// Notes features in the real page with a stand-in for the desktop API: the ⋯ menu, right-click to make
// a task, locked notes and sections, hidden sections, the chin, autocorrect and the capture that turns
// into a note. Run: node tests/notes-smoke.cjs (CHROMIUM_PATH may point at a Chromium build).
const { chromium } = require("playwright");
const assert = require("node:assert/strict");
const path = require("node:path");
const fs = require("node:fs");
const shots = process.env.ORBIT_SCREENSHOT_DIR;
(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_PATH || (fs.existsSync("/usr/bin/chromium") ? "/usr/bin/chromium" : undefined),
    args: ["--no-sandbox"],
  });
  const p = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  const errors = [];
  p.on("pageerror", (e) => errors.push(e.message));
  await p.addInitScript(() => {
    const now = Date.now();
    const note = (id, title, notes, extra = {}) => ({
      key: "tasks/" + id,
      payload: { id, title, notes, isNote: true, listID: null, photos: [], updatedAt: now, ...extra },
    });
    const data = {
      records: [
        {
          key: "preferences/00000000-0000-4000-8000-000000000002",
          payload: { id: "00000000-0000-4000-8000-000000000002", dayStartMinutes: 0, updatedAt: 1 },
        },
        {
          key: "lists/s1",
          payload: { id: "s1", name: "Journal", kind: "notes", color: "sage", sortOrder: 0, updatedAt: 1 },
        },
        {
          key: "lists/s2",
          payload: { id: "s2", name: "Private", kind: "notes", color: "rose", sortOrder: 1, updatedAt: 1 },
        },
        note("n1", "Groceries", "Milk, eggs and bread for the weekend"),
        note("n2", "Diary entry", "Today I felt great about the run", { listID: "s1" }),
        note("n3", "Secret plans", "Surprise party on Saturday", { listID: "s2" }),
      ],
      onboarded: true,
      configured: true,
      email: null,
      status: "Saved locally",
    };
    window.copiedTexts = [];
    let changed = () => {};
    const batch = async (changes) => {
      for (const record of changes) {
        const i = data.records.findIndex((r) => r.key === record.key);
        if (record.deleted) {
          if (i >= 0) data.records.splice(i, 1);
        } else if (i < 0) data.records.push(record);
        else data.records[i] = record;
      }
      changed();
    };
    window.orbit = {
      read: async () => structuredClone(data),
      onChange: (cb) => (changed = cb),
      onSyncStatus() {},
      copy: async (text) => window.copiedTexts.push(text),
      addNotePhoto: async () => ({ id: crypto.randomUUID(), contentType: "image/jpeg" }),
      copyNotePhoto: async () => {},
      onWake() {},
      onQuickAdd() {},
      onUpdateStatus() {},
      updates: async () => ({ status: "idle" }),
      reschedule() {},
      desktopSettings: async () => ({ notifications: true, shortcut: "", shortcuts: [""] }),
      // A stand-in spell checker: knows "becuase" is a slip for "because".
      spell: (word) => ({ misspelled: word === "togther", suggestions: word === "togther" ? ["together"] : [] }),
      batch,
      put: (key, payload, deleted = false) => batch([{ key, payload, deleted }]),
    };
  });
  await p.route("http://localhost:8123/**", (route) => {
    const file = path.resolve(__dirname, "../ui", new URL(route.request().url()).pathname.slice(1) || "index.html");
    return route.fulfill({
      body: fs.readFileSync(file),
      contentType: file.endsWith(".js") ? "text/javascript" : file.endsWith(".css") ? "text/css" : "text/html",
    });
  });
  // Polls an async check in the page (waitForFunction does not wait for a returned promise).
  const until = async (check, arg) => {
    for (let i = 0; i < 100; i++) {
      if (await p.evaluate(check, arg)) return;
      await p.waitForTimeout(100);
    }
    throw Error("Timed out waiting for " + check);
  };
  const record = (id) =>
    p.evaluate(async (id) => (await window.orbit.read()).records.find((r) => r.payload.id === id)?.payload, id);
  await p.goto("http://localhost:8123/index.html");
  await p.locator("h1").filter({ hasText: "Today" }).waitFor();

  // A long capture on Today unfolds into a note card without losing focus; Ctrl+Return saves it.
  const capture = p.locator("#inline-task-input");
  await capture.click();
  await p.keyboard.type("buy milk tomorrow");
  assert.equal(await p.locator(".inline-capture.note-form").count(), 0, "A short task stays a task");
  await p.keyboard.type(" and then think about how we could redo the garden");
  await p.locator(".inline-capture.note-form").waitFor();
  assert.equal(await p.evaluate(() => document.activeElement.id), "inline-task-input");
  await p.waitForTimeout(400);
  if (shots) await p.screenshot({ path: path.join(shots, "capture-note.png") });
  await p.keyboard.press("Enter");
  assert.match(await capture.inputValue(), /\n$/, "Return is a new line in a note");
  await p.keyboard.type("Plant herbs");
  await p.locator("#inline-note-title").fill("Weekend");
  await capture.press("Control+Enter");
  await until(async () =>
    (await window.orbit.read()).records.some((r) => r.payload.isNote && r.payload.title === "Weekend"),
  );
  assert.equal(await p.locator(".inline-capture.note-form").count(), 0);
  assert.equal(await capture.inputValue(), "");

  // Holding Ctrl while typing never flashes the Ctrl+1… labels.
  await capture.click();
  await p.keyboard.down("Control");
  await p.waitForTimeout(500);
  assert.equal(await p.evaluate(() => document.documentElement.classList.contains("ctrl-held")), false);
  await p.keyboard.up("Control");

  // Notes: the toolbar keeps photo, copy and make-a-task behind ⋯.
  await p.keyboard.press("Control+4");
  await p.locator(".notes-nav-page", { hasText: "Groceries" }).first().click();
  await p.locator("#note-body").waitFor();
  assert.equal(await p.locator("#add-note-photo, [data-copy-note], [data-note-to-task]").count(), 0);
  await p.getByRole("button", { name: "More note options" }).click();
  for (const label of ["Add photo", "Copy text", "Make it a Task", "Lock note"])
    await p.getByRole("menuitem", { name: label, exact: true }).waitFor();
  await p.getByRole("menuitem", { name: "Copy text", exact: true }).click();
  assert.equal((await p.evaluate(() => window.copiedTexts.at(-1))).startsWith("Groceries"), true);

  // Autocorrect: apostrophes, typos and a confident spell-checker fix.
  await p.locator("#note-body").click();
  await p.keyboard.press("Control+End");
  await p.keyboard.type(" i dont think teh shops are togther ");
  assert.match(await p.locator("#note-body").innerText(), /I don't think the shops are together $/);
  await p.keyboard.press("Control+z");
  assert.match(await p.locator("#note-body").innerText(), /togther $/, "Ctrl+Z takes the correction back");

  // Right-click a note: make it a task.
  await p.locator(".notes-nav-page", { hasText: "Diary entry" }).first().click({ button: "right" });
  await p.getByRole("menuitem", { name: "Make it a Task", exact: true }).click();
  await until(async () => {
    const task = (await window.orbit.read()).records.find((r) => r.payload.id === "n2")?.payload;
    return task && !task.isNote && !!task.localDate;
  });

  // Lock a note: the first lock asks for a password.
  await p.locator(".notes-nav-page", { hasText: "Groceries" }).first().click({ button: "right" });
  await p.getByRole("menuitem", { name: "Lock note", exact: true }).click();
  await p.locator("#lock-dialog[open]").waitFor();
  await p.locator("#lock-dialog").getByLabel("New password").fill("orbit");
  await p.locator("#lock-dialog").getByLabel("Confirm password").fill("orbit");
  await p.locator("#lock-dialog").getByRole("button", { name: "Set password" }).click();
  await until(async () =>
    (await window.orbit.read()).records.some((r) => r.payload.id === "n1" && r.payload.locked === true),
  );
  assert.ok(await p.evaluate(() => JSON.parse(localStorage.getItem("notesLock")).hash.length === 64));
  assert.equal(await p.evaluate(() => localStorage.getItem("notesLock").includes("orbit")), false);

  // Lock a section and hide another's titles.
  await p.locator('[data-section-menu="s2"]').first().click({ button: "right" });
  await p.getByRole("menuitem", { name: "Lock section", exact: true }).click();
  await until(async () => (await window.orbit.read()).records.some((r) => r.payload.id === "s2" && r.payload.locked));
  await p.locator('[data-section-menu="s1"]').first().click({ button: "right" });
  await p.getByRole("menuitem", { name: "Hide titles", exact: true }).click();
  await p.evaluate(() =>
    window.orbit.put("tasks/n4", {
      id: "n4",
      title: "Hidden thoughts",
      notes: "Very private",
      isNote: true,
      listID: "s1",
      photos: [],
      updatedAt: Date.now(),
    }),
  );
  await p.locator(".notes-nav-page.hidden-note").first().waitFor();

  // Minimising locks again: locked text, a locked section's pages and hidden titles stay out of view.
  await p.evaluate(() => {
    Object.defineProperty(document, "hidden", { configurable: true, get: () => true });
    document.dispatchEvent(new Event("visibilitychange"));
    Object.defineProperty(document, "hidden", { configurable: true, get: () => false });
  });
  await p.locator(".locked-page").waitFor();
  const nav = await p.locator(".notes-nav").innerText();
  for (const secret of ["Secret plans", "Hidden thoughts", "Milk, eggs"])
    assert.equal(nav.includes(secret), false, secret);
  assert.equal(await p.locator("#note-body").count(), 0, "A locked note's text is not on the page");
  await p.locator('[data-notes-home="all"]').click();
  const overview = await p.locator(".notes-overview").innerText();
  for (const secret of ["Secret plans", "Surprise party", "Hidden thoughts", "Very private", "Milk, eggs"])
    assert.equal(overview.includes(secret), false, secret);
  if (shots) await p.screenshot({ path: path.join(shots, "notes-locked.png") });
  // Searching does not find them either.
  await p.locator("#search").fill("surprise");
  assert.equal(await p.locator(".note-card:not([hidden])").count(), 0);
  await p.locator("#search").fill("");

  // Opening a locked note asks for the password; a wrong one is refused.
  await p.locator(".note-card", { hasText: "Groceries" }).click();
  await p.locator("#lock-dialog[open]").waitFor();
  await p.locator("#lock-dialog").getByLabel("Password", { exact: true }).fill("wrong");
  await p.locator("#lock-dialog").getByRole("button", { name: "Unlock" }).click();
  await p.locator(".lock-error", { hasText: "isn't right" }).waitFor();
  await p.locator("#lock-dialog").getByLabel("Password", { exact: true }).fill("orbit");
  await p.locator("#lock-dialog").getByRole("button", { name: "Unlock" }).click();
  await p.locator("#note-body").waitFor();
  assert.match(await p.locator("#note-body").innerText(), /Milk, eggs/);
  // Unlocked, the locked section's pages are listed again; Lock now hides them.
  await p.locator(".notes-nav-page", { hasText: "Secret plans" }).first().waitFor();
  await p.getByRole("button", { name: "Lock now" }).click();
  await p.locator(".locked-page").waitFor();
  assert.equal(await p.locator(".notes-nav-page", { hasText: "Secret plans" }).count(), 0);

  // The chin: typing at the end of a long note keeps the line well above the bottom edge.
  await p.evaluate(() =>
    window.orbit.put("tasks/n5", {
      id: "n5",
      title: "Long",
      notes: Array.from({ length: 80 }, (_, i) => `Line ${i + 1}`).join("\n"),
      isNote: true,
      listID: null,
      photos: [],
      updatedAt: Date.now(),
    }),
  );
  await p.locator(".notes-nav-page", { hasText: "Long" }).first().click();
  await p.locator("#note-body").click();
  await p.keyboard.press("Control+End");
  for (let i = 0; i < 4; i++) await p.keyboard.press("Enter");
  await p.keyboard.type("Still visible");
  await p.waitForTimeout(500);
  const caretBottom = await p.evaluate(() => getSelection().getRangeAt(0).getBoundingClientRect().bottom);
  assert.ok(caretBottom < 800 - 90, `caret at ${caretBottom}px should sit above the chin`);
  if (shots) await p.screenshot({ path: path.join(shots, "note-chin.png") });

  // A long capture on Habits becomes a note too.
  await p.keyboard.press("Escape");
  await p.keyboard.press("Control+5");
  await p
    .locator("#inline-task-input")
    .fill("remember to ask the coach about a gentler warm up routine before practice");
  await p.locator(".inline-capture.note-form").waitFor();
  await p.locator("#inline-task-input").press("Control+Enter");
  await until(async () =>
    (await window.orbit.read()).records.some(
      (r) => r.payload.isNote && r.payload.notes.startsWith("remember to ask the coach"),
    ),
  );
  assert.equal(!!(await record("n1")).locked, true);
  assert.deepEqual(errors, []);
  await browser.close();
  console.log("PASS: note menu, right-click to task, locks, hidden titles, chin, autocorrect, capture to note");
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
