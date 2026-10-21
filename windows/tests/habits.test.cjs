const test = require("node:test");
const assert = require("node:assert/strict");
const habits = require("../ui/habits.js");
const { cases } = require("../../shared/test-cases/habits.json");

for (const c of cases) {
  test(c.name, () => {
    const habit = { id: "h", ...c.habit };
    const logs = c.logs.map((l) => ({ habitID: "h", ...l }));
    assert.deepEqual(
      {
        due: habits.dueOn(habit, logs, c.day, c.weekStart),
        checked: habits.checkedOn(habit, logs, c.day),
        progress: habits.periodProgress(habit, logs, c.day, c.weekStart),
        lastSeven: habits.checkedDays(habit, logs, c.day, 7),
      },
      c.expect,
    );
  });
}

test("calendar arithmetic does not shift across daylight saving changes", () => {
  assert.equal(habits.addDays("2026-03-07", 1), "2026-03-08");
  assert.equal(habits.addDays("2026-11-01", 1), "2026-11-02");
  assert.equal(habits.addDays("2026-03-01", -1), "2026-02-28");
});

for (const c of require("../../shared/test-cases/consistency.json").cases) {
  test(`consistency: ${c.name}`, () => {
    assert.ok(Math.abs(habits.consistency(c.habits, c.logs, c.day) - c.expect) < 1e-9);
  });
}

const colors = require("../../shared/test-cases/habit-colors.json");
for (const c of colors.cases)
  test(`new habit colour: ${c.name}`, () => assert.equal(habits.nextColor(c.existing), c.expect));
