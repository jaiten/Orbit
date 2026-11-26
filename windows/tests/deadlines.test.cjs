const { test } = require("node:test");
const assert = require("node:assert/strict");
const { deadlineLabel } = require("../ui/planner.js");
const table = require("../../shared/test-cases/deadlines.json");

for (const item of table.cases)
  test(`due date: ${item.name}`, () => {
    assert.deepEqual(deadlineLabel(item.deadline, item.today), { text: item.text, state: item.state });
  });

test("due date: none or malformed has no label", () => {
  assert.equal(deadlineLabel(null, "2026-11-26"), null);
  assert.equal(deadlineLabel("", "2026-11-26"), null);
  assert.equal(deadlineLabel("soon", "2026-11-26"), null);
});
