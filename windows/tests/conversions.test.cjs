const test = require("node:test");
const assert = require("node:assert/strict");
const { convert } = require("../ui/conversions.js");
const { Store } = require("../store.cjs");
const today = "2026-10-19",
  now = new Date(today + "T12:00:00").getTime();
test("task conversion round trip preserves notes, subtasks and identifiers", () => {
  const source = {
    id: "abc",
    title: "Read",
    notes: "Chapter two",
    subtasks: [{ id: "step", title: "Pick book", completed: true }],
    tags: ["personal"],
    recurrenceRule: "FREQ=WEEKLY",
    completedAt: null,
  };
  const habit = convert("tasks", source, [], today, now)[0].payload;
  assert.equal(habit.frequencyRule, "WEEKLY");
  const task = convert("habits", habit, [], today, now)[0].payload;
  assert.equal(task.id, "abc");
  assert.equal(task.notes, "Chapter two");
  assert.deepEqual(task.subtasks, source.subtasks);
  assert.deepEqual(task.tags, source.tags);
  assert.equal(JSON.parse(task.conversionData).source.conversionData, undefined);
});
test("habit conversion and restoration preserve every history entry atomically", () => {
  const store = new Store(":memory:");
  try {
    const source = { id: "abc", title: "Walk", frequencyRule: "DAILY", target: 2, color: "sage", icon: "leaf" };
    const logs = [
      { id: "log", habitID: "abc", dayKey: today, count: 2, updatedAt: now },
      { id: "past", habitID: "abc", dayKey: "2026-10-18", count: 1, updatedAt: now },
    ];
    store.put("habits/abc", source);
    for (const l of logs) store.put("habit_logs/abc-" + l.dayKey, l);
    const changes = convert("habits", source, logs, today, now);
    store.batch(changes);
    assert.equal(changes[0].payload.completedAt, now);
    assert.equal(store.rows().filter((r) => !r.deleted).length, 1);
    const restored = convert("tasks", changes[0].payload, [], today, now);
    store.batch(restored);
    assert.equal(store.rows().find((r) => r.key === "habits/abc").payload.target, 2);
    assert.deepEqual(
      store
        .rows()
        .filter((r) => r.key.startsWith("habit_logs/") && !r.deleted)
        .map((r) => r.payload)
        .sort((a, b) => a.dayKey.localeCompare(b.dayKey)),
      logs.slice().reverse(),
    );
  } finally {
    store.close();
  }
});
