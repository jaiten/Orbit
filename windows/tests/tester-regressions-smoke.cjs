/* global load, openEvent, actionBusy, render, today, OrbitHabits, pageHTML, buildPageHTML, withRenderRows: writable, rows, state */
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
    await p.route("http://localhost/**", (route) => {
      const file = path.resolve(__dirname, "../ui", new URL(route.request().url()).pathname.slice(1) || "index.html");
      return route.fulfill({
        body: fs.readFileSync(file),
        contentType: file.endsWith(".js") ? "text/javascript" : file.endsWith(".css") ? "text/css" : "text/html",
      });
    });
    await p.goto("http://localhost/");
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
    const cacheChecks = await p.evaluate(() => {
      const sameHTML = pageHTML() === buildPageHTML();
      const before = withRenderRows(() => rows("events"))[0].location;
      const record = state.records.find((r) => r.key === "events/e1");
      record.payload.location = "Optimistic address";
      const after = withRenderRows(() => rows("events"))[0].location;
      record.payload.location = before;
      return { sameHTML, after };
    });
    assert.deepEqual(cacheChecks, { sameHTML: true, after: "Optimistic address" });
    if (process.env.ORBIT_BENCHMARK) {
      await p.locator('[data-page="today"]').click();
      const metrics = await p.evaluate(async () => {
        const past = new Date().setDate(new Date().getDate() - 200);
        for (let i = 0; i < 500; i++) {
          const id = `benchmark-task-${i}`;
          await window.orbit.put(`tasks/${id}`, {
            id,
            title: `History ${i}`,
            dueDate: past,
            completedAt: past,
            createdAt: past,
          });
        }
        for (let i = 0; i < 12; i++) {
          const id = `benchmark-habit-${i}`;
          await window.orbit.put(`habits/${id}`, {
            id,
            title: `Routine ${i}`,
            frequencyRule: "DAILY",
            target: 1,
            color: "sage",
            createdAt: past,
          });
          for (let offset = 1; offset <= 180; offset++) {
            const log = `benchmark-log-${i}-${offset}`;
            await window.orbit.put(`habit_logs/${log}`, {
              id: log,
              habitID: id,
              dayKey: OrbitHabits.addDays(today(), -offset),
              count: 1,
            });
          }
        }
        await load(true);
        if (pageHTML() !== buildPageHTML()) throw Error("Cached render differs from uncached render");
        const measure = () => {
          const samples = [];
          for (let i = 0; i < 20; i++) {
            const start = performance.now();
            render();
            document.querySelector("#content").getBoundingClientRect();
            samples.push(performance.now() - start);
          }
          samples.sort((a, b) => a - b);
          return { samples: samples.length, p50_ms: samples[9], p95_ms: samples[18] };
        };
        const cached = measure();
        const cache = withRenderRows;
        try {
          withRenderRows = (build) => build();
          return { cached, uncached: measure() };
        } finally {
          withRenderRows = cache;
        }
      });
      console.log("Today render + layout, 500 historical tasks / 12 habits / 2160 logs:", metrics);
    }
    await p.evaluate(async () => {
      for (const [index, title] of ["Walk", "Read", "Water", "Stretch"].entries()) {
        const id = "stable-" + index;
        await window.orbit.put("habits/" + id, {
          id,
          title,
          frequencyRule: "DAILY",
          target: 1,
          createdAt: Date.now() + index,
        });
      }
      await load(true);
    });
    await p.locator('[data-page="today"]').click();
    if (process.env.ORBIT_BENCHMARK) {
      // Keep this geometry check independent of the optional populated-planner workload.
      await p.evaluate(async () => {
        for (const row of rows("habits").filter((habit) => habit.id.startsWith("benchmark-")))
          await window.orbit.put(row._key, { ...row, createdAt: Date.now() + 172800000 });
        await load(true);
      });
    }
    await p.waitForFunction(() => document.querySelector(".compact-habits")?.classList.contains("columns"));
    await p.waitForFunction(() => document.getAnimations().every((animation) => animation.playState !== "running"));
    const selector = '.habits-compact-card [data-flip^="habit-stable-"]';
    const before = await p.evaluate((selector) => {
      return [...document.querySelectorAll(selector)].map((element) => {
        const cell = element.getBoundingClientRect();
        const list = element.closest(".check-list").getBoundingClientRect();
        return [Math.round(cell.x - list.x), Math.round(cell.y - list.y)];
      });
    }, selector);
    await p.locator(selector).first().getByRole("checkbox").click();
    await p.waitForFunction(async () =>
      (await window.orbit.read()).records.some(
        (record) => record.payload.habitID === "stable-0" && record.payload.count === 1,
      ),
    );
    const during = await p.evaluate(
      (selector) =>
        new Promise((resolve) => {
          const start = performance.now();
          const frames = [];
          function sample(now) {
            frames.push(
              [...document.querySelectorAll(selector)].map((element) => {
                const cell = element.getBoundingClientRect();
                const list = element.closest(".check-list").getBoundingClientRect();
                return [Math.round(cell.x - list.x), Math.round(cell.y - list.y)];
              }),
            );
            if (now - start < 1000) requestAnimationFrame(sample);
            else resolve(frames);
          }
          requestAnimationFrame(sample);
        }),
      selector,
    );
    for (const frame of during)
      assert.deepEqual(frame, before, "Checking a habit must not move its grid or the other habits");
    assert.deepEqual(errors, []);
    console.log(
      "PASS: reopened appearance, empty auth, location/minutes, failed calendar draft retention and stable habit grid",
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
