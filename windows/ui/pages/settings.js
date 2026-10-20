function versionSummary(p, deleted) {
  if (deleted) return "Removed item";
  const repeat =
    { "FREQ=DAILY": "Daily", "FREQ=WEEKLY": "Weekly", "FREQ=MONTHLY": "Monthly" }[p.recurrenceRule] || "Custom";
  return [
    p.title || p.name || "Item",
    p.notes,
    p.localDate ? "Planned for " + p.localDate : "",
    p.count !== undefined ? p.count + " check-ins" : "",
    p.completedAt ? "Completed" : "",
    p.target ? p.target + " times " + (p.frequencyRule === "WEEKLY" ? "a week" : "a day") : "",
    p.tags?.length ? "Tags: " + p.tags.join(", ") : "",
    p.priority ? "Priority: " + ["Normal", "Low", "Medium", "High"][p.priority] : "",
    p.recurrenceRule ? "Repeat: " + repeat : "",
    p.subtasks?.length ? "Steps: " + p.subtasks.map((s) => (s.completed ? "✓ " : "") + s.title).join(", ") : "",
  ]
    .filter(Boolean)
    .join("\n");
}

function accountSection() {
  if (state.email)
    return `<p>${esc(state.email)}</p><button id="sync-now">Sync now</button><button id="show-devices">Devices & active sign-ins</button><button id="change-password">Change password</button><div id="devices-panel"></div><button id="signout">Sign out</button>`;
  const disabled = !state.configured ? "disabled" : "";
  return `<form id="account"><label>Email<input name="email" type="email" autocomplete="email" value="${esc(accountEmail)}" required></label><label>Password<input name="password" type="password" autocomplete="current-password" minlength="8" required></label><div><button class="primary" type="submit" ${disabled}>Sign in</button><button type="button" id="forgot-password">Forgot password?</button><button type="button" id="signup" ${disabled}>Create account</button></div></form><details class="confirmation"><summary>Email confirmation</summary><form id="confirm-account"><label>Confirmation code (if provided)<input name="code" autocomplete="one-time-code" inputmode="numeric" required></label><button class="primary">Confirm account</button><button type="button" id="resend-code">Resend confirmation email</button></form><p class="secondary">Open the newest confirmation email and tap its link, then sign in above. If your email provides a code, enter it here.</p></details>${!state.configured ? '<p class="secondary">Backend setup is still in progress. Everything you add is saved locally.</p>' : ""}`;
}

function renderSettings() {
  const accentButtons = Object.keys(accents)
    .map(
      (name) =>
        `<button data-accent="${name}" aria-pressed="${document.documentElement.dataset.accent === name}">${name[0].toUpperCase() + name.slice(1)}</button>`,
    )
    .join("");
  let html = `<h1>Settings</h1>
    <section class="settings-block"><h2>Accent</h2><div class="accent-options">${accentButtons}</div></section>
    <section class="settings-block">
      <h2>Account</h2>
      <p id="sync-details">${esc(state.status)}</p>
      <p class="secondary">Sign in with the same account on your iPhone to sync. Everything is saved on this PC first.</p>
      ${accountSection()}
    </section>`;
  for (const r of state.records.filter((r) => r.conflict)) {
    html += `<section class="conflict"><h2>Review two versions</h2><p class="secondary">Both versions are saved. Choose the content you want to keep.</p><div class="version-options"><div><h3>On this PC</h3><p class="version-text">${esc(versionSummary(r.payload, r.deleted))}</p><button data-resolve="${esc(r.key)}" data-choice="local">Use the version above</button></div><div><h3>From sync</h3><p class="version-text">${esc(versionSummary(r.conflict.payload, r.conflict.deleted))}</p><button data-resolve="${esc(r.key)}" data-choice="cloud">Use this synced version</button></div></div></section>`;
  }
  html += `<section class="settings-block"><h2>Data</h2><button id="export-backup">Export</button><button id="import-backup">Import</button><p class="secondary">Exports contain your tasks, lists and habit history. No account details are included.</p><div id="import-confirm"></div></section>`;
  return html;
}

