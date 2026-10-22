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
  assert.equal(habit.icon, "automatic");
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

test("repeating tasks migrate to habits with the same ID and their completions as check-ins", () => {
  const { migrateRecurring } = require("../ui/conversions.js");
  const { runMigrations } = require("../migrations.cjs");
  const base = { notes: "", reminders: [], tags: [], subtasks: [], hasTime: false, dueDate: null, priority: 0 };
  const done = (day) => new Date(day + "T18:00:00").getTime();
  const tasks = [
    {
      ...base,
      id: "a1",
      title: "Stretch",
      recurrenceRule: "FREQ=DAILY",
      localDate: "2026-10-17",
      completedAt: done("2026-10-17"),
      nextOccurrenceID: "a2",
    },
    {
      ...base,
      id: "a2",
      title: "Stretch",
      recurrenceRule: "FREQ=DAILY",
      localDate: "2026-10-18",
      completedAt: done("2026-10-18"),
      nextOccurrenceID: "a3",
    },
    {
      ...base,
      id: "a3",
      title: "Stretch",
      recurrenceRule: "FREQ=DAILY",
      localDate: "2026-10-19",
      completedAt: null,
      nextOccurrenceID: null,
    },
    {
      ...base,
      id: "w1",
      title: "Gym",
      recurrenceRule: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR",
      localDate: "2026-10-19",
      completedAt: null,
      nextOccurrenceID: null,
    },
    {
      ...base,
      id: "m1",
      title: "Pay rent",
      recurrenceRule: "FREQ=MONTHLY",
      localDate: "2026-11-01",
      completedAt: null,
      nextOccurrenceID: null,
    },
    {
      ...base,
      id: "o1",
      title: "One-off",
      recurrenceRule: "",
      localDate: "2026-10-19",
      completedAt: null,
      nextOccurrenceID: null,
    },
  ];
  const changes = migrateRecurring(tasks, [], now);
  assert.deepEqual(changes, migrateRecurring(tasks, [], now), "migration is deterministic");
  const byKey = Object.fromEntries(changes.map((c) => [c.key, c]));
  assert.equal(byKey["habits/a3"].payload.frequencyRule, "DAILY");
  assert.equal(byKey["habits/a3"].payload.createdAt, new Date("2026-10-17T00:00:00").getTime());
  assert.equal(byKey["tasks/a3"].deleted, true);
  assert.deepEqual(
    changes
      .filter((c) => c.key.startsWith("habit_logs/a3-"))
      .map((c) => [c.payload.dayKey, c.payload.id])
      .sort(),
    [
      ["2026-10-17", "a1"],
      ["2026-10-18", "a2"],
    ],
  );
  assert.equal(byKey["tasks/a1"], undefined, "completed history stays as it is");
  assert.equal(byKey["habits/w1"].payload.frequencyRule, "WEEKDAYS");
  assert.equal(byKey["tasks/m1"].payload.recurrenceRule, "");
  assert.equal(byKey["tasks/m1"].deleted, undefined);
  assert.equal(byKey["tasks/o1"], undefined);

  const store = new Store(":memory:");
  try {
    for (const t of tasks) store.put("tasks/" + t.id, t);
    assert.ok(runMigrations(store, now) > 0);
    assert.equal(runMigrations(store, now), 0, "a second run has nothing to do");
    const restored = convert("habits", store.rows().find((r) => r.key === "habits/a3").payload, [], today, now);
    assert.equal(restored[0].payload.recurrenceRule, "", "Make It a Task never brings the repeat back");
  } finally {
    store.close();
  }
});
