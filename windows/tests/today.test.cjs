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

test("moving keeps the time of day and reminder offsets; Someday clears dates and reminders", () => {
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
  const later = planner.moveLater({ ...task, listID: "work" }, 1);
  assert.deepEqual([later.listID, later.localDate, later.dueDate], ["work", null, null]);
});

test("overdue labels name the weekday within a week", () => {
  assert.equal(planner.overdueLabel("2026-10-20", "2026-10-22", "en-US"), "from Tue");
  assert.equal(planner.overdueLabel("2026-10-01", "2026-10-22", "en-US"), "from Oct 1");
});
