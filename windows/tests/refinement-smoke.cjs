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
        window.emitSync = cb;
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
        if (command === "check") window.emitUpdate({ status: "current" });
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
  await p.locator('[data-page="settings"]').click();
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
  await p.waitForFunction(() => getComputedStyle(document.querySelector(".habit-row .row-actions")).width === "0px");
  const countBounds = await habitRow.locator(".row-detail").boundingBox();
  const rowBounds = await habitRow.boundingBox();
  assert.ok(rowBounds.x + rowBounds.width - countBounds.x - countBounds.width <= 16, "Count hugs the right edge");
  await habitRow.hover();
  await p.waitForFunction(() => getComputedStyle(document.querySelector(".habit-row .row-actions")).width === "70px");
  if (process.env.ORBIT_SCREENSHOT)
    await p.screenshot({ path: process.env.ORBIT_SCREENSHOT.replace(".png", "-hover.png") });
  await habitRow.getByRole("button", { name: "Edit habit: Drink water", exact: true }).click();
  assert.equal(await p.locator('#habit-form input[name="icon"]').inputValue(), "drop");
  assert.equal(await p.getByRole("combobox", { name: "Habit icon" }).count(), 0);
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
  assert.equal(await p.locator("#note-body").inputValue(), "Initial body continued");
  assert.equal(await p.evaluate(() => document.activeElement.id), "note-body");
  await p.keyboard.type(" safely");
  if (process.env.ORBIT_SCREENSHOT)
    await p.screenshot({ path: process.env.ORBIT_SCREENSHOT.replace(".png", "-note.png") });
  assert.equal(await p.locator("#note-body").inputValue(), "Initial body continued safely");
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
  assert.equal(await p.locator(".day-tile").count(), 42);
  const arrow = await p.getByRole("button", { name: "Next month" }).boundingBox();
  await p.getByRole("button", { name: "Next month" }).click();
  const nextArrow = await p.getByRole("button", { name: "Next month" }).boundingBox();
  assert.equal(nextArrow.x, arrow.x);
  assert.equal(nextArrow.y, arrow.y);
  await p.locator('[data-page="today"]').click();
  await p.locator("#inline-task-input").fill("Unfinished draft");
  await p.evaluate(() => window.emitUpdate({ status: "downloaded", version: "0.3.5", percent: 100 }));
  await p.locator("#restart-update").click();
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
  await p.keyboard.press("Control+6");
  await p.evaluate(() => window.emitUpdate({ status: "error" }));
  await p.getByRole("button", { name: "Try again", exact: true }).click();
  assert.equal(await p.locator("#update-status").innerText(), "You’re up to date.");
  // Photo attachment saves without replacing the title/body or stealing typing focus.
  await p.locator('[data-page="lists"]').click();
  await p.locator("#note-photo-file").setInputFiles(path.resolve(__dirname, "../assets/orbit.png"));
  await p.waitForFunction(async () => (await window.orbit.read()).records.some((r) => r.payload.photos?.length === 1));
  assert.equal(await p.locator("#note-body").inputValue(), "Last edit before restart");
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
  if (process.env.ORBIT_SCREENSHOT) await p.screenshot({ path: process.env.ORBIT_SCREENSHOT });
  assert.deepEqual(errors, []);
  console.log(
    "PASS: account keyboard/back, note sizing/scrolling, row actions/icons, settings races and planner flows",
  );
  await browser.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
