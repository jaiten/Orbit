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
        note("n4", "Old recipe", "Lentil soup", { updatedAt: now - 3 * 86400000 }),
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
      addToCalendar: async (service, task) => (window.calendarAdds ||= []).push([service, task.title]),
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

  // A quick Ctrl chord while typing never flashes the Ctrl+1… labels…
  await capture.click();
  await p.keyboard.down("Control");
  await p.waitForTimeout(500);
  assert.equal(await p.evaluate(() => document.documentElement.classList.contains("ctrl-held")), false);
  // …but holding Ctrl on its own a moment longer shows them, even while writing.
  await p.waitForTimeout(400);
  assert.equal(await p.evaluate(() => document.documentElement.classList.contains("ctrl-held")), true);
  await p.keyboard.up("Control");

  // Notes: the toolbar keeps photo, copy and make-a-task behind ⋯.
  await p.keyboard.press("Control+4");
  await p.locator(".notes-nav-page", { hasText: "Groceries" }).first().click();
  // Pages sit under date headings, as on iOS: Today first, older pages after.
  await p.locator('.notes-nav-name[data-notes-home=""]').click();
  const headings = await p.locator(".notes-overview .note-date-heading").allInnerTexts();
  assert.deepEqual(headings, ["Today", "Previous 7 Days"]);
  const navHeadings = await p
    .locator(".notes-nav .notes-nav-pages")
    .first()
    .locator(".note-date-heading")
    .allInnerTexts();
  assert.deepEqual(navHeadings, ["Today", "Previous 7 Days"], "The sidebar's All list is dated too");
  if (shots) await p.screenshot({ path: path.join(shots, "notes-dated.png") });
  await p.locator("#search").fill("lentil");
  assert.deepEqual(await p.locator(".notes-overview .note-date-heading:visible").allInnerTexts(), ["Previous 7 Days"]);
  await p.locator("#search").fill("");
  await p.locator(".notes-nav-page", { hasText: "Groceries" }).first().click();
  await p.locator("#note-body").waitFor();
  assert.equal(await p.locator("#add-note-photo, [data-copy-note], [data-note-to-task]").count(), 0);
  await p.getByRole("button", { name: "More note options" }).click();
  for (const label of ["Add photo", "Copy text", "Move to section", "Make it a Task", "Lock note"])
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

  // Right-click a note: move it to another section, as on iOS.
  await p.locator(".notes-nav-page", { hasText: "Old recipe" }).first().click({ button: "right" });
  await p.getByRole("menuitem", { name: "Move to section", exact: true }).hover();
  await p.getByRole("menuitem", { name: "Journal", exact: true }).click();
  await until(
    async () => (await window.orbit.read()).records.find((r) => r.payload.id === "n4")?.payload.listID === "s1",
  );
  assert.ok((await record("n4")).updatedAt > Date.now() - 60000, "Moving counts as an edit");

  // Drag a page onto another section (here the sidebar's Private) to move it there.
  await p
    .locator(".notes-nav-page", { hasText: "Old recipe" })
    .first()
    .dragTo(p.locator('.sidebar-list[data-note-drop="s2"]'));
  await until(
    async () => (await window.orbit.read()).records.find((r) => r.payload.id === "n4")?.payload.listID === "s2",
  );
  // …and back again, onto a section in the notes list.
  await p
    .locator(".notes-nav-page", { hasText: "Old recipe" })
    .first()
    .dragTo(p.locator('.notes-nav-group[data-note-drop="s1"] .notes-nav-row'));
  await until(
    async () => (await window.orbit.read()).records.find((r) => r.payload.id === "n4")?.payload.listID === "s1",
  );

  // General holds only notes without a section: a filed note is listed under its section alone.
  assert.equal(
    await p.locator('.notes-nav-group[data-note-drop=""] .notes-nav-page', { hasText: "Old recipe" }).count(),
    0,
  );
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
  // The open locked page is swapped for a blank page to write on, not a lock screen.
  await until(() => document.querySelector("#note-title")?.value === "" && !document.querySelector(".locked-page"));
  assert.equal(await p.locator(".notes-nav-page", { hasText: "Groceries" }).count(), 0, "Locked titles are hidden");
  await p.locator(".notes-nav-page", { hasText: "Locked note" }).first().waitFor();
  const nav = await p.locator(".notes-nav").innerText();
  for (const secret of ["Secret plans", "Hidden thoughts", "Milk, eggs"])
    assert.equal(nav.includes(secret), false, secret);
  assert.equal(
    (await p.locator("#note-body").innerText()).includes("Milk"),
    false,
    "A locked note's text is not on the page",
  );
  await p.locator('.notes-nav-name[data-notes-home=""]').click();
  const overview = await p.locator(".notes-overview").innerText();
  for (const secret of ["Secret plans", "Surprise party", "Hidden thoughts", "Very private", "Milk, eggs"])
    assert.equal(overview.includes(secret), false, secret);
  if (shots) await p.screenshot({ path: path.join(shots, "notes-locked.png") });
  // Searching does not find them either.
  await p.locator("#search").fill("surprise");
  assert.equal(await p.locator(".note-card:not([hidden])").count(), 0);
  await p.locator("#search").fill("");

  // Opening a locked note asks for the password; a wrong one is refused.
  assert.equal(await p.locator(".note-card", { hasText: "Groceries" }).count(), 0, "No locked titles on cards");
  await p.locator(".note-card", { hasText: "Locked note" }).first().click();
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
  await until(() => document.querySelector("#note-title")?.value === "" && !document.querySelector(".locked-page"));
  assert.equal(await p.locator(".notes-nav-page", { hasText: "Secret plans" }).count(), 0);
  // Going to Notes from the sidebar never asks for the password, even when the last page was locked.
  await p.evaluate(() => localStorage.setItem("lastNoteID", "n1"));
  await p.locator('nav [data-page="today"]').click();
  await p.locator('nav [data-page="lists"]').click();
  await p.waitForTimeout(300);
  assert.equal(await p.locator("#lock-dialog[open]").count(), 0, "Notes opened without a password prompt");
  await p.locator("#note-title").waitFor();

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
  // An open page doesn't redraw the list under the writer; going to the overview does.
  await p.locator('.notes-nav-name[data-notes-home=""]').click();
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
  // A new section can be locked as it is made (a password already exists here).
  await p.keyboard.press("Control+4");
  await p.locator("[data-new-list]").first().click();
  await p.locator('#list-form input[name="name"]').fill("Vault");
  assert.equal(await p.locator("#list-lock-row").isVisible(), true);
  await p.locator('#list-form input[name="locked"]').check();
  await p.locator("#list-form").getByRole("button", { name: "Save", exact: true }).click();
  await until(async () =>
    (await window.orbit.read()).records.some((r) => r.payload.name === "Vault" && r.payload.locked === true),
  );
  // Dated tasks can go to Google Calendar, Outlook or the calendar app.
  await p.keyboard.press("Control+1");
  await p.locator("#inline-task-input").fill("Dentist at 11:59pm");
  await p.locator("#inline-task-input").press("Enter");
  await p.locator(".task-row", { hasText: "Dentist" }).click({ button: "right" });
  await p.getByRole("menuitem", { name: "Add to calendar", exact: true }).hover();
  await p.getByRole("menuitem", { name: "Google Calendar", exact: true }).click();
  assert.deepEqual(await p.evaluate(() => window.calendarAdds), [["google", "Dentist"]]);
  assert.equal(!!(await record("n1")).locked, true);

  // Sidebar order, as iOS's Tab order: move Notes up in Settings; Ctrl+1 follows the new order.
  const navOrder = () =>
    p.locator("nav[aria-label='Planner'] button[data-page]").evaluateAll((b) => b.map((x) => x.dataset.page));
  await p.keyboard.press("Control+6");
  for (let i = 0; i < 2; i++) await p.locator('[data-nav-move="lists"][data-step="-1"]').click();
  assert.deepEqual(await navOrder(), ["today", "lists", "calendar", "tasks", "habits"]);
  assert.equal(await p.locator('nav button[data-page="lists"] kbd').innerText(), "Ctrl+2");
  if (shots) await p.screenshot({ path: path.join(shots, "sidebar-order.png") });
  await p.locator("#content").click({ position: { x: 5, y: 5 } });
  await p.keyboard.press("Control+2");
  await p.locator(".notes-nav").waitFor();
  // Dragging in the sidebar works too.
  await p.locator('nav button[data-page="habits"]').dragTo(p.locator('nav button[data-page="today"]'));
  assert.deepEqual(await navOrder(), ["habits", "today", "lists", "calendar", "tasks"]);
  await p.keyboard.press("Control+6");
  await p.locator("#restore-nav-order").click();
  assert.deepEqual(await navOrder(), ["today", "calendar", "tasks", "lists", "habits"]);
  assert.deepEqual(errors, []);
  await browser.close();
  console.log(
    "PASS: note menu, move to section, right-click to task, locks, locked new section, hidden titles, chin, autocorrect, capture to note, calendar export, sidebar order",
  );
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
