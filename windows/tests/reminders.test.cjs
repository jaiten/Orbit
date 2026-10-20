const test = require("node:test");
const assert = require("node:assert/strict");
const { upcoming, ReminderScheduler, MAX_WAIT } = require("../reminders.cjs");

const at = (s) => new Date(s).getTime();
const task = (id, extra) => ({
  key: "tasks/" + id,
  deleted: false,
  payload: { id, title: id, reminders: [], completedAt: null, listID: null, ...extra },
});
const habit = (id, extra) => ({
  key: "habits/" + id,
  deleted: false,
  payload: { id, title: id, frequencyRule: "DAILY", target: 1, reminderMinutes: null, nudgeMinutes: null, ...extra },
});

test("tasks remind at their instants; completed and Someday tasks never remind", () => {
  const now = at("2026-10-20T09:00:00");
  const list = upcoming(
    [
      task("call", { reminders: [at("2026-10-20T14:50:00")] }),
      task("done", { reminders: [at("2026-10-20T10:00:00")], completedAt: now }),
      task("idea", { reminders: [at("2026-10-20T11:00:00")], listID: "00000000-0000-4000-8000-000000000001" }),
    ],
    now,
  );
  assert.deepEqual(
    list.map((r) => r.title),
    ["call"],
  );
});

test("habit reminders follow local time, only on due days, and stop once checked", () => {
  const now = at("2026-10-23T06:00:00"); // Friday
  const records = [
    habit("stretch", { frequencyRule: "WEEKDAYS", reminderMinutes: 420 }),
    habit("walk", { frequencyRule: "WEEKENDS", reminderMinutes: 480 }),
    habit("read", { reminderMinutes: 1260 }),
    { key: "habit_logs/read-2026-10-23", deleted: false, payload: { habitID: "read", dayKey: "2026-10-23", count: 1 } },
  ];
  const list = upcoming(records, now).map((r) => [r.title, new Date(r.at).getDay(), new Date(r.at).getHours()]);
  assert.deepEqual(list, [
    ["stretch", 5, 7],
    ["walk", 6, 8],
    ["read", 6, 21],
  ]);
});

test("one timer for the next reminder; late reminders after sleep are skipped", () => {
  let now = at("2026-10-20T09:00:00");
  const timers = [];
  const shown = [];
  const records = [
    task("early", { reminders: [at("2026-10-20T07:00:00")] }),
    task("soon", { reminders: [at("2026-10-20T09:05:00")] }),
    task("later", { reminders: [at("2026-10-20T16:00:00")] }),
  ];
  const scheduler = new ReminderScheduler({
    read: () => records,
    show: (r) => shown.push(r.title),
    clock: { now: () => now, setTimeout: (fn, ms) => timers.push({ fn, ms }) && timers.length, clearTimeout() {} },
  });
  assert.equal(scheduler.reschedule().title, "soon");
  assert.equal(timers.at(-1).ms, 5 * 60000);
  now = at("2026-10-20T09:05:00");
  timers.at(-1).fn();
  assert.deepEqual(shown, ["soon"], "the 7:00 reminder was already two hours late");
  assert.equal(scheduler.next.title, "later");
  assert.equal(timers.at(-1).ms, MAX_WAIT, "re-checks at least hourly for midnight and zone changes");
  scheduler.reschedule();
  assert.deepEqual(shown, ["soon"], "never shown twice");
});

test("turning reminders off clears the timer", () => {
  const scheduler = new ReminderScheduler({
    read: () => [task("call", { reminders: [Date.now() + 60000] })],
    show() {},
    enabled: () => false,
  });
  assert.equal(scheduler.reschedule(), null);
  assert.equal(scheduler.timer, null);
});