function bindSettings() {
  document.querySelectorAll("button[data-accent]").forEach(
    (b) =>
      (b.onclick = () => {
        applyAccent(b.dataset.accent);
        render();
      }),
  );
  document
    .querySelectorAll("[data-resolve]")
    .forEach((b) => (b.onclick = () => action(() => api.resolve(b.dataset.resolve, b.dataset.choice))));
  if ($("#change-password")) $("#change-password").onclick = () => $("#password-editor").showModal();
  if ($("#forgot-password"))
    $("#forgot-password").onclick = () =>
      action(async () => {
        const email = $("#account").elements.email.value.trim();
        if (!email) throw Error("Enter your email first");
        showNotice(await api.auth("recover", email, ""));
      });
  if ($("#export-backup"))
    $("#export-backup").onclick = () =>
      action(async () => {
        const message = await api.backup("export");
        if (message) showNotice(message);
      });
  if ($("#import-backup"))
    $("#import-backup").onclick = async () => {
      try {
        const count = await api.backup("choose");
        if (count === null) return;
        const panel = $("#import-confirm");
        panel.innerHTML = `<p>Import ${count} items? Matching items will be replaced; other items stay.</p><button id="confirm-import">Import and merge</button><button id="cancel-import">Cancel</button>`;
        $("#cancel-import").onclick = () => panel.replaceChildren();
        $("#confirm-import").onclick = () => action(async () => showNotice(await api.backup("restore")));
      } catch (e) {
        showNotice(e.message);
      }
    };
  if ($("#show-devices")) $("#show-devices").onclick = () => void showDevices().catch((e) => showNotice(e.message));
  if ($("#confirm-account")) {
    $("#confirm-account").onsubmit = (e) => {
      e.preventDefault();
      void action(() => confirmAccount("verify"));
    };
    $("#resend-code").onclick = () => action(() => confirmAccount("resend"));
  }
  if ($("#sync-now")) $("#sync-now").onclick = () => action(() => api.sync());
  if ($("#signout")) $("#signout").onclick = () => action(() => api.auth("out"));
  if ($("#account")) {
    const auth = (mode) => {
      const f = $("#account");
      if (!f.reportValidity()) return;
      const email = f.elements.email.value.trim(),
        password = f.elements.password.value;
      accountEmail = email;
      action(async () => {
        const message = await api.auth(mode, email, password);
        if (message !== "Signed in") showNotice(message);
      });
    };
    $("#account").onsubmit = (e) => {
      e.preventDefault();
      auth("in");
    };
    $("#signup").onclick = () => auth("up");
  }
}

async function confirmAccount(mode) {
  const email = $("#account").elements.email.value.trim();
  accountEmail = email;
  if (!email || !$("#account").elements.email.reportValidity()) return;
  if (mode === "resend" && Date.now() < resendAfter)
    throw Error("Please wait a minute before requesting another code.");
  const code = $("#confirm-account").elements.code.value;
  if (mode === "verify" && !code.trim()) throw Error("Enter the newest confirmation code from your email.");
  const message = await api.auth(mode, email, code);
  if (mode === "resend") resendAfter = Date.now() + 60000;
  if (message !== "Signed in") showNotice(message);
}

async function showDevices() {
  const devices = await api.devices();
  const panel = $("#devices-panel");
  if (!panel) return;
  panel.innerHTML =
    `<h3>${devices.length} active sign-ins</h3><p class="secondary">Removing access blocks Orbit sync. Downloaded data stays on the device. A device can have multiple sign-ins.</p>` +
    devices
      .map(
        (d) =>
          `<div class="device-row"><span>${esc(d.name)}${d.current ? " · This device" : ""}<small class="secondary">Last active ${esc(new Date(d.last_seen).toLocaleString())}</small></span>${d.current ? "" : `<button data-remove-device="${esc(d.id)}">Remove access</button>`}</div>`,
      )
      .join("");
  panel.querySelectorAll("[data-remove-device]").forEach(
    (b) =>
      (b.onclick = async () => {
        if (b.dataset.confirm !== "yes") {
          b.dataset.confirm = "yes";
          b.textContent = "Confirm removal";
          return;
        }
        try {
          b.disabled = true;
          await api.removeDevice(b.dataset.removeDevice);
          await showDevices();
        } catch (e) {
          showNotice(e.message);
          b.disabled = false;
        }
      }),
  );
}
