const { test } = require("node:test");
const assert = require("node:assert/strict");
const R = require("../ui/repeats.js");
const table = require("../../shared/test-cases/repeats.json");

for (const item of table.cases)
  test(`repeat: ${item.name}`, () => {
    const t = item.task;
    const next = R.nextDays(
      { day: t.day, deadline: t.deadline, repeat: t.repeat, every: t.repeatEvery },
      item.completedDay,
    );
    assert.deepEqual(next, { day: item.expect.day, deadline: item.expect.deadline });
    assert.equal(R.occurrenceID(t.id, next.day || next.deadline), item.expect.id);
  });

test("repeat: labels, choices and unknown rules", () => {
  assert.equal(R.label({ repeat: "weekly", repeatEvery: 2 }), "Every 2 weeks");
  assert.equal(R.label({ repeat: "weekdays" }), "Every weekday");
  assert.equal(R.label({ repeat: "DAILY" }), "");
  assert.equal(R.choice({ repeat: "monthly" }), "monthly:1");
  assert.equal(R.nextDays({ day: "2026-11-27", repeat: "hourly" }, "2026-11-27"), null);
  assert.match(
    R.occurrenceID("abc", "2026-11-27"),
    /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
  );
});
