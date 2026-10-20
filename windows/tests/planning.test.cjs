const { test } = require("node:test");
const assert = require("node:assert/strict");
const { parse, describe } = require("../ui/planning.js");
const table = require("../../shared/test-cases/quick-add.json");

const now = new Date(table.now);
for (const c of table.cases) {
  test(`quick add: ${c.input}${c.defaultDate ? ` (viewing ${c.defaultDate})` : ""}`, () => {
    const result = parse(c.input, c.defaultDate ?? null, now);
    const expected = { someday: false, list: null, schedule: null, ...c.expect };
    if (expected.kind === "habit") delete expected.date;
    for (const [name, value] of Object.entries(expected)) assert.deepEqual(result[name], value, name);
  });
}

test("the preview chip says what will be created", () => {
  assert.equal(describe(parse("stretch weekdays 7am", null, now), now, "en-US"), "Habit · Weekdays · 7:00 AM");
  assert.equal(
    describe(parse("gym tomorrow 6pm #health", null, now), now, "en-US"),
    "Task · Tomorrow · 6:00 PM · #health",
  );
  assert.equal(describe(parse("learn piano someday", null, now), now, "en-US"), "Someday");
  assert.equal(describe(parse("Buy milk", null, now), now, "en-US"), "Task · Today");
  assert.equal(describe(parse("", null, now), now, "en-US"), "");
});
