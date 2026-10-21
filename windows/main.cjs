const { app, BrowserWindow, ipcMain, safeStorage, session, protocol, net, dialog, powerMonitor } = require("electron");
const { confirmationNotice } = require("./auth-links.cjs");
const { PlannerTools, encodeBackup, decodeBackup, planImport, encodeTasksCSV } = require("./planner-tools.cjs");
const { SOMEDAY_LIST_ID } = require("./ui/planner.js");
const { createHash, randomBytes } = require("node:crypto");
const path = require("node:path");
const fs = require("node:fs");
const { pathToFileURL } = require("node:url");
const { Store } = require("./store.cjs");
const { Sync } = require("./sync.cjs");
const { runMigrations } = require("./migrations.cjs");
const { setupDesktop } = require("./desktop.cjs");
const { createClient } = require("@supabase/supabase-js");
const config = require("./config.json");
protocol.registerSchemesAsPrivileged([
  { scheme: "orbit", privileges: { standard: true, secure: true, supportFetchAPI: true } },
]);
if (process.env.ORBIT_TEST_DATA) app.setPath("userData", process.env.ORBIT_TEST_DATA);
let window,
  store,
  sync,
  client,
  accountNotice,
  plannerTools,
  pendingBackup,
  pendingRecoveryURL,
  recoveryReady = false,
  desktop;
