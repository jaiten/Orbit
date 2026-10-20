// The rules in docs/sync-plan.md, checked by running code in separate processes with different TZ values:
// all-day tasks and check-ins are floating calendar days, habit reminders follow local time, timed tasks are instants.
const test = require("node:test");
const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const path = require("node:path");

const ui = path.resolve(__dirname, "../ui");
/** Runs `body` (a function source taking the ui modules) in a process whose local time zone is `tz`. */
function inZone(tz, body, input = null) {
  const script = `
    const planner = require(${JSON.stringify(ui + "/planner.js")});
    const habits = require(${JSON.stringify(ui + "/habits.js")});
    const quick = require(${JSON.stringify(ui + "/planning.js")});
    const dayKey = planner.localKey;
    const input = ${JSON.stringify(input)};
    process.stdout.write(JSON.stringify((${body})({ planner, habits, quick, dayKey, input })));`;
  return JSON.parse(execFileSync(process.execPath, ["-e", script], { env: { ...process.env, TZ: tz } }).toString());
}
/** The renderer's day for a task: the local day of a timed task's instant, or its floating day. */
const taskDay = `(t, dayKey) => (t.hasTime ? dayKey(new Date(t.dueDate)) : t.localDate)`;

test("an all-day task keeps its day when the device travels", () => {
  const task = inZone(
    "America/Vancouver",
    "({ quick }) => quick.parse('renew passport fri', null, new Date('2026-10-20T12:00:00'))",
  );
  assert.equal(task.date, "2026-10-23");
  const record = { hasTime: false, dueDate: null, localDate: task.date };
  for (const zone of ["Asia/Tokyo", "Pacific/Honolulu", "Europe/London"])
    assert.equal(inZone(zone, `({ dayKey, input }) => (${taskDay})(input, dayKey)`, record), "2026-10-23", zone);
});

test("a habit logged at 23:30 on one device reads as the same day on another", () => {
  const log = inZone(
    "America/Vancouver",
    "({ dayKey }) => ({ habitID: 'h', dayKey: dayKey(new Date('2026-10-20T23:30:00')), count: 1 })",
  );
  assert.equal(log.dayKey, "2026-10-20");
  const habit = { id: "h", frequencyRule: "DAILY", target: 1 };
  const elsewhere = inZone(
    "Europe/London",
    "({ habits, input }) => [habits.checkedOn(input.habit, [input.log], '2026-10-20'), habits.checkedOn(input.habit, [input.log], '2026-10-21')]",
    { habit, log },
  );
  assert.deepEqual(elsewhere, [true, false]);
});

test("a 3pm call shows at the right local time on a device in another zone", () => {
  const due = inZone("America/New_York", "() => new Date('2026-10-20T15:00:00').getTime()");
  const shown = inZone(
    "America/Los_Angeles",
    `({ dayKey, input }) => ({ hour: new Date(input).getHours(), day: (${taskDay})({ hasTime: true, dueDate: input }, dayKey) })`,
    due,
  );
  assert.deepEqual(shown, { hour: 12, day: "2026-10-20" });
});

test("moving a timed task across a daylight-saving change keeps its wall-clock time", () => {
  const moved = inZone(
    "America/Vancouver",
    `({ planner }) => {
    const due = new Date("2026-03-07T09:00:00").getTime();
    const task = planner.moveToDay({ hasTime: true, dueDate: due, localDate: "2026-03-07", reminders: [due - 900000] }, "2026-03-09");
    return { hour: new Date(task.dueDate).getHours(), day: task.localDate, lead: task.dueDate - task.reminders[0] };
  }`,
  );
  assert.deepEqual(moved, { hour: 9, day: "2026-03-09", lead: 900000 });
  assert.equal(inZone("America/Vancouver", "({ habits }) => habits.addDays('2026-03-07', 2)"), "2026-03-09");
});

test("a habit reminder time follows the device's current zone", () => {
  // Stored as minutes after midnight; each device turns it into its own local 7:00.
  const habit = { reminderMinutes: 420 };
  const at = (zone) =>
    inZone(
      zone,
      "({ input }) => { const d = new Date('2026-10-21T00:00:00'); d.setMinutes(input.reminderMinutes); return [d.getHours(), d.getMinutes()]; }",
      habit,
    );
  assert.deepEqual(at("Asia/Tokyo"), [7, 0]);
  assert.deepEqual(at("America/Vancouver"), [7, 0]);
});
