/* global load, rows, today, OrbitHabits */
// Audit fixes (November 2026): Ctrl+Shift+Enter tasks from long captures, Someday @tag rules in Calendar and
// Coming up, quick add abbreviations and event addresses.
const { chromium } = require("playwright");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROMIUM_PATH || (fs.existsSync("/usr/bin/chromium") ? "/usr/bin/chromium" : undefined),
    args: ["--no-sandbox"],
  });
  try {
    const p = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const errors = [];
    p.on("pageerror", (error) => errors.push(error.message));
    await p.addInitScript(() => {
      const data = { records: [], onboarded: true, configured: true, email: null, status: "Saved locally" };
      window.mapCalls = [];
      window.orbit = {
        read: async () => structuredClone(data),
        onChange() {},
        onSyncStatus() {},
        onWake() {},
        onQuickAdd() {},
        onUpdateStatus() {},
        reschedule() {},
        updates: async () => ({ status: "idle", currentVersion: "0.3.62" }),
        desktopSettings: async () => ({ notifications: true, shortcut: "", shortcuts: [""] }),
        openMap: async (location) => window.mapCalls.push(location),
        put: async (key, payload, deleted = false) => {
          const i = data.records.findIndex((r) => r.key === key);
          const record = { key, payload, deleted };
          if (i < 0) data.records.push(record);
          else data.records[i] = record;
        },
        batch: async (changes) => {
          for (const { key, payload } of changes) await window.orbit.put(key, payload);
        },
      };
    });
    await p.route("http://localhost/**", (route) => {
      const file = path.resolve(__dirname, "../ui", new URL(route.request().url()).pathname.slice(1) || "index.html");
      return route.fulfill({
        body: fs.readFileSync(file),
        contentType: file.endsWith(".js") ? "text/javascript" : file.endsWith(".css") ? "text/css" : "text/html",
      });
    });
    await p.goto("http://localhost/");
    const tasks = () => p.evaluate(() => rows("tasks"));

    // 1. Ctrl+Shift+Enter on a long capture adds one task for today, even with "on monday" and "every day" inside.
    await p.locator('[data-page="today"]').click();
    const long =
      "Email Sam about the budget numbers he sent on monday and ask whether we review every day or only weekly";
    const input = p.locator("#inline-task-input");
    await input.click();
    await input.fill(long);
    await p.waitForFunction(() => document.querySelector("#inline-add-form").classList.contains("note-form"));
    assert.match(await p.locator(".capture-note-hint").innerText(), /Ctrl\+Shift\+Enter for a task \(Today\)/);
    await input.press("Control+Shift+Enter");
    await p.waitForFunction(() => rows("tasks").length === 1);
    const [forced] = await tasks();
    assert.equal(forced.title, long);
    assert.equal(forced.localDate, await p.evaluate(() => today()));
    assert.ok(!forced.isNote);
    await p.locator(".today-main .task-row", { hasText: "Email Sam" }).first().waitFor();
    // Date words that close the text still schedule it, and the bar says where it went.
    await input.fill("Write the long quarterly report for the team with all the numbers tomorrow");
    await input.press("Control+Shift+Enter");
    await p.waitForFunction(() => rows("tasks").length === 2);
    const tomorrow = await p.evaluate(() => OrbitHabits.addDays(today(), 1));
    assert.equal((await tasks()).find((t) => t.title.startsWith("Write")).localDate, tomorrow);
    assert.equal(await p.locator("#inline-receipt").innerText(), "Added to Tomorrow");

    // 2. Abbreviations expand as you type a space, and can carry quick add words.
    await p.evaluate(async () => {
      await window.orbit.put("preferences/00000000-0000-4000-8000-000000000003", {
        id: "00000000-0000-4000-8000-000000000003",
        progressWords: [],
        shortcuts: [{ abbr: "gs", text: "grocery shopping #errands" }],
        updatedAt: Date.now(),
      });
      await load(true);
    });
    await input.click();
    await input.pressSequentially("gs ");
    assert.equal(await input.inputValue(), "grocery shopping #errands ");
    assert.match(await p.locator("#inline-preview").innerText(), /#errands/);
    await input.press("Control+z");
    assert.equal(await input.inputValue(), "gs ");
    await input.fill("");
    await p.locator('[data-page="settings"]').click();
    await p.locator("#capture-shortcuts").fill("mtg = meeting with the team\nbad line\nMTG = team meeting");
    await p.locator("#capture-shortcuts").dispatchEvent("change");
    await p.waitForFunction(() =>
      rows("preferences").some((r) => r.shortcuts?.length === 1 && r.shortcuts[0].text === "team meeting"),
    );

    // 3. A Someday @tag rule shows its task on Today, in Calendar and in Coming up on matching days, and
    // offers to hand over tasks that were tagged before the rule existed.
    await p.evaluate(async () => {
      const day = today();
      const later = OrbitHabits.addDays(day, 2);
      await window.orbit.put("tasks/s1", {
        id: "s1",
        title: "Water plants @home",
        listID: "00000000-0000-4000-8000-000000000001",
        localDate: null,
        sortOrder: 1,
        updatedAt: 1,
      });
      await window.orbit.put("tasks/s2", {
        id: "s2",
        title: "Tidy desk @home",
        localDate: day,
        sortOrder: 2,
        updatedAt: 1,
      });
      window.ruleDays = { day, later };
      await load(true);
    });
    await p.locator("#someday-rule-add").click();
    const rule = p.locator("#someday-rule-rows fieldset").first();
    await rule.locator('[name="tag"]').fill("@Home");
    await rule.locator('[name="trigger"]').selectOption("weeks");
    // Dates are chosen in the app's own date picker; set the field it keeps behind the button.
    await rule.locator('[name="start"]').evaluate((input, day) => {
      input.value = day;
      input.dispatchEvent(new Event("input", { bubbles: true }));
      input.dispatchEvent(new Event("change", { bubbles: true }));
    }, await p.evaluate(() => window.ruleDays.later));
    await rule.locator('[name="interval"]').fill("1");
    await p.locator("#someday-rule-save").click();
    await p.locator("#notice .notice-action").click();
    await p.waitForFunction(
      () => rows("tasks").find((t) => t.id === "s2").listID === "00000000-0000-4000-8000-000000000001",
    );
    await p.locator('[data-page="today"]').click();
    assert.equal(await p.locator(".today-main .task-row", { hasText: "Water plants" }).count(), 0);
    await p.locator(".upcoming-row", { hasText: "Water plants" }).first().waitFor();
    await p.locator('[data-page="calendar"]').click();
    await p.locator('[data-scope="month"]').click();
    const later = await p.evaluate(() => window.ruleDays.later);
    await p.locator(`[data-day="${later}"] .cal-item.ruled`, { hasText: "Water plants" }).waitFor();
    await p.locator(`[data-day="${later}"] .cal-item.ruled`, { hasText: "Tidy desk" }).waitFor();

    // 3b. "No matching event" works for an iPhone calendar on days inside the window it shares.
    await p.evaluate(async () => {
      const day = today();
      await window.orbit.put("calendars/w1", {
        id: "w1",
        title: "Work",
        shown: true,
        eventsFrom: OrbitHabits.addDays(day, -14),
        eventsThrough: OrbitHabits.addDays(day, 106),
      });
      await window.orbit.put("preferences/00000000-0000-4000-8000-000000000004", {
        id: "00000000-0000-4000-8000-000000000004",
        rules: [
          {
            id: "r2",
            tag: "remote",
            trigger: "noEvent",
            calendar: "Work",
            title: "Office day",
            start: "",
            end: "",
            interval: 1,
          },
        ],
        updatedAt: Date.now(),
      });
      await window.orbit.put("tasks/s3", {
        id: "s3",
        title: "Deep work @remote",
        listID: "00000000-0000-4000-8000-000000000001",
        localDate: null,
        sortOrder: 3,
        updatedAt: 1,
      });
      await load(true);
    });
    await p.locator('[data-page="today"]').click();
    await p.locator(".today-main .task-row", { hasText: "Deep work" }).first().waitFor();
    await p.evaluate(async () => {
      await window.orbit.put("events/o1", {
        id: "o1",
        calendarID: "w1",
        title: "Office day",
        allDay: true,
        startDay: today(),
      });
      await load(true);
    });
    await p.waitForFunction(() => !document.querySelector(".today-main")?.textContent.includes("Deep work"));
    await p.locator('[data-page="calendar"]').click();

    // 4. Event addresses show in the day list and Coming up, and open in maps.
    await p.evaluate(async (later) => {
      await window.orbit.put("calendars/c1", { id: "c1", title: "Personal", writable: true, color: "#3366cc" });
      const start = new Date(later + "T09:00:00").getTime();
      await window.orbit.put("events/e1", {
        id: "e1",
        calendarID: "c1",
        title: "Dentist",
        location: "12 King St\nSpringfield",
        allDay: false,
        start,
        end: start + 3600000,
      });
      await load(true);
    }, later);
    await p.locator(`[data-day="${later}"]`).click();
    assert.equal(await p.locator(".cal-day-events .event-place").innerText(), "12 King St, Springfield");
    await p.locator('[data-page="today"]').click();
    await p.locator(".upcoming-event .event-place", { hasText: "12 King St" }).waitFor();
    await p.locator(".upcoming-event").first().click();
    await p.locator("#event-open-map").click();
    assert.deepEqual(await p.evaluate(() => window.mapCalls), ["12 King St, Springfield"]);
    // Saving without touching the address keeps its original two lines.
    await p.locator("#save-event").click();
    await p.waitForFunction(() => !document.querySelector("#event-editor").open);
    const kept = await p.evaluate(
      async () => (await window.orbit.read()).records.find((r) => r.key === "events/e1").payload.request,
    );
    assert.equal(kept.location, "12 King St\nSpringfield");
    assert.deepEqual(errors, []);
    console.log("PASS: forced long tasks, abbreviations, Someday rules in Calendar/Coming up, event addresses");
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
