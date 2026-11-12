const test = require("node:test");
const assert = require("node:assert/strict");
const OrbitNavOrder = require("../ui/nav-order.js");

test("sidebar order keeps known pages, drops unknown ones and appends missing ones", () => {
  assert.deepEqual(OrbitNavOrder.ordered(null), ["today", "calendar", "tasks", "lists", "habits"]);
  assert.deepEqual(OrbitNavOrder.ordered("lists,today,bogus,lists"), ["lists", "today", "calendar", "tasks", "habits"]);
});

test("moving a page puts it at the new position", () => {
  const order = OrbitNavOrder.ordered("");
  assert.deepEqual(OrbitNavOrder.move(order, "lists", 0), ["lists", "today", "calendar", "tasks", "habits"]);
  assert.deepEqual(OrbitNavOrder.move(order, "today", 9), ["calendar", "tasks", "lists", "habits", "today"]);
  assert.deepEqual(OrbitNavOrder.move(order, "habits", -1), ["habits", "today", "calendar", "tasks", "lists"]);
});
