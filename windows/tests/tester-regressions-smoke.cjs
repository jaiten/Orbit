/* global load, openEvent, actionBusy */
const { chromium } = require("playwright");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

(async () => {
  const browser = await chromium.launch();
  try {
    const p = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    const errors = [];
    p.on("pageerror", (error) => errors.push(error.message));
    await p.addInitScript(() => {
      const data = { records: [], onboarded: true, configured: true, email: null, status: "Saved locally" };
      window.authCalls = [];
      window.orbit = {
        read: async () => structuredClone(data),
        onChange() {},
        onSyncStatus() {},
        onWake() {},
        onQuickAdd() {},
        onUpdateStatus() {},
        reschedule() {},
        updates: async () => ({ status: "idle", currentVersion: "0.3.59" }),
        desktopSettings: async () => ({ notifications: true }),
        auth: async (...args) => {
          window.authCalls.push(args);
          return "Signed in";
        },
        put: async (key, payload) => {
          if (window.failWrite) throw Error("Test write failed");
          const i = data.records.findIndex((r) => r.key === key);
          if (i < 0) data.records.push({ key, payload });
          else data.records[i] = { key, payload };
        },
      };
    });
    await p.route("http://orbit.test/**", (route) => {
      const file = path.resolve(__dirname, "../ui", new URL(route.request().url()).pathname.slice(1) || "index.html");
      return route.fulfill({
        body: fs.readFileSync(file),
        contentType: file.endsWith(".js") ? "text/javascript" : file.endsWith(".css") ? "text/css" : "text/html",
      });
    });
    await p.goto("http://orbit.test/");
    await p.locator('[data-page="settings"]').click();
    for (const appearance of ["dark", "light", "system"]) {
      await p.locator('[data-page="today"]').click();
      await p.locator('[data-page="settings"]').click();
      await p.locator(`[data-appearance="${appearance}"]`).click();
      assert.equal(await p.locator("html").getAttribute("data-appearance"), appearance);
      assert.equal(await p.locator("h1").innerText(), "Settings");
    }
    await p.getByRole("button", { name: "Account Sign in" }).click();
    const signIn = p.locator('#account [type="submit"]');
    for (const button of [signIn, p.locator("#signup"), p.locator("#forgot-password")])
      assert.equal(await button.isDisabled(), true);
    await p.locator('#account [name="email"]').fill("invalid");
    assert.equal(await p.locator("#forgot-password").isDisabled(), true);
    await p.locator('#account [name="email"]').fill("tester@example.com");
    assert.equal(await p.locator("#forgot-password").isEnabled(), true);
    assert.equal(await signIn.isDisabled(), true);
    await p.locator('#account [name="password"]').fill("short");
    assert.equal(await signIn.isEnabled(), true);
    assert.equal(await p.locator("#signup").isDisabled(), true);
    await p.locator('#account [name="password"]').fill("test-password");
    assert.equal(await p.locator("#signup").isEnabled(), true);
    assert.equal(await p.evaluate(() => window.authCalls.length), 0);

    await p.evaluate(async () => {
      await window.orbit.put("calendars/c1", { id: "c1", title: "Personal", writable: true });
      await window.orbit.put("events/e1", {
        id: "e1",
        calendarID: "c1",
        title: "Visit",
        location: "Old address",
        allDay: false,
        start: new Date().setHours(9, 0, 0, 0),
        end: new Date().setHours(10, 0, 0, 0),
      });
      await load(true);
      openEvent("e1");
    });
    assert.equal(await p.locator('#event-form [name="location"]').inputValue(), "Old address");
    await p.locator('#event-form [name="location"]').fill("123 Main Street");
    await p.locator('#event-form [name="startTime"]').fill("09:37");
    await p.locator('#event-form [name="endTime"]').fill("10:43");
    await p.evaluate(() => {
      window.failWrite = true;
    });
    await p.locator("#save-event").click();
    await p.waitForFunction(() => !actionBusy);
    assert.equal(await p.locator("#event-editor").isVisible(), true);
    assert.equal(await p.locator('#event-form [name="location"]').inputValue(), "123 Main Street");
    await p.evaluate(() => {
      window.failWrite = false;
    });
    await p.locator("#save-event").click();
    await p.waitForFunction(() => !document.querySelector("#event-editor").open);
    const request = await p.evaluate(
      async () => (await window.orbit.read()).records.find((r) => r.key === "events/e1").payload.request,
    );
    assert.equal(request.location, "123 Main Street");
    assert.equal(new Date(request.start).getMinutes(), 37);
    assert.equal(new Date(request.end).getMinutes(), 43);
    assert.deepEqual(errors, []);
    console.log("PASS: reopened appearance, empty auth, location/minutes and failed calendar draft retention");
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
