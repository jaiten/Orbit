const { chromium } = require("playwright");
const assert = require("node:assert/strict");
const path = require("node:path");
const fs = require("node:fs");
(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_PATH || (fs.existsSync("/usr/bin/chromium") ? "/usr/bin/chromium" : undefined),
    args: ["--no-sandbox"],
  });
  const p = await browser.newPage();
  const errors = [];
  p.on("pageerror", (e) => errors.push(e.message));
  await p.addInitScript(() => {
    const data = { records: [], onboarded: true, configured: true, email: null, status: "Saved locally" };
    window.authCalls = [];
    window.copiedTexts = [];
    let updateState = { status: "idle", currentVersion: "0.3.4", version: null, percent: 0 };
    window.updateInstalls = 0;
    window.updateChecks = 0;
    let changed = () => {};
    let settings = { notifications: true, shortcut: "", shortcuts: ["", "Control+Space"] };
    const batch = async (changes) => {
      if (window.failWrite) throw Error("Test disk unavailable");
      for (const record of changes) {
        const i = data.records.findIndex((r) => r.key === record.key);
        if (i < 0) data.records.push(record);
        else data.records[i] = record;
      }
      changed();
    };
    window.orbit = {
      read: async () => {
        if (window.holdRead) {
          window.readWaiting = true;
          await new Promise((resolve) => {
            (window.readReleases ||= []).push(resolve);
            window.releaseRead = () => window.readReleases.splice(0).forEach((release) => release());
          });
          window.readWaiting = false;
        }
        return structuredClone(data);
      },
      onChange: (cb) => (changed = cb),
      onSyncStatus(cb) {
        window.emitSync = (value) => {
          data.status = value.status;
          data.syncing = value.syncing;
          cb(value);
        };
      },
      copy: async (text) => {
        window.copiedTexts.push(text);
      },
      addNotePhoto: async () => ({ id: crypto.randomUUID(), contentType: "image/jpeg" }),
      copyNotePhoto: async () => {},
      onWake() {},
      onQuickAdd() {},
      onUpdateStatus(cb) {
        window.emitUpdate = (value) => {
          updateState = { ...updateState, ...value };
          cb(structuredClone(updateState));
        };
      },
      updates: async (command) => {
        if (command === "check") {
          window.updateChecks++;
          if (["idle", "current", "error"].includes(updateState.status))
            window.emitUpdate({ status: "current", version: null });
        }
        if (command === "install") {
          window.updateInstalls++;
          window.emitUpdate({ status: "installing" });
        }
        return structuredClone(updateState);
      },
      reschedule() {},
      desktopSettings: async (changes) => (settings = { ...settings, ...changes }),
      auth: async (mode, email) => {
        window.authCalls.push({ mode, email });
        return "Signed in";
      },
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
  await p.goto("http://localhost:8123/index.html");
  await p.locator("h1").filter({ hasText: "Today" }).waitFor();
  assert.equal(await p.locator("#home-update").isVisible(), false);
  await p.evaluate(() => window.emitUpdate({ status: "downloading", version: "0.3.5", percent: 12 }));
  assert.equal(await p.locator("#home-update").isVisible(), true);
  await p.evaluate(() => window.emitUpdate({ status: "current", version: "0.3.5" }));
  assert.equal(await p.locator("#home-update").isVisible(), false);
  await p.evaluate(() => window.emitUpdate({ status: "idle", version: null }));

  assert.equal(await p.locator("[data-sidebar-note-heading]").count(), 0);
  assert.equal(await p.locator('nav [data-page="settings"]').count(), 0);
  const settingsGear = p.locator('.sidebar-footer [data-page="settings"]');
  const gearBox = await settingsGear.boundingBox();
  const syncBox = await p.locator("#sync-status").boundingBox();
  assert.ok(gearBox.x >= syncBox.x + syncBox.width && Math.abs(gearBox.y - syncBox.y) < 8);
  await p.locator('[data-page="settings"]').click();
  for (const accent of ["teal", "blue"]) {
    await p.locator(`button[data-accent="${accent}"]`).click();
    assert.equal(await p.locator("html").getAttribute("data-accent"), accent);
    assert.equal(await p.locator(`button[data-accent="${accent}"]`).getAttribute("aria-pressed"), "true");
  }
  await p.locator('button[data-accent="coral"]').click();
  await p.getByRole("combobox", { name: "Overall progress range", exact: true }).click();
  await p.getByRole("option", { name: "Past week", exact: true }).click();
  assert.equal(await p.evaluate(() => localStorage.getItem("overallProgressRange")), "7");
  await p.getByRole("combobox", { name: "Overall progress range", exact: true }).click();
  await p.getByRole("option", { name: "Past month", exact: true }).click();
  assert.equal(await p.evaluate(() => localStorage.getItem("overallProgressRange")), "30");

  await p.locator("#compact-rows").check();
  assert.equal(await p.locator("html").getAttribute("data-compact"), "true");
  await p.locator("#notifications-toggle").uncheck();
  await p.locator('[data-appearance="dark"]').click();
  assert.equal(await p.locator("html").getAttribute("data-appearance"), "dark");
  await p.getByRole("button", { name: "Account Sign in" }).click();
  await p.locator('#account input[name="email"]').fill("tester@example.com");
  await p.locator('#account input[name="password"]').press("Enter");
  assert.equal(await p.evaluate(() => window.authCalls.length), 0, "Enter still validates the form");
  for (const field of ["password", "email"]) {
    await p.locator('#account input[name="email"]').fill("tester@example.com");
    await p.locator('#account input[name="password"]').fill("test-password");
    const calls = await p.evaluate(() => window.authCalls.length);
    await p.locator(`#account input[name="${field}"]`).press("Enter");
    await p.waitForFunction((count) => window.authCalls.length === count + 1, calls);
    await p.waitForTimeout(100);
    assert.deepEqual(await p.evaluate(() => window.authCalls.at(-1)), { mode: "in", email: "tester@example.com" });
  }
  await p.getByRole("button", { name: "Back to settings" }).click();
  assert.equal(await p.locator("h1").innerText(), "Settings");
  await p.locator('[data-page="today"]').click();
  await p.keyboard.press("ArrowLeft");
  assert.notEqual(await p.locator("h1").innerText(), "Today");
  await p.keyboard.press("ArrowDown");
  assert.equal(await p.locator("h1").innerText(), "Today");
  await p.locator("#inline-task-input").fill("Visit Japan someday");
  await p.locator("#inline-task-input").press("Enter");
  await p.locator('[data-page="tasks"]').click();
  await p.getByRole("button", { name: "Edit Visit Japan", exact: true }).waitFor();
  await p.getByRole("combobox", { name: "Show tasks" }).click();
  assert.equal((await p.locator("#task-scope-options").innerText()).includes("✓"), false);
  assert.equal(await p.locator("#task-scope-options [aria-selected=true]").innerText(), "All tasks");
  await p.getByRole("option", { name: "Someday", exact: true }).click();
  await p.getByRole("button", { name: "Edit Visit Japan", exact: true }).waitFor();
  const taskRow = p.locator(".task-row").filter({ hasText: "Visit Japan" });
  await taskRow.hover();
  await taskRow.getByRole("button", { name: "Edit task: Visit Japan", exact: true }).click();
  assert.equal(await p.locator("#task-form input[name=title]").inputValue(), "Visit Japan");
  await p.mouse.click(230, 50);
  assert.equal(await p.locator("dialog[open]").count(), 0);
  await taskRow.hover();
  await taskRow.getByRole("button", { name: "Delete Visit Japan", exact: true }).click();
  await taskRow.waitFor({ state: "detached" });
  await p.locator('[data-page="lists"]').click();
  assert.equal(
    await p.evaluate(() => document.scrollingElement.scrollHeight <= document.scrollingElement.clientHeight),
    true,
    "A short note needs no page scrollbar",
  );
  await p
    .locator("#note-title")
    .fill("A wrapped note title with enough words to fill several lines without clipping the caret");
  assert.equal(
    await p
      .locator("#note-title")
      .evaluate((field) => field.scrollHeight <= field.clientHeight && field.scrollTop === 0),
    true,
    "All title lines fit without scrolling the caret into a clipped edge",
  );
  await p.locator("#note-title").fill("");
  await p.keyboard.type("My new note");
  assert.equal(await p.locator("#note-title").inputValue(), "My new note");
  await p.waitForTimeout(800);
  await p.keyboard.type(" continues");
  assert.equal(await p.locator("#note-title").inputValue(), "My new note continues");
  if (process.env.ORBIT_SCREENSHOT)
    await p.screenshot({ path: process.env.ORBIT_SCREENSHOT.replace(".png", "-title.png") });
  await p.locator("#note-body").fill("A long note line\n".repeat(80));
  assert.equal(
    await p.evaluate(() => document.scrollingElement.scrollHeight > document.scrollingElement.clientHeight),
    true,
    "Long notes still scroll normally",
  );
  await p.locator("#note-body").fill("");
  await p.getByRole("button", { name: "Back to notes", exact: false }).click();
  await p.locator('[data-page="habits"]').click();
  await p.locator("#inline-task-input").fill("Drink water");
  await p.locator("#inline-task-input").press("Enter");
  await p.getByRole("checkbox", { name: "Log Drink water", exact: true }).waitFor();
  assert.equal(
    await p.evaluate(() => document.scrollingElement.scrollHeight <= document.scrollingElement.clientHeight),
    true,
    "A short habit list needs no page scrollbar",
  );
  // An icon chosen on iPhone is retained through a Windows edit, but never rendered as emoji.
  await p.evaluate(async () => {
    // eslint-disable-next-line no-undef
    const habit = rows("habits")[0];
    await window.orbit.put(habit._key, { ...habit, icon: "drop" });
  });
  await p.waitForTimeout(250);
  await p.mouse.move(0, 0);
  const habitRow = p.locator(".habit-row").filter({ hasText: "Drink water" });
  assert.equal((await habitRow.innerText()).includes("💧"), false);
  await p.waitForFunction(() => getComputedStyle(document.querySelector(".habit-row .row-actions")).opacity === "0");
  const countBounds = await habitRow.locator(".row-detail").boundingBox();
  const rowBounds = await habitRow.boundingBox();
  assert.ok(rowBounds.x + rowBounds.width - countBounds.x - countBounds.width <= 16, "Count hugs the right edge");
  const titleBeforeHover = await habitRow.locator(".row-title").boundingBox();
  await habitRow.hover();
  await p.waitForFunction(() => getComputedStyle(document.querySelector(".habit-row .row-actions")).opacity === "1");
  assert.deepEqual(
    await habitRow.locator(".row-title").boundingBox(),
    titleBeforeHover,
    "Hover must not move or resize the text",
  );
  if (process.env.ORBIT_SCREENSHOT)
    await p.screenshot({ path: process.env.ORBIT_SCREENSHOT.replace(".png", "-hover.png") });
  await habitRow.getByRole("button", { name: "Edit habit: Drink water", exact: true }).click();
  assert.equal(await p.locator('#habit-form input[name="icon"]').inputValue(), "drop");
  assert.equal(await p.getByRole("combobox", { name: "Habit icon" }).count(), 0);
  await p.getByRole("combobox", { name: "Colour", exact: true }).click();
  assert.equal(await p.locator("#habit-colour-options .colour-swatch").count(), 4);
  await p.getByRole("option", { name: "Lavender", exact: true }).click();
  assert.equal(await p.locator("#habit-colour .swatch-lavender").count(), 1);
  await p.getByRole("combobox", { name: "Repeats", exact: true }).click();
  await p.getByRole("option", { name: "Weekly", exact: true }).click();
  assert.equal(await p.locator("#habit-target-label").innerText(), "Times a week");
  await p.getByRole("combobox", { name: "Repeats", exact: true }).click();
  await p.getByRole("option", { name: "Daily", exact: true }).click();
  if (process.env.ORBIT_SCREENSHOT)
    await p.screenshot({ path: process.env.ORBIT_SCREENSHOT.replace(".png", "-habit-editor.png") });

  await p.locator("#habit-form").getByRole("button", { name: "Save", exact: true }).click();
  await p.waitForFunction(() => {
    // eslint-disable-next-line no-undef
    return rows("habits")[0].icon === "drop" && !document.querySelector("#habit-editor").open;
  });
  if (process.env.ORBIT_SCREENSHOT)
    await p.screenshot({ path: process.env.ORBIT_SCREENSHOT.replace(".png", "-habits.png") });
  // A refresh queued by blur must not replace a field focused while the read is in flight.
  await p.locator('[data-page="lists"]').click();
  await p.locator("#note-body").fill("Initial body");
  await p.waitForTimeout(750);
  await p.evaluate(() => {
    window.holdRead = true;
    // This variable belongs to the renderer’s classic-script scope.
    // eslint-disable-next-line no-undef
    pendingRender = true;
    document.activeElement.blur();
  });
  await p.waitForFunction(() => window.readWaiting);
  await p.locator("#note-body").focus();
  await p.keyboard.type(" continued");
  await p.evaluate(() => {
    window.holdRead = false;
    window.releaseRead();
  });
  await p.waitForTimeout(150);
  assert.equal(await p.locator("#note-body").evaluate((field) => field.value), "Initial body continued");
  assert.equal(await p.evaluate(() => document.activeElement.id), "note-body");
  await p.keyboard.type(" safely");
  if (process.env.ORBIT_SCREENSHOT)
    await p.screenshot({ path: process.env.ORBIT_SCREENSHOT.replace(".png", "-note.png") });
  assert.equal(await p.locator("#note-body").evaluate((field) => field.value), "Initial body continued safely");
  await p.keyboard.press("Control+6");
  await p.locator("#compact-rows").check();
  await p.locator('[data-appearance="light"]').click();
  assert.equal(await p.locator("html").getAttribute("data-appearance"), "light");
  // Incoming data must not remove a Settings control between pointer-down and pointer-up.
  await p.evaluate(async () => {
    window.holdRead = true;
    window.raceControl = document.querySelector("#compact-rows");
    await window.orbit.batch([
      { key: "tasks/refresh-race", payload: { id: "refresh-race", title: "Background update", localDate: null } },
    ]);
  });
  await p.waitForFunction(() => window.readWaiting);
  const control = await p.locator("#compact-rows").boundingBox();
  const beforeClick = await p.locator("#compact-rows").isChecked();
  await p.mouse.move(control.x + control.width / 2, control.y + control.height / 2);
  await p.mouse.down();
  await p.evaluate(() => {
    window.holdRead = false;
    window.releaseRead();
  });
  await p.waitForTimeout(100);
  assert.equal(await p.evaluate(() => window.raceControl === document.querySelector("#compact-rows")), true);
  await p.mouse.up();
  assert.equal(await p.locator("#compact-rows").isChecked(), !beforeClick);
  await p.keyboard.press("Control+3");
  assert.equal(await p.locator("h1").innerText(), "Tasks");
  await p.locator("[data-new-list]").first().click();
  assert.equal(await p.evaluate(() => document.activeElement.name), "name");
  await p.mouse.click(230, 50);
  assert.equal(await p.locator("dialog[open]").count(), 0);
  await p.keyboard.press("Control+2");
  await p.keyboard.press("Control+Shift+V");
  assert.equal(await p.locator(".day-tile").count(), 7);
  await p.keyboard.press("Control+Shift+V");
  assert.ok([28, 35, 42].includes(await p.locator(".day-tile").count()));
  assert.ok((await p.locator(".cal-cell:not(.outside)").count()) >= 28);
  const arrow = await p.getByRole("button", { name: "Next month" }).boundingBox();
  await p.getByRole("button", { name: "Next month" }).click();
  const nextArrow = await p.getByRole("button", { name: "Next month" }).boundingBox();
  assert.equal(nextArrow.x, arrow.x);
  assert.equal(nextArrow.y, arrow.y);
  await p.locator('[data-page="today"]').click();
  await p.locator("#inline-task-input").fill("Unfinished draft");
  await p.evaluate(() => window.emitUpdate({ status: "downloaded", version: "0.3.5", percent: 100 }));
  assert.equal(await p.locator("#home-update").isVisible(), true);
  assert.match(await p.locator("#restart-update").innerText(), /Click to restart/);
  await p.locator("#home-update").click();
  assert.equal(await p.evaluate(() => window.updateInstalls), 0, "Restart discarded an unfinished task draft");
  await p.keyboard.press("Control+6");
  await p.getByRole("button", { name: "Restart to update", exact: true }).click();
  assert.equal(await p.evaluate(() => window.updateInstalls), 0, "Settings restart discarded a draft on another page");
  await p.keyboard.press("Control+1");
  await p.locator("#inline-task-input").fill("");
  await p.locator('[data-page="lists"]').click();
  await p.locator("#note-body").fill("Last edit before restart");
  await p.evaluate(() => window.emitUpdate({ status: "downloading", version: "0.3.5", percent: 80 }));
  assert.equal(await p.evaluate(() => document.activeElement.id), "note-body", "Update events stole typing focus");
  await p.evaluate(() => {
    window.failWrite = true;
    window.emitUpdate({ status: "downloaded", version: "0.3.5", percent: 100 });
  });
  await p.locator("#restart-update").click();
  await p.locator("#notice").getByText("Test disk unavailable").waitFor();
  assert.equal(await p.evaluate(() => window.updateInstalls), 0, "Restart proceeded after note saving failed");
  await p.evaluate(() => (window.failWrite = false));
  await p.locator("#restart-update").click();
  await p.waitForFunction(() => window.updateInstalls === 1);
  assert.equal(
    await p.evaluate(async () =>
      (await window.orbit.read()).records.some((r) => r.payload.notes === "Last edit before restart"),
    ),
    true,
    "Restart ran before the latest note edit was saved",
  );
  const previousChecks = await p.evaluate(() => window.updateChecks);
  await p.keyboard.press("Control+6");
  assert.ok((await p.evaluate(() => window.updateChecks)) > previousChecks, "Entering Settings checks for updates");
  await p.evaluate(() => window.emitUpdate({ status: "error" }));
  await p.getByRole("button", { name: "Try again", exact: true }).click();
  assert.equal(await p.locator("#update-status").innerText(), "You’re up to date.");
  // Photo attachment saves without replacing the title/body or stealing typing focus.
  await p.locator('[data-page="lists"]').click();
  await p.locator("#note-photo-file").setInputFiles(path.resolve(__dirname, "../assets/orbit.png"));
  await p.waitForFunction(async () => (await window.orbit.read()).records.some((r) => r.payload.photos?.length === 1));
  assert.equal(await p.locator("#note-body").evaluate((field) => field.value), "Last edit before restart");
  await p.locator("#note-body").focus();
  const syncBefore = await p.locator("#sync-text").innerText();
  await p.evaluate(() => {
    window.emitSync({ status: "Syncing…", syncing: true });
    window.emitSync({ status: "All changes synced", syncing: false });
    window.emitSync({ status: "Syncing…", syncing: true });
    window.emitSync({ status: "All changes synced", syncing: false });
  });
  await p.waitForTimeout(1300);
  assert.equal(await p.locator("#sync-text").innerText(), syncBefore);
  assert.equal(await p.evaluate(() => document.activeElement.id), "note-body");
  await p.locator('[data-page="today"]').click();
  assert.equal(await p.locator("#sync-text").innerText(), "Synced");
  if (await p.locator("#notice").isVisible()) await p.getByRole("button", { name: "Dismiss message" }).click();
  for (const title of ["First selection", "Second selection"]) {
    await p.locator("#inline-task-input").fill(title);
    await p.locator("#inline-task-input").press("Enter");
    await p.getByRole("button", { name: `Edit ${title}`, exact: true }).waitFor();
  }
  await p.getByRole("button", { name: "Edit First selection", exact: true }).click({ modifiers: ["Control"] });
  await p.getByRole("button", { name: "Edit Second selection", exact: true }).click({ modifiers: ["Control"] });
  await p.locator("#copy-selected").click();
  const copied = await p.evaluate(() => window.copiedTexts.at(-1));
  assert.ok(copied.includes("First selection") && copied.includes("Second selection"));
  assert.equal(await p.locator("#notice").isVisible(), false, "Copying should stay silent");
  await p.locator("#clear-selection").click();
  await p.getByRole("button", { name: "Edit First selection", exact: true }).click({ button: "right" });
  const copyItem = p.locator("#row-menu").getByRole("menuitem", { name: "Copy text", exact: true });
  await copyItem.hover();
  await p.waitForFunction(
    () => getComputedStyle(document.querySelector("#row-menu button")).color === "rgb(255, 255, 255)",
  );
  await copyItem.click();
  assert.equal(await p.locator("#notice").isVisible(), false);
  await p.getByRole("checkbox", { name: "Complete First selection", exact: true }).click();
  await p.locator('[data-page="calendar"]').click();
  await p.locator('[data-month="0"]').click();
  assert.equal(await p.locator("#calendar-completed").getAttribute("open"), null);
  const dock = await p.locator(".calendar-page > .capture-dock").boundingBox();
  const panel = await p.locator(".cal-day").boundingBox();
  assert.ok(dock.x + dock.width < panel.x, "Calendar capture overlaps the day panel");
  // Calendar uses the same overlay controls, without moving text in its day panel.
  const calendarRow = p.locator(".cal-day .task-row").filter({ hasText: "Second selection" });
  await p.mouse.move(0, 0);
  await p.waitForTimeout(160);
  const calendarTitle = await calendarRow.locator(".row-title").boundingBox();
  await calendarRow.hover();
  await p.waitForTimeout(160);
  const hoveredTitle = await calendarRow.locator(".row-title").boundingBox();
  for (const dimension of ["x", "y", "width", "height"])
    assert.ok(Math.abs(hoveredTitle[dimension] - calendarTitle[dimension]) < 1);
  await calendarRow.getByRole("button", { name: "Edit task: Second selection", exact: true }).click();
  assert.equal(await p.locator('#task-form input[name="title"]').inputValue(), "Second selection");
  await p.locator("#editor").getByRole("button", { name: "Close", exact: true }).click();
  if (process.env.ORBIT_SCREENSHOT) await p.screenshot({ path: process.env.ORBIT_SCREENSHOT });
  await p.locator('[data-page="today"]').click();
  assert.equal(await p.locator(".progress-day").count(), 7);
  assert.equal(await p.getByRole("combobox", { name: "Progress range" }).count(), 0);
  await p.locator('[data-page="habits"]').click();
  for (const title of ["Gym", "Read", "A longer habit title which needs the whole row"]) {
    await p.locator("#inline-task-input").fill(title);
    await p.locator("#inline-task-input").press("Enter");
    await p.getByRole("checkbox", { name: `Log ${title}`, exact: true }).waitFor();
  }
  const habitRects = await p.locator(".habit-row").evaluateAll((rows) =>
    rows.map((row) => ({
      x: row.getBoundingClientRect().x,
      y: row.getBoundingClientRect().y,
      width: row.getBoundingClientRect().width,
    })),
  );
  assert.equal(habitRects[0].y, habitRects[1].y, "Short habits should share two columns");
  assert.ok(habitRects.at(-1).width > habitRects[0].width * 1.8, "A long habit gets a full row");
  if (process.env.ORBIT_SCREENSHOT) {
    await p.locator('[data-page="today"]').click();
    await p.waitForTimeout(220);
    await p.screenshot({ path: process.env.ORBIT_SCREENSHOT.replace(".png", "-today.png") });
  }

  await p.locator('[data-page="calendar"]').click();
  await p.locator('[data-month="0"]').click();
  await p.getByRole("tab", { name: "Week", exact: true }).click();
  assert.equal(await p.locator(".time-slot").count(), 7 * 96);
  const slot = p.locator('[data-time-slot$="T09:30"]').first();
  const slotDate = (await slot.getAttribute("data-time-slot")).split("T")[0];
  await slot.click();
  assert.equal(await p.locator('#task-form input[name="time"]').inputValue(), "09:30");
  assert.equal(await p.locator('#task-form input[name="date"]').inputValue(), slotDate);
  await p.locator('#task-form input[name="title"]').fill("Timeline sample");
  await p.locator("#task-form").getByRole("button", { name: "Save", exact: true }).click();
  await p.locator(".schedule-event", { hasText: "Timeline sample" }).waitFor();
  if (process.env.ORBIT_SCREENSHOT)
    await p.screenshot({ path: process.env.ORBIT_SCREENSHOT.replace(".png", "-week.png") });
  await p.getByRole("tab", { name: "Day", exact: true }).click();
  assert.equal(await p.locator(".time-slot").count(), 96);
  assert.equal(await p.locator(".schedule-event").count(), 1);
  await p.locator('[data-time-slot$="T15:00"]').click();
  assert.equal(await p.locator('#task-form input[name="time"]').inputValue(), "15:00");
  await p.locator("#editor").getByRole("button", { name: "Close", exact: true }).click();
  await p.keyboard.press("Control+6");
  await p.getByRole("combobox", { name: "Quick add shortcut" }).click();
  await p.getByRole("option", { name: "Off", exact: true }).click();
  await p.waitForFunction(async () => (await window.orbit.desktopSettings()).shortcut === "");
  await p.locator('[data-page="lists"]').click();
  const noteBody = await p.locator("#note-body").evaluate((field) => field.value);
  await p.evaluate(() => (window.noteFieldBeforeResize = document.querySelector("#note-body")));
  for (const [selector, amount] of [
    ["#main-pane-grip", 42],
    ["#notes-pane-grip", 48],
  ]) {
    const grip = await p.locator(selector).boundingBox();
    await p.mouse.move(grip.x + grip.width / 2, grip.y + 80);
    await p.mouse.down();
    await p.mouse.move(grip.x + grip.width / 2 + amount, grip.y + 80);
    await p.mouse.up();
  }
  assert.equal(await p.locator("#main-pane-grip").getAttribute("aria-valuenow"), "258");
  assert.equal(await p.locator("#notes-pane-grip").getAttribute("aria-valuenow"), "296");
  assert.equal(await p.evaluate(() => window.noteFieldBeforeResize === document.querySelector("#note-body")), true);
  await p.getByRole("button", { name: "Hide note list", exact: true }).click();
  assert.equal(await p.locator(".notes-nav").isVisible(), false);
  await p.getByRole("button", { name: "Show note list", exact: true }).click();
  assert.equal(await p.locator("#note-body").evaluate((field) => field.value), noteBody);
  await p.getByRole("button", { name: "Hide main sidebar", exact: true }).click();
  assert.equal(await p.locator(".sidebar").isVisible(), false);
  await p.getByRole("button", { name: "Show main sidebar", exact: true }).click();
  await p.reload();
  await p.locator("h1").filter({ hasText: "Today" }).waitFor();
  assert.equal(await p.locator("#main-pane-grip").getAttribute("aria-valuenow"), "258");
  assert.equal(await p.evaluate(() => localStorage.getItem("notesSidebarWidth")), "296");
  // Notes keep photo anchors at the insertion point and preserve text through delete/undo.
  await p.keyboard.press("Control+4");
  await p.locator("#note-title").fill("Beta editor checks");
  await p.locator("#note-body").fill("Before after");
  await p.locator("#note-body").evaluate((field) => {
    field.focus();
    field.setSelectionRange(6, 6);
    field.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
  });
  await p.locator("#note-photo-file").setInputFiles(path.resolve(__dirname, "../assets/orbit.png"));
  await p.locator("[data-photo-id]").waitFor();
  assert.equal(await p.locator("#note-body").evaluate((field) => field.value), "Before after");
  await p.waitForFunction(async () =>
    (await window.orbit.read()).records.some(
      (r) => r.payload.title === "Beta editor checks" && r.payload.photos?.[0]?.position === "6",
    ),
  );
  await p.locator("[data-photo-id] img").click();
  assert.equal(await p.locator("figure.photo-selected").count(), 1);
  await p.getByRole("button", { name: "Wrap text to the right", exact: true }).click();
  assert.equal(await p.locator("[data-photo-id]").getAttribute("data-wrap"), "left");
  await p.keyboard.press("Backspace");
  assert.equal(await p.locator("[data-photo-id]").count(), 0);
  assert.equal(await p.locator("#note-body").evaluate((field) => field.value), "Before after");
  await p.keyboard.press("Control+z");
  assert.equal(await p.locator("[data-photo-id]").count(), 1);
  await p.keyboard.press("Control+1");
  await p.keyboard.press("Control+4");
  assert.equal(await p.locator("[data-photo-id]").getAttribute("data-wrap"), "left");
  await p.locator("#note-body").evaluate((field) => {
    field.focus();
    field.setSelectionRange(0, field.value.length);
  });
  await p.keyboard.press("Tab");
  assert.equal(await p.locator("[data-photo-id]").count(), 1, "Indent removed an inline photo");
  await p.keyboard.press("Shift+Tab");
  assert.equal(await p.locator("#note-body").evaluate((field) => field.value), "Before after");
  assert.equal(await p.locator("[data-photo-id]").count(), 1);
  const editedLabel = await p.locator("#note-edited").innerText();
  await p.locator("#note-body").fill("A line");
  await p.keyboard.press("Enter");
  assert.equal(await p.locator("#note-body").evaluate((field) => field.value), "A line\n");
  await p.keyboard.press("Enter");
  await p.keyboard.type("Another line");
  assert.equal(await p.locator("#note-body").evaluate((field) => field.value), "A line\n\nAnother line");
  await p.locator("#note-body").fill("");
  await p.keyboard.type("- one");
  await p.keyboard.press("Enter");
  await p.keyboard.type("two");
  assert.equal(await p.locator("#note-body").evaluate((field) => field.value), "• one\n• two");
  await p.keyboard.press("Tab");
  assert.equal(await p.locator("#note-body").evaluate((field) => field.value), "• one\n    ◦ two");
  await p.keyboard.press("Shift+Tab");
  assert.equal(await p.locator("#note-body").evaluate((field) => field.value), "• one\n• two");
  await p.waitForTimeout(750);
  assert.equal(await p.locator("#note-edited").innerText(), editedLabel);
  await p.keyboard.press("Control+1");
  // Layout edits are opt-in and persist, including accessible button moves.
  assert.equal(await p.locator(".today-panel[draggable=true]").count(), 0);
  assert.equal(await p.locator('[data-today-panel="heatmap"]').isVisible(), false);
  await p.getByRole("button", { name: "Edit layout", exact: true }).click();
  assert.equal(await p.locator('[data-today-panel="heatmap"]').isVisible(), false);
  await p.locator('[data-panel-visible="plan"]').uncheck();
  assert.equal(await p.locator('[data-today-panel="plan"]').isVisible(), false);
  await p.locator('[data-panel-visible="plan"]').check();
  await p.locator('[data-panel-visible="heatmap"]').check();
  const divider = p.getByRole("separator", { name: "Today column widths", exact: true });
  const initialMainWidth = await p.locator('[data-panel-drop="main"]').evaluate((column) => column.clientWidth);
  const dividerBox = await divider.boundingBox();
  await p.mouse.move(dividerBox.x + dividerBox.width / 2, dividerBox.y + 30);
  await p.mouse.down();
  await p.mouse.move(dividerBox.x - 60, dividerBox.y + 30, { steps: 8 });
  await p.mouse.up();
  const resizedMainWidth = await p.locator('[data-panel-drop="main"]').evaluate((column) => column.clientWidth);
  assert.ok(resizedMainWidth < initialMainWidth - 30, "Divider resizes both columns");
  assert.ok(Number(await p.evaluate(() => localStorage.getItem("todayColumnShare"))) >= 35);

  assert.equal(await p.locator("[data-panel-column-toggle]").count(), 0);
  const gripBox = await p.getByRole("button", { name: "Move Habits", exact: true }).boundingBox();
  const taskPanelBox = await p.locator('[data-today-panel="tasks"]').boundingBox();
  await p.mouse.move(gripBox.x + 12, gripBox.y + gripBox.height / 2);
  await p.mouse.down();
  await p.mouse.move(taskPanelBox.x + 50, taskPanelBox.y + 2, { steps: 12 });
  assert.equal(await p.locator(".layout-placeholder").count(), 1);
  const ghostWidth = await p.locator(".layout-ghost").evaluate((ghost) => ghost.clientWidth);
  assert.ok(Math.abs(ghostWidth - resizedMainWidth + 20) < 45, "Dragging across columns adapts the preview width");
  await p.mouse.up();
  assert.equal(
    await p.locator('[data-panel-drop="main"]').evaluate((column) => column.firstElementChild.dataset.todayPanel),
    "habits",
  );
  assert.equal(
    await p.locator('[data-today-panel="habits"]').evaluate((panel) => panel.parentElement.dataset.panelDrop),
    "main",
  );
  await p.getByRole("button", { name: "Finish editing layout", exact: true }).click();
  assert.equal(await p.locator(".today-panel[draggable=true]").count(), 0);
  assert.equal(await p.locator('[data-today-panel="heatmap"]').isVisible(), true);
  assert.ok(
    Math.abs(
      (await p.locator('[data-panel-drop="main"]').evaluate((column) => column.clientWidth)) - resizedMainWidth,
    ) <= 4,
    "Column width persists when edit borders are removed",
  );
  const contentRadii = await p
    .locator(".today-panel:not([hidden]) .card, .today-board .task-row, .compact-habits .habit-row")
    .evaluateAll((boxes) => boxes.map((box) => getComputedStyle(box).borderTopLeftRadius));
  assert.ok(contentRadii.length > 3 && contentRadii.every((radius) => radius === "12px"));
  assert.equal(
    await p
      .locator(".overall-day")
      .allTextContents()
      .then((values) => values.join("")),
    "",
  );
  const progressHeading = await p.locator(".overall-progress h2").boundingBox();
  const progressRange = await p.locator(".overall-progress .recent-progress-head > span").boundingBox();
  assert.ok(progressRange.x > progressHeading.x + progressHeading.width);
  assert.ok(Math.abs(progressRange.y - progressHeading.y) < 5);
  assert.equal(await p.locator("[data-progress-day] svg path").count(), 0);
  const filledDay = p.locator(".overall-day").last();
  const previousColour = await filledDay.evaluate((day) => {
    day.style.setProperty("--o", "1");
    return getComputedStyle(day).backgroundColor;
  });
  await p.evaluate(() => (document.documentElement.dataset.accent = "lavender"));
  assert.notEqual(
    await filledDay.evaluate((day) => getComputedStyle(day).backgroundColor),
    previousColour,
    "Overall progress follows the chosen accent",
  );
  await p.evaluate(() => (document.documentElement.dataset.accent = localStorage.getItem("accent") || "coral"));

  // A real drop reschedules a task to a quarter-hour and retains reminder offsets.
  await p.locator("#inline-task-input").fill("Drag calendar task");
  await p.locator("#inline-task-input").press("Enter");
  await p.getByRole("button", { name: "Edit Drag calendar task", exact: true }).waitFor();
  await p.keyboard.press("Control+2");
  await p.getByRole("tab", { name: "Week", exact: true }).click();
  const dragSource = p.locator(".schedule-anytime", { hasText: "Drag calendar task" });
  assert.equal(await p.locator("#toggle-anytime").count(), 0);
  assert.ok((await dragSource.boundingBox()).height <= 25, "Anytime rows stay one compact line");
  const anytimeDivider = p.getByRole("separator", { name: "Anytime section height", exact: true });
  await anytimeDivider.focus();
  await p.keyboard.press("Home");
  assert.equal(await anytimeDivider.getAttribute("aria-valuenow"), "0");
  await p.keyboard.press("ArrowDown");
  await p.keyboard.press("ArrowDown");

  const targetSlot = p.locator('[data-time-slot$="T10:15"]').first();
  const expectedDay = (await targetSlot.getAttribute("data-time-slot")).slice(0, 10);
  await targetSlot.scrollIntoViewIfNeeded();
  // Dispatch the same DataTransfer events as a native desktop drag; Chromium headless
  // cannot synthesize dragging from the scrolled all-day row into a virtual time grid.
  await dragSource.evaluate((source, key) => {
    const transfer = new DataTransfer();
    source.dispatchEvent(new DragEvent("dragstart", { dataTransfer: transfer, bubbles: true }));
    document
      .querySelector(`[data-time-slot="${key}T10:15"]`)
      .dispatchEvent(new DragEvent("drop", { dataTransfer: transfer, bubbles: true, cancelable: true }));
  }, expectedDay);
  await p.waitForFunction(async () =>
    (await window.orbit.read()).records.some(
      (r) =>
        r.payload.title === "Drag calendar task" &&
        r.payload.hasTime &&
        new Date(r.payload.dueDate).getMinutes() === 15,
    ),
  );
  await p.getByRole("button", { name: "Change duration of Drag calendar task", exact: true }).focus();
  await p.keyboard.press("ArrowDown");
  await p.waitForFunction(async () =>
    (await window.orbit.read()).records.some(
      (r) => r.payload.title === "Drag calendar task" && r.payload.durationMinutes === 45,
    ),
  );
  assert.match(await p.locator(".time-axis").innerText(), /AM/);
  if (process.env.ORBIT_SCREENSHOT)
    await p.screenshot({ path: process.env.ORBIT_SCREENSHOT.replace(".png", "-calendar.png") });
  await p.keyboard.press("Control+6");
  await p.getByRole("combobox", { name: "Calendar clock format", exact: true }).click();
  await p.getByRole("option", { name: "24 hour", exact: true }).click();
  await p.locator("#progress-tasks").uncheck();
  await p.keyboard.press("Control+2");
  assert.doesNotMatch(await p.locator(".time-axis").innerText(), /AM|PM/);
  assert.equal(await p.evaluate(() => localStorage.getItem("progressIncludesTasks")), "false");
  await p.keyboard.press("Control+1");
  const row = p.locator(".task-row", { hasText: "Drag calendar task" });
  await row.click({ button: "right" });
  await p.locator("#row-menu").getByRole("menuitem", { name: "Select item", exact: true }).click();
  await p.locator("h1").click();
  assert.equal(await p.locator("#selection-bar").isVisible(), false);
  await row.click({ button: "right" });
  assert.equal(await p.locator("#row-menu .danger").innerText(), "Delete");
  await p.locator("#row-menu .danger").click();
  await p.waitForFunction(async () =>
    (await window.orbit.read()).records.some((r) => r.payload.title === "Drag calendar task" && r.deleted),
  );
  // Past corrections keep their own completion date, fill the ring, and reset on navigation.
  const pastKey = await p.locator("[data-progress-day]").nth(2).getAttribute("data-progress-day");
  const taskID = "a1111111-1111-4111-8111-111111111111",
    habitID = "b1111111-1111-4111-8111-111111111111";
  await p.evaluate(
    async ({ pastKey, taskID, habitID }) => {
      await window.orbit.batch([
        {
          key: "tasks/" + taskID,
          payload: { id: taskID, title: "Past task", localDate: pastKey, hasTime: false, updatedAt: Date.now() },
        },
        {
          key: "habits/" + habitID,
          payload: {
            id: habitID,
            title: "Past habit",
            target: 1,
            frequencyRule: "DAILY",
            color: "sage",
            createdAt: new Date(pastKey + "T00:00:00").getTime(),
            updatedAt: Date.now(),
          },
        },
      ]);
    },
    { pastKey, taskID, habitID },
  );
  await p.locator(`[data-progress-day="${pastKey}"]`).click();
  assert.equal(await p.getByRole("button", { name: "Back to Today", exact: true }).isVisible(), true);
  await p.getByRole("checkbox", { name: "Complete Past task", exact: true }).click();
  assert.equal(await p.getByRole("checkbox", { name: "Log Past habit", exact: true }).isDisabled(), true);
  assert.equal(await p.locator(`[data-progress-day="${pastKey}"]`).getAttribute("aria-pressed"), "true");
  assert.equal(await p.locator("[data-progress-day] svg path").count(), 0);
  await p.locator('[data-page="habits"]').click();
  assert.equal(
    await p.getByRole("checkbox", { name: "Log Past habit", exact: true }).isEnabled(),
    true,
    "Habits always checks in for today",
  );
  await p.locator("#habit-history").click();
  const historicalToggle = p.locator(`[data-history-toggle="${habitID}"][data-day="${pastKey}"]`);
  await historicalToggle.click();
  await p.waitForFunction(
    async (id) =>
      (await window.orbit.read()).records.some((record) => record.payload.habitID === id && record.payload.count === 1),
    habitID,
  );
  const historyGrid = await p.locator(".habit-history .box-grid").first().boundingBox();
  assert.ok(historyGrid.width > historyGrid.height, "History uses compact horizontal weeks");
  if (process.env.ORBIT_SCREENSHOT)
    await p.screenshot({ path: process.env.ORBIT_SCREENSHOT.replace(".png", "-history.png") });
  await p.locator(`[data-history="${habitID}"]`).click();
  assert.equal(await p.getByRole("button", { name: "Back to History", exact: true }).isVisible(), true);
  if (process.env.ORBIT_SCREENSHOT)
    await p.screenshot({ path: process.env.ORBIT_SCREENSHOT.replace(".png", "-history-detail.png") });
  await p.getByRole("button", { name: "Back to History", exact: true }).click();
  await p.getByRole("button", { name: "Back to Habits", exact: true }).click();
  await p.locator('[data-page="today"]').click();
  await p.locator(`[data-progress-day="${pastKey}"]`).click();
  // Restore tasks in progress for this assertion, which was switched off earlier in Settings.
  await p.evaluate(() => localStorage.setItem("progressIncludesTasks", "true"));
  await p.locator(`[data-progress-day="${pastKey}"]`).click();
  assert.equal(
    await p.locator(`[data-progress-day="${pastKey}"] .progress-value`).getAttribute("stroke-dasharray"),
    "none",
  );
  assert.equal(
    await p.evaluate(
      async (id) =>
        new Date(
          (await window.orbit.read()).records.find((record) => record.payload.id === id).payload.completedAt,
        ).getDate(),
      taskID,
    ),
    Number(pastKey.slice(-2)),
  );
  await p.keyboard.press("Control+4");
  await p.keyboard.press("Control+1");
  assert.equal(await p.locator(".past-edit-banner").count(), 0);
  // Bulk moves replace repeated per-row overdue handling.
  await p.evaluate(async (id) => {
    const record = (await window.orbit.read()).records.find((record) => record.payload.id === id);
    await window.orbit.put(record.key, { ...record.payload, completedAt: null, updatedAt: Date.now() });
  }, taskID);
  await p.waitForFunction(() => !!document.querySelector('[data-overdue-all="someday"]'));
  await p.getByRole("button", { name: "All to Someday", exact: true }).click();
  await p.waitForFunction(
    async (id) =>
      (await window.orbit.read()).records.find((record) => record.payload.id === id).payload.listID ===
      "00000000-0000-4000-8000-000000000001",
    taskID,
  );
  await p.keyboard.press("Control+2");
  await p.getByRole("separator", { name: "Anytime section height", exact: true }).focus();
  await p.keyboard.press("Home");
  assert.equal(await p.locator(".schedule-all-day").evaluate((element) => element.getBoundingClientRect().height), 0);
  await p.keyboard.press("End");
  assert.equal(await p.locator(".schedule-all-day").evaluate((element) => element.getBoundingClientRect().height), 240);
  // New note groups stay out of task categories; nonempty deletion offers explicit outcomes.
  await p.keyboard.press("Control+4");
  await p.getByRole("button", { name: "New section", exact: true }).click();
  await p.locator('#list-form input[name="name"]').fill("Notes only");
  await p.locator("#list-form").getByRole("button", { name: "Save", exact: true }).click();
  const sectionID = await p.evaluate(
    async () => (await window.orbit.read()).records.find((record) => record.payload.name === "Notes only").payload.id,
  );
  assert.equal(await p.locator(`[data-list="${sectionID}"]`).count(), 0);
  await p.getByRole("button", { name: "New note in Notes only", exact: true }).click();
  await p.locator("#note-title").fill("Retain this page");
  await p.locator("#note-body").fill("Keep this content");
  await p.keyboard.press("Escape");
  await p.locator(`.notes-nav [data-section-menu="${sectionID}"]`).click({ button: "right" });
  await p.getByRole("menuitem", { name: "Delete section", exact: true }).click();
  await p.getByRole("button", { name: "Move notes to All", exact: true }).click();
  await p.waitForFunction(async () =>
    (await window.orbit.read()).records.some(
      (record) => !record.deleted && record.payload.title === "Retain this page" && record.payload.listID == null,
    ),
  );
  assert.equal(await p.getByRole("button", { name: "Collapse All notes", exact: true }).count(), 1);
  await p.getByRole("button", { name: "Collapse All notes", exact: true }).click();
  assert.equal(await p.getByRole("button", { name: "Expand All notes", exact: true }).count(), 1);
  // Expanding collapsed groups for search must keep sequential typing in the right order.
  await p.locator("#note-filter").pressSequentially("Retain");
  assert.equal(await p.locator("#note-filter").inputValue(), "Retain");
  assert.equal(await p.locator(".notes-nav-page", { hasText: "Retain this page" }).isVisible(), true);
  await p.locator("#note-filter").fill("");
  await p.locator("#note-filter").blur();
  // Deleting a section and its contents leaves a similarly named task category intact.
  await p.evaluate(async () => {
    await window.orbit.batch([
      {
        key: "lists/delete-notes",
        payload: { id: "delete-notes", name: "Remove these", kind: "notes", sortOrder: 2, updatedAt: Date.now() },
      },
      {
        key: "lists/keep-category",
        payload: { id: "keep-category", name: "Remove these", kind: "tasks", sortOrder: 2, updatedAt: Date.now() },
      },
      {
        key: "tasks/remove-page",
        payload: {
          id: "remove-page",
          title: "Delete this page",
          isNote: true,
          notes: "Old content",
          listID: "delete-notes",
          updatedAt: Date.now(),
        },
      },
    ]);
  });
  await p.locator('.notes-nav [data-section-menu="delete-notes"]').waitFor();
  await p.locator('.notes-nav [data-section-menu="delete-notes"]').click({ button: "right" });
  await p.getByRole("menuitem", { name: "Delete section", exact: true }).click();
  await p.getByRole("button", { name: "Delete section and notes", exact: true }).click();
  await p.waitForFunction(async () =>
    (await window.orbit.read()).records.some((record) => record.key === "tasks/remove-page" && record.deleted),
  );
  assert.equal(
    await p.evaluate(
      async () =>
        (await window.orbit.read()).records.find((record) => record.key === "lists/keep-category").deleted || false,
    ),
    false,
  );
  assert.deepEqual(errors, []);
  console.log(
    "PASS: account keyboard/back, note sizing/scrolling, row actions/icons, settings races and planner flows",
  );
  await browser.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
