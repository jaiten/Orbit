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
    const data = { records: [], onboarded: true, email: null, status: "Saved locally" };
    let changed = () => {};
    let settings = { notifications: true, shortcut: "", shortcuts: ["", "Control+Space"] };
    const batch = async (changes) => {
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
      onSyncStatus() {},
      onWake() {},
      onQuickAdd() {},
      reschedule() {},
      desktopSettings: async (changes) => (settings = { ...settings, ...changes }),
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
  await p.keyboard.type("My new note");
  assert.equal(await p.locator("#note-title").inputValue(), "My new note");
  await p.waitForTimeout(800);
  await p.keyboard.type(" continues");
  assert.equal(await p.locator("#note-title").inputValue(), "My new note continues");
  await p.getByRole("button", { name: "Back to notes", exact: false }).click();
  await p.locator('[data-page="habits"]').click();
  await p.locator("#inline-task-input").fill("Drink water");
  await p.locator("#inline-task-input").press("Enter");
  await p.getByRole("checkbox", { name: "Log Drink water", exact: true }).waitFor();
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
  if (process.env.ORBIT_SCREENSHOT) await p.screenshot({ path: process.env.ORBIT_SCREENSHOT });
  assert.deepEqual(errors, []);
  console.log("PASS: settings, keyboard dates, Someday retrieval, note typing and habit capture");
  await browser.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
