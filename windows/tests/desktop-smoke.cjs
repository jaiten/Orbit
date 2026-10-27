const { _electron: electron } = require("playwright");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
// Windows can hold the database open briefly after the app quits; cleanup must never hide a real failure.
const remove = (folder) => {
  try {
    fs.rmSync(folder, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
  } catch (e) {
    console.warn("Could not remove", folder, e.code);
  }
};
(async () => {
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), "orbit-ui-"));
  const options = {
    executablePath: require("electron"),
    args: [path.resolve(__dirname, "..")],
    env: { ...process.env, ORBIT_TEST_DATA: folder },
  };
  let app;
  try {
    app = await electron.launch(options);
    const p = await app.firstWindow();
    const quickAdd = async (text, preview) => {
      await p.getByRole("button", { name: "Task options", exact: true }).first().click();
      await p.getByRole("textbox", { name: "Quick add" }).fill(text);
      if (preview) await p.locator("#quick-add-preview").getByText(preview, { exact: true }).waitFor();
      await p.getByRole("button", { name: "Add", exact: true }).click();
    };
    const errors = [];
    p.on("pageerror", (e) => errors.push(e.message));
    await p.getByRole("heading", { name: "Today", exact: true, level: 1 }).waitFor();
    // Homepage capture stays inline and keeps the draft field ready for another item.
    await p.getByRole("textbox", { name: "New task", exact: true }).fill("Inline walk");
    await p.getByRole("textbox", { name: "New task", exact: true }).press("Enter");
    await p.getByRole("checkbox", { name: "Complete Inline walk", exact: true }).waitFor();
    if (await p.locator("dialog[open]").count()) throw Error("Inline capture opened a dialog");
    if (await p.getByRole("textbox", { name: "New task", exact: true }).inputValue())
      throw Error("Inline draft did not clear");
    await p.getByRole("button", { name: "Edit Inline walk", exact: true }).click();
    await p.getByRole("button", { name: "Delete", exact: true }).click();
    const weekly = "22222222-2222-4222-8222-222222222222";
    await p.evaluate(async (id) => {
      const now = new Date(),
        yesterday = new Date();
      yesterday.setDate(now.getDate() - 1);
      const key = (d) =>
        `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
      await window.orbit.batch([
        {
          key: "habits/" + id,
          payload: {
            id,
            title: "Gym weekly test",
            frequencyRule: "WEEKLY",
            target: 5,
            color: "sage",
            icon: "leaf",
            createdAt: Date.now(),
            updatedAt: Date.now(),
          },
        },
        {
          key: "habit_logs/" + id + "-" + key(yesterday),
          payload: { id: crypto.randomUUID(), habitID: id, dayKey: key(yesterday), count: 1, updatedAt: Date.now() },
        },
      ]);
    }, weekly);
    await p.getByRole("checkbox", { name: "Log Gym weekly test", exact: true }).click();
    await p.getByRole("checkbox", { name: "Undo Gym weekly test", exact: true }).waitFor();
    await p.getByRole("checkbox", { name: "Undo Gym weekly test", exact: true }).click();
    await p.getByRole("checkbox", { name: "Log Gym weekly test", exact: true }).waitFor();
    // History shows every habit at once; each still links to its check-ins.
    await p.locator('[data-page="habits"]').click();
    await p.getByRole("button", { name: /^History/ }).click();
    await p.getByRole("heading", { name: "History", exact: true }).waitFor();
    await p.getByRole("button", { name: "Gym weekly test 1 of the last 7 days →", exact: true }).waitFor();
    if ((await p.locator('.habit-history .box-grid i[data-o]:not([data-o="0"])').count()) !== 1)
      throw Error("History grid is missing a check-in");
    await p.getByRole("button", { name: "Gym weekly test 1 of the last 7 days →", exact: true }).click();
    await p.getByRole("heading", { name: "Gym weekly test", exact: true }).waitFor();
    await p.getByText("1 check-in", { exact: true }).waitFor();
    await p.locator('[data-page="today"]').click();
    await p.evaluate(async (id) => {
      const all = await window.orbit.read();
      await window.orbit.batch(
        all.records
          .filter((r) => r.payload.id === id || r.payload.habitID === id)
          .map((r) => ({ key: r.key, payload: r.payload, deleted: true })),
      );
    }, weekly);
    await p.getByRole("button", { name: "+ New section", exact: true }).first().click();
    await p.locator("#list-form input[name=name]").fill("Personal");
    await p.getByRole("button", { name: "Save", exact: true }).click();
    // The list order controls persist positions, including after saving the editor.
    await p.getByRole("button", { name: "+ New section", exact: true }).first().click();
    await p.locator("#list-form input[name=name]").fill("Temporary list");
    await p.getByRole("button", { name: "Save", exact: true }).click();
    await p.getByRole("button", { name: "Edit Temporary list section", exact: true }).click();
    await p.getByRole("button", { name: "Move section up", exact: true }).click();
    await p.getByRole("button", { name: "Save", exact: true }).click();
    const listOrder = await p.locator("#sidebar-lists [data-list]").allTextContents();
    if (listOrder.indexOf("Temporary list") > listOrder.indexOf("Personal")) throw Error("List order did not persist");
    await p.getByRole("button", { name: "Edit Temporary list section", exact: true }).click();
    await p.getByRole("button", { name: "Delete section", exact: true }).click();
    await p.getByRole("button", { name: "Delete Section, Keep Items", exact: true }).click();
    await quickAdd("Read for twenty minutes", "Task · Today");
    await p.getByRole("button", { name: "Edit Read for twenty minutes", exact: true }).click();
    await p.getByText("More options", { exact: true }).click();
    await p.getByLabel("Notes", { exact: true }).fill("A small, clear commitment");
    await p.getByLabel("Section", { exact: true }).selectOption({ label: "Personal" });
    await p.getByRole("button", { name: "Save", exact: true }).click();
    await p.getByRole("button", { name: "Personal", exact: true }).click();
    await p.getByRole("heading", { name: "Personal", exact: true }).waitFor();
    await p.getByRole("button", { name: "Edit Read for twenty minutes", exact: true }).waitFor();
    await p.locator('[data-page="today"]').click();
    // Sync updates never close or clear an open quick add.
    await p.keyboard.press("Control+n");
    await p.getByRole("textbox", { name: "Quick add" }).fill("Morning walk every day");
    await app.evaluate(({ BrowserWindow }) => {
      for (let i = 0; i < 5; i++)
        BrowserWindow.getAllWindows()[0].webContents.send("sync-status", {
          status: i % 2 ? "All changes synced" : "Syncing…",
          syncing: i % 2 === 0,
        });
    });
    if (!(await p.locator("#quick-add-dialog").evaluate((el) => el.open))) throw Error("Sync closed quick add");
    await p.locator("#quick-add-preview").getByText("Habit · Daily", { exact: true }).waitFor();
    await p.getByRole("button", { name: "Add", exact: true }).click();
    await p.getByRole("checkbox", { name: "Log Morning walk", exact: true }).click();
    await p.getByText("1 of 1 today", { exact: true }).waitFor();
    await p.getByRole("checkbox", { name: "Undo Morning walk", exact: true }).click();
    await p.getByText("0 of 1 today", { exact: true }).waitFor();
    await p.getByRole("button", { name: "Edit Read for twenty minutes", exact: true }).click();
    await p.getByRole("button", { name: "Make it a Habit", exact: true }).click();
    // Habits on Today log on click; right-click edits them.
    await p.getByRole("checkbox", { name: "Log Read for twenty minutes", exact: true }).click({ button: "right" });
    await p.getByRole("menuitem", { name: "Edit…", exact: true }).click();
    await p.getByRole("button", { name: "Make it a Task", exact: true }).click();
    await p.getByRole("button", { name: "Edit Read for twenty minutes", exact: true }).click();
    if ((await p.getByLabel("Notes", { exact: true }).inputValue()) !== "A small, clear commitment")
      throw Error("Conversion lost notes");
    await p.getByRole("button", { name: "Save", exact: true }).click();
    // A repeating task from an older device becomes a habit with the same ID.
    const original = await p.evaluate(async () => {
      const s = await window.orbit.read();
      return s.records.find((r) => r.key.startsWith("tasks/") && !r.deleted);
    });
    await p.evaluate(async (r) => {
      await window.orbit.put(r.key, { ...r.payload, recurrenceRule: "FREQ=DAILY" });
    }, original);
    await p.getByRole("checkbox", { name: "Log Read for twenty minutes", exact: true }).waitFor();
    const migrated = await p.evaluate(async (id) => {
      const s = await window.orbit.read();
      return s.records.find((r) => r.key === "habits/" + id && !r.deleted);
    }, original.payload.id);
    if (migrated?.payload.frequencyRule !== "DAILY") throw Error("Repeating task did not become a daily habit");
    await p.getByRole("checkbox", { name: "Log Read for twenty minutes", exact: true }).click({ button: "right" });
    await p.getByRole("menuitem", { name: "Edit…", exact: true }).click();
    await p.getByRole("button", { name: "Make it a Task", exact: true }).click();
    await p.getByRole("checkbox", { name: "Complete Read for twenty minutes" }).click();
    const restored = await p.evaluate(
      async (id) => (await window.orbit.read()).records.find((r) => r.key === "tasks/" + id),
      original.payload.id,
    );
    if (restored.payload.recurrenceRule) throw Error("Make it a Task restored a repeat");
    await p.getByText("1 completed", { exact: true }).waitFor();
    await p.getByRole("button", { name: "Settings", exact: true }).click();
    await p.getByRole("heading", { name: "Settings", exact: true }).waitFor();
    await p.getByRole("button", { name: "Dark", exact: true }).click();
    if ((await p.locator("html").getAttribute("data-appearance")) !== "dark") throw Error("Appearance did not change");
    await p.getByRole("button", { name: "System", exact: true }).click();
    await p.getByRole("button", { name: "Sage", exact: true }).click();
    if ((await p.locator("html").getAttribute("data-accent")) !== "sage") throw Error("Theme did not change");
    await p.getByRole("button", { name: "Coral", exact: true }).click();
    await p.locator("[data-edit-list]").click();
    await p.getByRole("button", { name: "Delete section", exact: true }).click();
    await p.getByRole("button", { name: "Delete Section, Keep Items", exact: true }).click();
    const afterDelete = await p.evaluate(() => window.orbit.read());
    if (afterDelete.records.some((r) => r.key.startsWith("tasks/") && !r.deleted && r.payload.listID))
      throw Error("Deleted list left orphaned to-dos");
    if (!afterDelete.records.some((r) => r.key.startsWith("tasks/") && !r.deleted))
      throw Error("Deleting list deleted its to-dos");
    await p.locator('[data-page="today"]').click();
    await app.evaluate(({ app }) => app.emit("second-instance", {}, ["orbit://auth#error_code=otp_expired"]));
    await p
      .getByText(
        "That confirmation link is invalid or expired. Request a fresh email in Settings and use the newest link.",
        { exact: true },
      )
      .waitFor();
    await p.getByRole("heading", { name: "Account" }).waitFor();
    await p.getByRole("button", { name: "Dismiss message" }).click();
    await p.locator('[data-page="today"]').click();
    for (const title of ["Wash car", "Call Mom"]) {
      await quickAdd(title);
      await p.getByRole("checkbox", { name: "Complete " + title, exact: true }).waitFor();
    }
    // Rows spring into place; measure once they have settled.
    await p.evaluate(() => Promise.all(document.getAnimations().map((a) => a.finished.catch(() => {}))));
    const first = await p.getByRole("checkbox", { name: "Complete Wash car", exact: true }).boundingBox();
    const second = await p.getByRole("checkbox", { name: "Complete Call Mom", exact: true }).boundingBox();
    // Rows stack one per line, as in docs/mockups/windows-today.png (the website layout).
    if (second.y <= first.y || Math.abs(first.x - second.x) > 2) throw Error("Today rows do not stack");
    // Keyboard: pages, focused-item toggle/edit/delete, help, search.
    await p.keyboard.press("Control+2");
    // Calendar: a week of day tiles; the arrows move a week and Today comes back.
    await p.getByRole("group", { name: "Days" }).waitFor();
    const firstDay = () => p.locator(".day-tile").first().getAttribute("data-day");
    const thisWeek = await firstDay();
    await p.getByRole("button", { name: "Next month" }).click();
    if ((await firstDay()) === thisWeek) throw Error("Next month did not move the calendar");
    await p.locator(".week-nav .today-button").click();
    if ((await firstDay()) !== thisWeek) throw Error("Today did not return to this week");
    await p.keyboard.press("Control+1");
    // Clear any earlier Undo (a move a moment ago), then tick: ticking never offers Undo.
    await p.evaluate(() => {
      const box = document.querySelector("#undo-toast");
      if (!box.hidden) document.querySelector("#dismiss-undo").click();
    });
    await p.locator("#undo-toast").waitFor({ state: "hidden" });
    await p.getByRole("checkbox", { name: "Complete Wash car", exact: true }).focus();
    await p.keyboard.press("Space");
    await p.getByRole("checkbox", { name: "Reopen Wash car", exact: true }).waitFor();
    if (!(await p.evaluate(() => document.activeElement?.getAttribute("aria-label")))?.startsWith("Reopen Wash car"))
      throw Error("Focus left the toggled item");
    await p.keyboard.press("Enter");
    await p.getByRole("checkbox", { name: "Complete Wash car", exact: true }).waitFor();
    await p.waitForTimeout(300);
    if (await p.locator("#undo-toast").isVisible()) throw Error("Undo appeared for a tick");
    await p.keyboard.press("e");
    await p.locator("#editor[open]").waitFor();
    await p.keyboard.press("Escape");
    await p.locator("#editor[open]").waitFor({ state: "detached" });
    await p.getByRole("checkbox", { name: "Complete Call Mom", exact: true }).focus();
    await p.keyboard.press("Delete");
    await p.getByRole("checkbox", { name: "Complete Call Mom", exact: true }).waitFor({ state: "detached" });
    await p.getByRole("button", { name: "Undo", exact: true }).click();
    await p.getByRole("checkbox", { name: "Complete Call Mom", exact: true }).waitFor();
    await p.keyboard.press("Control+/");
    await p.getByRole("heading", { name: "Keyboard Shortcuts", exact: true }).waitFor();
    await p.keyboard.press("Escape");
    await p.locator('[data-page="tasks"]').click();
    await p.getByRole("searchbox", { name: "Search tasks" }).fill("mom");
    if (!(await p.getByRole("checkbox", { name: "Complete Call Mom", exact: true }).isVisible()))
      throw Error("Search hid the match");
    if (await p.getByRole("checkbox", { name: "Complete Wash car", exact: true }).isVisible())
      throw Error("Search kept a non-match");
    await p.getByRole("searchbox", { name: "Search tasks" }).fill("");
    await p.keyboard.press("Control+1");
    // Reminders: one timer for the next reminder, re-planned after every change.
    const soon = Date.now() + 120000;
    await p.evaluate(async (at) => {
      const r = (await window.orbit.read()).records.find((r) => r.payload.title === "Wash car");
      await window.orbit.put(r.key, { ...r.payload, reminders: [at] });
    }, soon);
    const next = await app.evaluate(() => global.orbitTestDesktop.scheduler.next);
    if (next?.title !== "Wash car" || next.at !== soon)
      throw Error("Reminder was not scheduled: " + JSON.stringify(next));
    // Global quick-add shortcut: on by default, changeable and can be turned off.
    if (!(await app.evaluate(({ globalShortcut }) => globalShortcut.isRegistered("CommandOrControl+Shift+Space"))))
      throw Error("Global shortcut not registered");
    await p.getByRole("button", { name: "Settings", exact: true }).click();
    await p.getByLabel("Quick add shortcut").selectOption({ label: "Off" });
    await p.waitForFunction(async () => (await window.orbit.desktopSettings()).shortcut === "");
    if (await app.evaluate(({ globalShortcut }) => globalShortcut.isRegistered("CommandOrControl+Shift+Space")))
      throw Error("Global shortcut still registered when off");
    await p.getByLabel("Quick add shortcut").selectOption({ label: "Ctrl + Shift + Space" });
    await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].webContents.send("quick-add"));
    await p.getByRole("textbox", { name: "Quick add" }).waitFor();
    await p.keyboard.press("Escape");
    await p.locator('[data-page="today"]').click();
    // A sync conflict shows a small banner on Today that leads to Review.
    const conflictKey = await p.evaluate(async () => {
      const r = (await window.orbit.read()).records.find((r) => r.payload.title === "Call Mom");
      return r.key;
    });
    await app.evaluate(({ BrowserWindow }, key) => {
      const row = global.orbitTestStore.rows().find((r) => r.key === key);
      global.orbitTestStore.accept({
        key,
        payload: { ...row.payload, title: "Call Mum" },
        deleted: false,
        revision: 5,
        mutation: "remote",
      });
      BrowserWindow.getAllWindows()[0].webContents.send("changed");
    }, conflictKey);
    await p.getByRole("button", { name: "1 item has two versions to review →", exact: true }).click();
    await p.getByRole("heading", { name: "Review", exact: true }).waitFor();
    await p.locator(".version-text", { hasText: "Call Mum" }).waitFor();
    await p.getByRole("button", { name: "Keep This Version", exact: true }).nth(1).click();
    await p.getByText("Nothing to review.", { exact: true }).waitFor();
    await p.locator('[data-page="today"]').click();
    await p.getByRole("checkbox", { name: "Complete Call Mum", exact: true }).waitFor();
    // Overdue items offer Today / Later / Someday; Someday keeps them off Today until added back.
    await p.evaluate(async () => {
      const id = crypto.randomUUID(),
        d = new Date();
      d.setDate(d.getDate() - 2);
      const localDate = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
      await window.orbit.put("tasks/" + id, {
        id,
        title: "Renew passport",
        notes: "",
        listID: null,
        localDate,
        dueDate: null,
        hasTime: false,
        durationMinutes: 30,
        reminders: [],
        recurrenceRule: "",
        priority: 0,
        tags: [],
        subtasks: [],
        completedAt: null,
        sortOrder: Date.now(),
        updatedAt: Date.now(),
      });
    });
    const overdue = p.locator(".check-tile", { hasText: "Renew passport" });
    await overdue.getByText(/^from /).waitFor();
    await overdue.getByRole("button", { name: "Someday", exact: true }).click();
    await overdue.waitFor({ state: "detached" });
    await p.locator(`[data-list="00000000-0000-4000-8000-000000000001"]`).click();
    await p.getByRole("heading", { name: "Someday", exact: true }).waitFor();
    await p.getByRole("button", { name: "Add to Today", exact: true }).click();
    await p.locator('[data-page="today"]').click();
    await p.getByRole("checkbox", { name: "Complete Renew passport", exact: true }).waitFor();
    const someday = await p.evaluate(async () =>
      (await window.orbit.read()).records.find((r) => r.key === "lists/00000000-0000-4000-8000-000000000001"),
    );
    if (someday?.payload.name !== "Someday") throw Error("Someday list was not created");
    await p.getByRole("button", { name: "Task options", exact: true }).first().click();
    await p.getByRole("textbox", { name: "Quick add" }).fill("Plan picnic tomorrow 1pm #weekend");
    await p.locator("#quick-add-preview").getByText("Task · Tomorrow · 1:00 PM · #weekend", { exact: true }).waitFor();
    await p.getByRole("button", { name: "More details…", exact: true }).click();
    await p.evaluate(async () => {
      const r = (await window.orbit.read()).records.find((r) => r.payload.title === "Wash car");
      await window.orbit.put(r.key, { ...r.payload, notes: "Synced while the editor is open" });
    });
    if ((await p.locator("#task-form input[name=title]").inputValue()) !== "Plan picnic")
      throw Error("Details lost the title");
    await p.getByRole("button", { name: "Cancel", exact: true }).click();
    // Adding to a list keeps the task undated in that list, off Today.
    await p.getByRole("button", { name: "Someday", exact: true }).first().click();
    // Task categories open in Tasks; Ctrl+N adds to the selected category.
    await p.keyboard.press("Control+n");
    await p.getByRole("textbox", { name: "Quick add" }).fill("Learn the cello");
    await p.locator("#quick-add-preview").getByText("Someday", { exact: true }).waitFor();
    await p.getByRole("button", { name: "Add", exact: true }).click();
    await p.getByRole("checkbox", { name: "Complete Learn the cello", exact: true }).waitFor();
    await p.locator('[data-page="today"]').click();
    if (await p.getByRole("checkbox", { name: "Complete Learn the cello" }).count())
      throw Error("Someday item shown on Today");
    // Long text in the add field grows it and becomes a note, never a to-do; the page edits in place.
    const capture = p.getByRole("textbox", { name: "New task", exact: true });
    const shortHeight = (await capture.boundingBox()).height;
    await capture.fill(
      "Garden ideas. Plant tomatoes along the south fence and move the herbs closer to the kitchen door so they get used more often.",
    );
    await p.locator("#inline-preview").getByText("Note", { exact: true }).waitFor();
    if ((await capture.boundingBox()).height <= shortHeight + 10) throw Error("Add field did not grow");
    await capture.press("Enter");
    await p.waitForFunction(async () =>
      (await window.orbit.read()).records.some((r) => r.payload.isNote && r.payload.title === "Garden ideas"),
    );
    if (await p.getByRole("checkbox", { name: /Garden ideas/ }).count()) throw Error("A note showed as a to-do");
    // Return on an empty field leaves it.
    await capture.focus();
    await capture.press("Enter");
    if (await p.evaluate(() => document.activeElement?.id === "inline-task-input"))
      throw Error("Empty Return kept focus");
    if (await p.locator("#inline-receipt").textContent()) throw Error("A success message appeared");
    await p.locator('[data-page="lists"]').click();
    await p.getByRole("heading", { name: "Notes", exact: true, level: 1 }).waitFor();
    await p.locator(".note-card", { hasText: "Garden ideas" }).click();
    await p.getByRole("textbox", { name: "Note text" }).fill("Tomatoes by the fence. Herbs by the door.");
    await p.getByRole("textbox", { name: "Note title" }).fill("Garden plan");
    // Esc saves and returns to the overview; the page is in the notes sidebar too.
    await p.getByRole("textbox", { name: "Note title" }).press("Escape");
    await p.locator(".notes-nav-page", { hasText: "Garden plan" }).waitFor();
    await p.locator(".note-card", { hasText: "Garden plan" }).click({ button: "right" });
    await p.getByRole("menuitem", { name: "Copy text", exact: true }).click();
    const copied = await app.evaluate(({ clipboard }) => clipboard.readText());
    if (copied !== "Garden plan\n\nTomatoes by the fence. Herbs by the door.") throw Error("Copy text: " + copied);
    // Typing with nothing focused starts something: a page on Notes, a task on Today. Shortcuts don't.
    await p.evaluate(() => document.activeElement?.blur());
    await p.keyboard.type("Packing list");
    await p.getByRole("textbox", { name: "Note title" }).waitFor();
    if ((await p.getByRole("textbox", { name: "Note title" }).inputValue()) !== "Packing list")
      throw Error("Typing did not start a page");
    await p.keyboard.press("Escape");
    await p.waitForFunction(async () =>
      (await window.orbit.read()).records.some((r) => r.payload.isNote && r.payload.title === "Packing list"),
    );
    // The Notes bottom bar writes a note, even a short one.
    await p.getByRole("textbox", { name: "New task", exact: true }).fill("Gift ideas");
    await p.locator("#inline-preview").getByText("Note", { exact: true }).waitFor();
    await p.getByRole("textbox", { name: "New task", exact: true }).press("Enter");
    await p.locator(".note-card", { hasText: "Gift ideas" }).waitFor();
    await p.locator('[data-page="today"]').click();
    await p.evaluate(() => document.activeElement?.blur());
    await p.keyboard.press("Control+2");
    await p.keyboard.press("Control+1");
    if (await p.getByRole("textbox", { name: "New task", exact: true }).inputValue())
      throw Error("A shortcut started a task");
    await p.keyboard.type("Water plants");
    if ((await p.getByRole("textbox", { name: "New task", exact: true }).inputValue()) !== "Water plants")
      throw Error("Typing did not start a task");
    await p.keyboard.press("Enter");
    await p.getByRole("checkbox", { name: "Complete Water plants", exact: true }).waitFor();
    await p.getByRole("textbox", { name: "New task", exact: true }).press("Enter");
    // Every task, including Someday, is reachable from Tasks; Calendar keeps Week and Month.
    if (await p.getByRole("tab", { name: "All", exact: true }).count()) throw Error("Today still has view tabs");
    await p.locator('[data-page="tasks"]').click();
    await p.getByRole("heading", { name: "Tasks", exact: true }).waitFor();
    await p.getByRole("checkbox", { name: "Complete Learn the cello", exact: true }).waitFor();
    await p.locator('[data-page="calendar"]').click();
    await p.getByRole("tab", { name: "Week", exact: true }).click();
    await p.getByRole("heading", { name: "This week", exact: true }).waitFor();
    await p.getByRole("tab", { name: "Month", exact: true }).click();
    await p.getByRole("group", { name: "Days" }).waitFor();
    await p.locator('[data-page="today"]').click();
    await p.getByRole("button", { name: "Settings", exact: true }).click();
    const backupFile = path.join(folder, "planner-backup.json");
    await app.evaluate(({ dialog }, file) => {
      dialog.showSaveDialog = async () => ({ canceled: false, filePath: file });
      dialog.showOpenDialog = async () => ({ canceled: false, filePaths: [file] });
    }, backupFile);
    await p.getByRole("button", { name: "Export Everything (JSON)", exact: true }).click();
    await p.getByText("Exported", { exact: true }).waitFor();
    const backup = JSON.parse(fs.readFileSync(backupFile, "utf8"));
    if (backup.version !== 2) throw Error("Export is not version 2");
    backup.records.find((r) => r.payload.title === "Wash car").payload.title = "Wash car restored";
    fs.writeFileSync(backupFile, JSON.stringify(backup));
    // Preview first; a differing item is only replaced when chosen.
    await p.getByRole("button", { name: "Import…", exact: true }).click();
    await p.getByText("1 item differs from yours:").waitFor();
    await p.getByRole("button", { name: "Import", exact: true }).click();
    await p.getByText("Nothing new to import", { exact: true }).waitFor();
    await p.getByRole("button", { name: "Import…", exact: true }).click();
    await p.getByLabel("Replace it with the imported version").check();
    await p.getByRole("button", { name: "Import", exact: true }).click();
    await p.getByText("Imported 1 item", { exact: true }).waitFor();
    await p.locator('[data-page="today"]').click();
    await p.getByRole("checkbox", { name: "Complete Wash car restored", exact: true }).waitFor();
    const csvFile = path.join(folder, "tasks.csv");
    await app.evaluate(({ dialog }, file) => {
      dialog.showSaveDialog = async () => ({ canceled: false, filePath: file });
    }, csvFile);
    await p.getByRole("button", { name: "Settings", exact: true }).click();
    await p.getByRole("button", { name: "Export Tasks (CSV)", exact: true }).click();
    await p.getByText("Tasks exported", { exact: true }).waitFor();
    if (!fs.readFileSync(csvFile, "utf8").includes("Wash car restored,Inbox,")) throw Error("CSV is missing a task");
    await p.locator('[data-page="today"]').click();
    await p.getByRole("button", { name: "Undo", exact: true }).click();
    await p.getByRole("checkbox", { name: "Complete Wash car", exact: true }).waitFor();
    await p.emulateMedia({ colorScheme: "dark", reducedMotion: "reduce" });
    await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setSize(900, 700));
    if (await p.evaluate(() => document.documentElement.scrollWidth > innerWidth))
      throw Error("Horizontal overflow at compact window size");
    await p.getByRole("button", { name: "Add a task", exact: true }).first().waitFor();
    await p.emulateMedia({ colorScheme: "light" });
    await app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows()[0].setSize(1320, 900));
    await p.screenshot({ path: path.resolve(__dirname, "../assets/desktop-preview.png"), fullPage: true });
    if (errors.length) throw Error(errors.join("\n"));
    // Completed is a lasting user preference, including across an actual app restart.
    await p.locator(".completed-items").evaluate((details) => {
      details.open = false;
    });
    await p.waitForFunction(() => localStorage.getItem("todayCompletedExpanded") === "false");
    await app.close();
    app = await electron.launch(options);
    const q = await app.firstWindow();
    await q.getByText("1 completed", { exact: true }).waitFor();
    if (await q.locator(".completed-items").evaluate((details) => details.open))
      throw Error("Completed did not remember collapsed state after restart");
    await q.locator(".completed-items > summary").click();
    await q.waitForFunction(() => localStorage.getItem("todayCompletedExpanded") === "true");
    await q.reload();
    await q.locator(".completed-items").waitFor();
    if (!(await q.locator(".completed-items").evaluate((details) => details.open)))
      throw Error("Completed did not remember expanded state after reload");
    await q.getByText("0 of 1 today", { exact: true }).waitFor();
    const late = new Date();
    late.setHours(23, 59, 0, 0);
    await q.clock.install({ time: late });
    await q.evaluate(async () => {
      const id = "33333333-3333-4333-8333-333333333333";
      await window.orbit.put("habits/" + id, {
        id,
        title: "Midnight gym",
        frequencyRule: "WEEKLY",
        target: 5,
        color: "sage",
        icon: "leaf",
        createdAt: Date.now(),
        updatedAt: Date.now(),
      });
    });
    await q.getByRole("checkbox", { name: "Log Midnight gym", exact: true }).click();
    await q.getByRole("checkbox", { name: "Undo Midnight gym", exact: true }).waitFor();
    await q.clock.setSystemTime(new Date(late.getTime() + 120000));
    await q.evaluate(() => window.dispatchEvent(new Event("focus")));
    await q.getByRole("checkbox", { name: "Log Midnight gym", exact: true }).waitFor();
    await app.close();

    // First launch: onboarding is skipped above; here it is switched on for fresh data folders.
    const fresh = fs.mkdtempSync(path.join(os.tmpdir(), "orbit-first-"));
    const folders = [fresh];
    const firstRun = { ...options, env: { ...options.env, ORBIT_TEST_DATA: fresh, ORBIT_ONBOARDING: "1" } };
    try {
      app = await electron.launch(firstRun);
      let w = await app.firstWindow();
      const welcome = w.locator("#onboarding");
      await welcome.getByRole("heading", { name: "Welcome to Orbit" }).waitFor();
      // Skipping is an × in the corner; the footer buttons sit in the same place on every step.
      await welcome.getByRole("button", { name: "Skip setup", exact: true }).waitFor();
      await w.evaluate(() => Promise.all(document.getAnimations().map((a) => a.finished.catch(() => {}))));
      const primaryBox = await welcome.locator(".onboarding-primary").boundingBox();
      await welcome.getByRole("textbox", { name: "Quick add" }).fill("dentist tomorrow 9am");
      await welcome.locator("#onboarding-preview").getByText("Task · Tomorrow", { exact: false }).waitFor();
      await welcome.getByRole("button", { name: "Add", exact: true }).click();
      await welcome.getByRole("heading", { name: "Pick a habit or two" }).waitFor();
      await w.evaluate(() => Promise.all(document.getAnimations().map((a) => a.finished.catch(() => {}))));
      const nextBox = await welcome.locator(".onboarding-primary").boundingBox();
      if (Math.abs(nextBox.x - primaryBox.x) > 1 || Math.abs(nextBox.y - primaryBox.y) > 1)
        throw Error("Onboarding buttons moved between steps: " + JSON.stringify([primaryBox, nextBox]));
      await welcome.getByRole("button", { name: /^Stretch/ }).click();
      await welcome.getByRole("button", { name: "Continue", exact: true }).click();
      await welcome.getByRole("heading", { name: "Stay in sync" }).waitFor();
      await welcome.getByRole("button", { name: "Not Now", exact: true }).click();
      await w.getByRole("checkbox", { name: "Log Stretch", exact: true }).waitFor();
      if (!(await w.evaluate(() => window.orbit.read())).records.some((r) => r.payload.title === "dentist"))
        throw Error("Onboarding quick add did not save");
      await app.close();
      app = await electron.launch(firstRun);
      w = await app.firstWindow();
      await w.getByRole("checkbox", { name: "Log Stretch", exact: true }).waitFor();
      if (await w.locator("#onboarding").isVisible()) throw Error("Onboarding showed twice");
      await app.close();

      const another = fs.mkdtempSync(path.join(os.tmpdir(), "orbit-examples-"));
      folders.push(another);
      app = await electron.launch({ ...firstRun, env: { ...firstRun.env, ORBIT_TEST_DATA: another } });
      w = await app.firstWindow();
      await w.getByRole("button", { name: "Start with Examples", exact: true }).click();
      await w.getByRole("button", { name: "Not Now", exact: true }).click();
      await w.getByRole("button", { name: "Set Up Sync", exact: true }).click();
      await w.getByRole("heading", { name: "Account", exact: true }).waitFor();
      await w.locator('[data-page="today"]').click();
      await w.getByRole("checkbox", { name: "Complete Morning walk", exact: true }).waitFor();
      await w.getByRole("checkbox", { name: "Log Drink water", exact: true }).click();
      await w.locator('[data-page="settings"]').click();
      await w.getByRole("button", { name: "Remove Examples", exact: true }).click();
      await w.locator('[data-page="today"]').click();
      await w.getByRole("heading", { name: "Today", exact: true, level: 1 }).waitFor();
      const left = (await w.evaluate(() => window.orbit.read())).records.filter(
        (r) => !r.deleted && r.key !== "lists/00000000-0000-4000-8000-000000000001",
      );
      if (left.length) throw Error("Examples left behind: " + left.map((r) => r.key).join(", "));
      // Progress stays in the existing row, survives restart, and only Finish completes it.
      await w.getByRole("textbox", { name: "New task", exact: true }).fill("Laundry");
      await w.getByRole("textbox", { name: "New task", exact: true }).press("Enter");
      const laundryRow = w
        .locator(".task-row")
        .filter({ has: w.getByRole("button", { name: "Edit Laundry", exact: true }) });
      await laundryRow.waitFor();
      const ordinaryHeight = (await laundryRow.boundingBox()).height;
      await w.getByLabel("Progress options for Laundry", { exact: true }).click();
      await w.getByRole("button", { name: "Track start & finish", exact: true }).click();
      await w.getByRole("checkbox", { name: "Start Laundry", exact: true }).click();
      await w.getByRole("checkbox", { name: "Finish Laundry", exact: true }).waitFor();
      if (Math.abs((await laundryRow.boundingBox()).height - ordinaryHeight) > 1)
        throw Error("Starting expanded the task row");
      const startedTask = (await w.evaluate(() => window.orbit.read())).records.find(
        (r) => r.payload.title === "Laundry",
      ).payload;
      if (!startedTask.startedAt || startedTask.completedAt) throw Error("Start did not preserve an incomplete task");
      await app.close();
      app = await electron.launch({ ...firstRun, env: { ...firstRun.env, ORBIT_TEST_DATA: another } });
      w = await app.firstWindow();
      await w.getByRole("checkbox", { name: "Finish Laundry", exact: true }).waitFor();
      await w.getByLabel("Progress options for Laundry", { exact: true }).click();
      await w.getByRole("button", { name: "Reset progress", exact: true }).click();
      await w.getByRole("checkbox", { name: "Start Laundry", exact: true }).click();
      await w.getByRole("checkbox", { name: "Finish Laundry", exact: true }).click();
      const finishedTask = (await w.evaluate(() => window.orbit.read())).records.find(
        (r) => r.payload.title === "Laundry",
      ).payload;
      if (!finishedTask.completedAt) throw Error("Finish did not complete the task");
    } finally {
      if (app) await app.close();
      app = null;
      folders.forEach(remove);
    }
    console.log(
      "PASS: onboarding, examples, conversion round trip,  native desktop lists, task editing/completion, habit log/undo, compact dark layout, settings and offline restart",
    );
  } finally {
    if (app) await app.close();
    remove(folder);
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
