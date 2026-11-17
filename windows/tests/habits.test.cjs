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
        ...("slipped" in c.expect ? { slipped: habits.slipped(habit, logs, c.day) } : {}),
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

for (const c of require("../../shared/test-cases/streaks.json").cases) {
  test("streak: " + c.name, () => {
    const habit = { id: "h", ...c.habit };
    const full = habits.dailyTarget(habit);
    const logs = [
      ...c.checkedDays.map((dayKey) => ({ habitID: "h", dayKey, count: full })),
      ...(c.partialDays || []).map((dayKey) => ({ habitID: "h", dayKey, count: 1 })),
    ];
    const count = habits.streak(habit, logs, c.day, c.weekStart);
    assert.deepEqual({ streak: count, milestone: habits.milestone(habit, count) }, c.expect);
  });
}

test("avoid habits: ticked days in a row, a slip fails the day and ends the run", () => {
  const habit = { id: "a", frequencyRule: "AVOID", target: 1 };
  const kept = (dayKey) => ({ habitID: "a", dayKey, count: 1 });
  const slip = (dayKey) => ({ habitID: "a", dayKey, count: habits.SLIP });
  const days = ["2026-10-13", "2026-10-14", "2026-10-15", "2026-10-16"];
  assert.equal(habits.streak(habit, days.map(kept), "2026-10-16"), 4);
  assert.equal(
    habits.streak(habit, [...days.slice(0, 2).map(kept), slip("2026-10-15"), kept("2026-10-16")], "2026-10-16"),
    1,
  );
  assert.equal(habits.streak(habit, [], "2026-10-16"), 0);
  assert.equal(habits.slipped(habit, [slip("2026-10-16")], "2026-10-16"), true);
  assert.equal(habits.slipped(habit, [kept("2026-10-16")], "2026-10-16"), false);
  assert.equal(habits.label(habit), "Avoid");
  assert.equal(habits.consistency([habit], [slip("2026-10-16")], "2026-10-16"), 0);
  assert.equal(habits.consistency([habit], [kept("2026-10-16")], "2026-10-16"), 1);
});

test("counter goals: at least is met once reached, at most is fine until passed", () => {
  const counter = (goal, goalKind) => ({ frequencyRule: "COUNTER", target: 1, goal, goalKind });
  assert.equal(habits.goalState(counter(null), 5), null);
  assert.equal(habits.goalState(counter(8, "atLeast"), 3), "short");
  assert.equal(habits.goalState(counter(8, "atLeast"), 8), "met");
  assert.equal(habits.goalState(counter(2, "atMost"), 2), "within");
  assert.equal(habits.goalState(counter(2, "atMost"), 3), "over");
  assert.equal(habits.goalState({ frequencyRule: "DAILY", goal: 3 }, 5), null);
});
