const { test } = require("node:test");
const assert = require("node:assert/strict");
const { parse } = require("../ui/planning.js");
test("quick add interprets tomorrow and a time", () => {
  const result = parse("gym tomorrow 6am", null, new Date(2026, 9, 19, 12));
  assert.equal(result.title, "gym");
  assert.equal(result.localDate, "2026-10-20");
  assert.equal(new Date(result.dueDate).getHours(), 6);
  assert.equal(result.hasTime, true);
});
test("quick add preserves an explicit planning day", () => {
  const result = parse("read 8pm", "2026-10-22", new Date(2026, 9, 19, 12));
  assert.equal(result.localDate, "2026-10-22");
  assert.equal(new Date(result.dueDate).getHours(), 20);
});
test("plain capture stays unscheduled and arbitrary digits stay in the title", () => {
  const result = parse("Buy 13 apples");
  assert.equal(result.localDate, null);
  assert.equal(result.hasTime, false);
  assert.equal(result.title, "Buy 13 apples");
});
