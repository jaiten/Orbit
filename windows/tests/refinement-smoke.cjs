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
      read: async () => structuredClone(data),
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
  await p.locator("#task-scope").selectOption("someday");
  await p.getByRole("button", { name: "Edit Visit Japan", exact: true }).waitFor();
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
  assert.deepEqual(errors, []);
  console.log("PASS: settings, keyboard dates, Someday retrieval, note typing and habit capture");
  await browser.close();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