let recoveryHandler;
const handleConfirmation = (raw) => {
  const notice = confirmationNotice(raw);
  if (!notice) return;
  const candidate = new URL(raw);
  if (candidate.searchParams.has("code")) {
    pendingRecoveryURL = raw;
    if (recoveryHandler) void recoveryHandler();
    return;
  }
  accountNotice = notice;
  if (window) {
    if (window.isMinimized()) window.restore();
    window.show();
    window.focus();
    window.webContents.send("changed");
  }
};
if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on("second-instance", (_, argv) => {
    for (const arg of argv) handleConfirmation(arg);
    if (window) {
      if (window.isMinimized()) window.restore();
      window.show();
      window.focus();
    }
  });
  app.on("open-url", (event, url) => {
    event.preventDefault();
    handleConfirmation(url);
  });
}
for (const arg of process.argv) handleConfirmation(arg);
app.whenReady().then(async () => {
  if (app.isPackaged && !process.env.ORBIT_TEST_DATA)
    app.setAsDefaultProtocolClient("orbit", process.env.PORTABLE_EXECUTABLE_FILE || process.execPath);
  store = new Store(path.join(app.getPath("userData"), "orbit.sqlite"));
  // Lets the desktop smoke test simulate sync conflicts; only set for test data folders.
  if (process.env.ORBIT_TEST_DATA) global.orbitTestStore = store;
  const migrate = () => {
    try {
      return runMigrations(store) > 0;
    } catch (e) {
      console.error("Migration skipped:", e.message);
      return false;
    }
  };
  migrate();
  // People who already have plans skip the first-launch screens. Tests skip them unless ORBIT_ONBOARDING is set.
  if (!store.setting("onboarded") && store.rows().length) store.setting("onboarded", "yes");
  const onboarded = () =>
    store.setting("onboarded") === "yes" || (!!process.env.ORBIT_TEST_DATA && !process.env.ORBIT_ONBOARDING);
  const notify = (kind = "data") => {
    if (kind === "status") window?.webContents.send("sync-status", { status: sync.status, syncing: sync.busy });
    else {
      // Records from older devices may still contain repeating tasks.
      if (migrate()) void sync.run();
      desktop?.scheduler.reschedule();
      window?.webContents.send("changed");
    }
  };
  const tokenPath = path.join(app.getPath("userData"), "session.enc");
  const authKey = config.url
    ? "sb-" + new URL(config.url).hostname.split(".")[0] + "-auth-token"
    : "orbit-local-auth-token";
  const storagePath = (key) =>
    key === authKey
      ? tokenPath
      : path.join(app.getPath("userData"), "auth-" + createHash("sha256").update(key).digest("hex") + ".enc");
  const storage = {
    getItem: (key) => {
      const file = storagePath(key);
      return fs.existsSync(file) ? safeStorage.decryptString(fs.readFileSync(file)) : null;
    },
    setItem: (key, v) => {
      if (!safeStorage.isEncryptionAvailable()) throw Error("Windows credential encryption is unavailable");
      const file = storagePath(key);
      fs.writeFileSync(file + ".tmp", safeStorage.encryptString(v));
      fs.renameSync(file + ".tmp", file);
    },
    removeItem: (key) => {
      const file = storagePath(key);
      if (fs.existsSync(file)) fs.unlinkSync(file);
    },
  };
  if (config.url && config.publishableKey)
    client = createClient(config.url, config.publishableKey, {
      auth: { storage, autoRefreshToken: true, persistSession: true, detectSessionInUrl: false },
    });
  sync = new Sync(store, client, notify);
  plannerTools = new PlannerTools(store);
  recoveryHandler = async () => {
    const raw = pendingRecoveryURL;
    pendingRecoveryURL = null;
    if (!raw || !client) return;
    try {
      const pending = JSON.parse(storage.getItem(authKey + "-orbit-recovery") || "null");
      if (!pending) {
        accountNotice = confirmationNotice(raw);
        notify();
        return;
      }
      if (Date.now() - pending.created > 3600000)
        throw Error("Request a new recovery email on this PC and open its link here.");
      const url = new URL(raw),
        code = url.searchParams.get("code");
      if (!/^[A-Za-z0-9_-]{16,2048}$/.test(code || "")) throw Error("Invalid recovery link");
      const response = await fetch(config.url + "/auth/v1/token?grant_type=pkce", {
        method: "POST",
        headers: { apikey: config.publishableKey, "Content-Type": "application/json" },
        body: JSON.stringify({ auth_code: code, code_verifier: pending.verifier }),
      });
      const result = await response.json();
      if (!response.ok) throw Error(result.msg || result.error_description || "Recovery link could not be verified");
      if (
        !result.access_token ||
        !result.refresh_token ||
        result.user?.email?.toLowerCase() !== pending.email.toLowerCase()
      )
        throw Error("Recovery email did not match this request.");
      const { data, error } = await client.auth.setSession({
        access_token: result.access_token,
        refresh_token: result.refresh_token,
      });
      if (error) throw error;
      try {
        store.bind(data.user.id);
      } catch (e) {
        await client.auth.signOut({ scope: "local" });
        throw e;
      }
      recoveryReady = true;
      storage.removeItem(authKey + "-orbit-recovery");
      accountNotice = "Choose a new password below.";
    } catch (e) {
      accountNotice = e.message;
    }
    notify();
    if (window) {
      window.show();
      window.focus();
    }
  };
  protocol.handle("orbit", (request) => {
    const url = new URL(request.url);
    const ui = path.join(__dirname, "ui");
    const file = path.join(ui, url.pathname === "/" ? "index.html" : decodeURIComponent(url.pathname));
    if (
      url.host !== "app" ||
      !file.startsWith(ui + path.sep) ||
      !/\.(html|js|css|svg)$/.test(file) ||
      !fs.existsSync(file)
    )
      return new Response("Not found", { status: 404 });
    return net.fetch(pathToFileURL(file).href);
  });
  session.defaultSession.setPermissionRequestHandler((_, __, callback) => callback(false));
  window = new BrowserWindow({
    width: 1240,
    height: 860,
    minWidth: 820,
    minHeight: 620,
    title: "Orbit",
    backgroundColor: "#EBEBEE",
    icon: path.join(__dirname, "assets", "orbit.png"),
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  window.webContents.on("will-navigate", (e) => e.preventDefault());
  const handle = (name, fn) =>
    ipcMain.handle(name, async (event, arg) => {
      if (event.senderFrame !== window.webContents.mainFrame || !event.senderFrame.url.startsWith("orbit://app/"))
        throw Error("Invalid sender");
      return fn(arg);
    });
  handle("devices", async () => {
    if (!client) throw Error("Sign in first");
    const { data, error } = await client.rpc("orbit_devices_list", { p_name: "Windows PC" });
    if (error) throw error;
    return data;
  });
  handle("remove-device", async (id) => {
    if (!client || typeof id !== "string") throw Error("Invalid request");
    const { data, error } = await client.rpc("orbit_device_remove", { p_session: id });
    if (error) throw error;
    return data;
  });
  handle("read", async () => {
    const notice = accountNotice;
    accountNotice = null;
    return {
      records: store.rows(),
      undoAvailable: plannerTools.available,
      undoCreatedAt: plannerTools.last?.created,
      undoKind: plannerTools.last?.kind,
      recoveryReady,
      accountNotice: notice,
      status: sync.status,
      syncing: sync.busy,
      configured: !!client,
      onboarded: onboarded(),
      email: (await client?.auth.getSession())?.data?.session?.user?.email ?? null,
    };
  });
  handle("put", ({ key, payload, deleted }) => {
    plannerTools.change([{ key, payload, deleted: deleted === true }]);
    notify();
    void sync.run();
  });
  handle("batch", (changes) => {
    plannerTools.change(changes);
    notify();
    void sync.run();
  });
  handle("sync", () => sync.run());
  handle("onboarded", () => void store.setting("onboarded", "yes"));
  handle("resolve", ({ key, choice }) => {
    store.resolve(key, choice);
    return sync.run();
  });
  handle("undo", () => {
    plannerTools.undo();
    notify();
    void sync.run();
  });
  const saveFile = async (defaultPath, name, extension, text) => {
    const { canceled, filePath } = await dialog.showSaveDialog(window, {
      defaultPath,
      filters: [{ name, extensions: [extension] }],
    });
    if (canceled || !filePath) return false;
    const temporary = filePath + "." + randomBytes(8).toString("hex") + ".tmp";
    try {
      fs.writeFileSync(temporary, text, { encoding: "utf8", flag: "wx" });
      fs.renameSync(temporary, filePath);
    } finally {
      if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
    }
    return true;
  };
  handle("backup", async (request) => {
    const { mode, replaceChanged } = typeof request === "string" ? { mode: request } : request || {};
    const day = new Date().toLocaleDateString("en-CA");
    if (mode === "export")
      return (await saveFile(`Orbit-${day}.json`, "Orbit export", "json", encodeBackup(store.rows())))
        ? "Exported"
        : null;
    if (mode === "export-csv")
      // The byte-order mark lets Excel read accented characters correctly.
      return (await saveFile(
        `Orbit-tasks-${day}.csv`,
        "CSV",
        "csv",
        "\uFEFF" + encodeTasksCSV(store.rows(), SOMEDAY_LIST_ID),
      ))
        ? "Tasks exported"
        : null;
    if (mode === "choose") {
      const { canceled, filePaths } = await dialog.showOpenDialog(window, {
        properties: ["openFile"],
        filters: [{ name: "Orbit export", extensions: ["json"] }],
      });
      if (canceled) return null;
      if (fs.statSync(filePaths[0]).size > 50000000) throw Error("This file is too large");
      pendingBackup = planImport(store.rows(), decodeBackup(fs.readFileSync(filePaths[0], "utf8")));
      const title = (r) => r.payload.title || r.payload.name || r.payload.dayKey || "Item";
      return {
        added: pendingBackup.added.length,
        same: pendingBackup.same.length,
        changed: pendingBackup.changed.map((r) => ({ key: r.key, title: title(r) })),
      };
    }
    if (mode === "restore" && pendingBackup) {
      const chosen = [...pendingBackup.added, ...(replaceChanged === true ? pendingBackup.changed : [])];
      plannerTools.change(
        chosen.map((r) => ({ ...r, payload: { ...r.payload, updatedAt: Date.now() } })),
        "imported",
      );
      pendingBackup = null;
      notify();
      void sync.run();
      return chosen.length
        ? `Imported ${chosen.length} ${chosen.length === 1 ? "item" : "items"}`
        : "Nothing new to import";
    }
    throw Error("Choose a file first");
  });
  handle("auth", async ({ mode, email, password }) => {
    if (!client) throw Error("Sync backend is not configured yet");
    if (mode === "recover") {
      if (typeof email !== "string" || !email.trim()) throw Error("Email required");
      const verifier = randomBytes(32).toString("base64url"),
        challenge = createHash("sha256").update(verifier).digest("base64url");
      storage.setItem(
        authKey + "-orbit-recovery",
        JSON.stringify({ email: email.trim(), verifier, created: Date.now() }),
      );
      const response = await fetch(config.url + "/auth/v1/recover?redirect_to=orbit%3A%2F%2Fauth", {
        method: "POST",
        headers: { apikey: config.publishableKey, "Content-Type": "application/json" },
        body: JSON.stringify({ email: email.trim(), code_challenge: challenge, code_challenge_method: "s256" }),
      });
      if (!response.ok) {
        const body = await response.json();
        throw Error(body.msg || body.message || "Recovery email could not be requested");
      }
      return "If this account exists, a recovery email is on its way. Open it on this PC.";
    }
    if (mode === "password") {
      if (typeof password !== "string" || password.length < 8) throw Error("Use at least 8 characters");
      const { error } = await client.auth.updateUser({ password });
      if (error) throw error;
      recoveryReady = false;
      notify();
      return "Password changed";
    }
    if (mode === "out") {
      await client.auth.signOut({ scope: "local" });
      sync.status = "Saved on this PC";
      notify();
      return;
    }
    if (
      !["in", "up", "resend", "verify"].includes(mode) ||
      typeof email !== "string" ||
      (mode !== "resend" && typeof password !== "string")
    )
      throw Error("Invalid sign-in request");
    email = email.trim();
    if (mode === "resend") {
      const { error } = await client.auth.resend({
        type: "signup",
        email,
        options: { emailRedirectTo: "orbit://auth" },
      });
      if (error) throw error;
      return "If this account needs confirmation, a fresh confirmation email is on its way.";
    }
    const result = await (mode === "verify"
      ? client.auth.verifyOtp({ email, token: password.trim(), type: "email" })
      : mode === "up"
        ? client.auth.signUp({ email, password, options: { emailRedirectTo: "orbit://auth" } })
        : client.auth.signInWithPassword({ email, password }));
    if (result.error) throw result.error;
    if (result.data.session) {
      accountNotice = null;
      try {
        store.bind(result.data.user.id);
      } catch (e) {
        await client.auth.signOut({ scope: "local" });
        throw e;
      }
      await client.rpc("orbit_devices_list", { p_name: "Windows PC" });
      await sync.run();
    }
    return result.data.session ? "Signed in" : "Open the newest confirmation email, tap its link, then sign in here.";
  });
  const registerDevice = async () => {
    try {
      if ((await client?.auth.getSession())?.data?.session)
        await client.rpc("orbit_devices_list", { p_name: "Windows PC" });
    } catch {
      /* Offline access remains available. */
    }
  };
  void registerDevice();
  setInterval(() => void registerDevice(), 300000).unref();
  handle("desktop-settings", (changes) => (changes ? desktop.update(changes) : desktop.settings()));
  // The page reports its time zone (it notices changes reliably); reminders are re-planned in that zone.
  handle("reschedule", (zone) => {
    if (typeof zone === "string" && /^[A-Za-z0-9_+\-/]{1,64}$/.test(zone) && zone !== process.env.TZ)
      process.env.TZ = zone;
    desktop.scheduler.reschedule();
  });
  app.setAppUserModelId("com.orbit.planner");
  desktop = setupDesktop({ window, store, iconPath: path.join(__dirname, "assets", "orbit.png") });
  if (process.env.ORBIT_TEST_DATA) global.orbitTestDesktop = desktop;
  await window.loadURL("orbit://app");
  if (pendingRecoveryURL) void recoveryHandler();
  window.on("focus", () => void sync.run());
  // A sleeping PC can miss midnight; tell the page to re-check the day.
  for (const event of ["resume", "unlock-screen"])
    powerMonitor.on(event, () => {
      window?.webContents.send("wake");
      desktop?.scheduler.reschedule();
    });
  setInterval(() => void sync.run(), 20000).unref();
  if (client) {
    client
      .channel("planner")
      .on("postgres_changes", { event: "*", schema: "public", table: "orbit_records" }, () => void sync.run())
      .subscribe((status) => {
        if (status === "SUBSCRIBED") void sync.run();
      });
    void sync.run();
  }
});
app.on("window-all-closed", () => app.quit());
app.on("before-quit", () => store?.close());
