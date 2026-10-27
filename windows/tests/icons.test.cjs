const test = require("node:test");
const assert = require("node:assert/strict");
const icons = require("../ui/icons.js");
const { cases } = require("../../shared/test-cases/icons.json");
test("automatic icon matches use whole words and agree with iOS", () => {
  for (const row of cases) assert.equal(icons.suggested(row.title), row.expect, row.title);
  assert.equal(icons.resolve("leaf", "Gym").id, "leaf");
  assert.equal(icons.resolve("automatic", "Gym").id, "dumbbell");
  assert.equal(icons.resolve("unknown", "Gym").id, "checklist");
  assert.equal(new Set(icons.all.map((icon) => icon.id)).size, icons.all.length);
});
test("date groups keep completed and Someday tasks out of overdue", () => {
  const { dateGroup } = require("../ui/planner.js");
  const today = "2026-10-22";
  for (const [item, expected] of [
    [{ day: "2026-10-20" }, "Overdue"],
    [{ day: today }, "Today"],
    [{ day: "2026-10-24" }, "Upcoming"],
    [{ day: null }, "Someday"],
    [{ day: "2026-10-20", someday: true }, "Someday"],
    [{ day: "2026-10-20", completedDay: today, someday: true }, "Completed"],
  ])
    assert.equal(dateGroup(item, today), expected);
});
