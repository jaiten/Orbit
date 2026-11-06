const test = require("node:test");
const assert = require("node:assert/strict");
const planner = require("../ui/planner.js");
const { cases } = require("../../shared/test-cases/today.json");

for (const c of cases) {
  test(c.name, () => {
    const item = (i) => ({ day: i.day ?? null, completedDay: i.completedDay ?? null, someday: !!i.someday });
    const day = c.day ?? c.today;
    assert.deepEqual(
      c.items.filter((i) => planner.onDay(item(i), day, c.today)).map((i) => i.title),
      c.expect,
    );
    assert.deepEqual(
      c.items.filter((i) => planner.isOverdue(item(i), c.today)).map((i) => i.title),
      c.overdue,
    );
  });
}

test("moving keeps the time of day and reminder offsets; Someday and categories clear dates and reminders", () => {
  const due = new Date("2026-10-18T09:30:00").getTime();
  const task = {
    id: "t",
    listID: planner.SOMEDAY_LIST_ID,
    hasTime: true,
    dueDate: due,
    localDate: "2026-10-18",
    reminders: [due - 600000],
  };
  const moved = planner.moveToDay(task, "2026-10-20", 1);
  assert.equal(moved.localDate, "2026-10-20");
  assert.equal(new Date(moved.dueDate).getHours(), 9);
  assert.equal(new Date(moved.dueDate).getMinutes(), 30);
  assert.equal(moved.dueDate - moved.reminders[0], 600000);
  assert.equal(moved.listID, null, "leaving Someday");
  const someday = planner.moveToSomeday({ ...task, listID: null }, 1);
  assert.deepEqual(
    [someday.listID, someday.localDate, someday.dueDate, someday.hasTime, someday.reminders],
    [planner.SOMEDAY_LIST_ID, null, null, false, []],
  );
  const filed = planner.moveToList(task, "work", 1);
  assert.deepEqual([filed.listID, filed.localDate, filed.dueDate, filed.reminders], ["work", null, null, []]);
});

test("overdue labels name the weekday within a week", () => {
  assert.equal(planner.overdueLabel("2026-10-20", "2026-10-22", "en-US"), "from Tue");
  assert.equal(planner.overdueLabel("2026-10-01", "2026-10-22", "en-US"), "from Oct 1");
});

test("Tasks groups match iPhone: Someday first, uncategorized by day, then categories", () => {
  const S = planner.SOMEDAY_LIST_ID;
  const entries = [
    { id: "late", day: "2026-11-01", listID: null },
    { id: "now", day: "2026-11-02", listID: null },
    { id: "soon", day: "2026-11-05", listID: null },
    { id: "loose", day: null, listID: null },
    { id: "someday", day: null, listID: S },
    { id: "errand", day: "2026-11-02", listID: "errands" },
    { id: "noteSection", day: null, listID: "personal-notes" },
    { id: "done", day: "2026-11-02", listID: null, completedDay: "2026-11-02" },
  ];
  const groups = planner.taskGroups(entries, [{ id: "errands", name: "Errands" }], "2026-11-02");
  assert.deepEqual(
    groups.map((g) => [g.name, g.items.map((e) => e.id)]),
    [
      ["Someday", ["loose", "someday", "noteSection"]],
      ["Today", ["late", "now"]],
      ["Upcoming", ["soon"]],
      ["Errands", ["errand"]],
      ["Completed", ["done"]],
    ],
  );
});

test("category suggestions follow the shared cases", () => {
  const { cases } = require("../../shared/test-cases/category-suggestions.json");
  for (const c of cases)
    assert.equal(
      planner.suggestCategory(
        c.title,
        c.history.map(([title, category]) => ({ title, category })),
      ),
      c.expect,
      c.name,
    );
});

test("day start follows the shared cases", () => {
  const data = require("../../shared/test-cases/day-start.json");
  assert.deepEqual(planner.DAY_START_CHOICES, data.choices);
  for (const c of data.cases) assert.equal(planner.plannerDayKey(new Date(c.time), c.dayStart), c.expect, c.name);
  for (const c of data.labels) assert.equal(planner.dayStartLabel(c.dayStart), c.expect);
});
