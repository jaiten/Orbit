const { test } = require("node:test");
const assert = require("node:assert/strict");
const { Store } = require("../store.cjs");
const { PlannerTools, encodeBackup, decodeBackup } = require("../planner-tools.cjs");
const id = "11111111-1111-4111-8111-111111111111";
test("undo restores a deletion without rewinding the server revision", () => {
  const s = new Store(":memory:"),
    t = new PlannerTools(s);
  try {
    t.change([{ key: "tasks/" + id, payload: { id, title: "Read" } }]);
    t.change([{ key: "tasks/" + id, payload: { id, title: "Read" }, deleted: true }]);
    t.undo();
    assert.equal(s.rows()[0].deleted, false);
    assert.equal(s.rows()[0].payload.title, "Read");
    assert.equal(s.rows()[0].dirty, 1);
  } finally {
    s.close();
  }
});
test("undo refuses to replace a changed synced record", () => {
  const s = new Store(":memory:"),
    t = new PlannerTools(s);
  try {
    t.change([{ key: "tasks/" + id, payload: { id, title: "Read", listID: null } }]);
    t.change([{ key: "tasks/" + id, payload: { id, title: "Read", listID: "someday" } }]);
    s.put("tasks/" + id, { id, title: "Different device", listID: "someday" });
    assert.throws(() => t.undo(), /changed on another device/);
    assert.equal(s.rows()[0].payload.title, "Different device");
  } finally {
    s.close();
  }
});
test("backup excludes auth and sync metadata and validates all records before restore", () => {
  const text = encodeBackup([
    { key: "lists/" + id, payload: { id, name: "Work" }, deleted: false, revision: 5, mutation: "private" },
    { key: "tasks/" + id, payload: { id, title: "Deleted" }, deleted: true },
  ]);
  const records = decodeBackup(text);
  assert.equal(records.length, 1);
  assert.equal(records[0].key, "lists/" + id);
  assert.ok(!text.includes("private"));
  assert.throws(
    () => decodeBackup(JSON.stringify({ format: "orbit-backup", version: 1, records: [...records, ...records] })),
    /Invalid/,
  );
  assert.throws(
    () =>
      decodeBackup(
        JSON.stringify({
          format: "orbit-backup",
          version: 1,
          records: [{ key: "owner", payload: { id, title: "Bad" } }],
        }),
      ),
    /Invalid/,
  );
});

const fs = require("node:fs");
const path = require("node:path");
const { planImport, encodeTasksCSV } = require("../planner-tools.cjs");
const fixtures = path.resolve(__dirname, "../../shared/test-cases");
const SOMEDAY = "00000000-0000-4000-8000-000000000001";

test("the shared export sample round-trips exactly through the store", () => {
  const text = fs.readFileSync(path.join(fixtures, "export-sample.json"), "utf8");
  const sample = JSON.parse(text);
  const s = new Store(":memory:");
  try {
    s.batch(decodeBackup(text));
    const exported = JSON.parse(encodeBackup(s.rows(), new Date(sample.exportedAt)));
    assert.deepEqual(exported, sample);
  } finally {
    s.close();
  }
});

test("tasks export to the same CSV as iOS", () => {
  const previous = process.env.TZ;
  process.env.TZ = "UTC"; // The CSV has local times; the sample is checked in UTC.
  try {
    const sample = JSON.parse(fs.readFileSync(path.join(fixtures, "export-sample.json"), "utf8"));
    const csv = encodeTasksCSV(
      sample.records.map((r) => ({ ...r, deleted: false })),
      SOMEDAY,
    );
    assert.equal(csv, fs.readFileSync(path.join(fixtures, "export-sample.csv"), "utf8"));
  } finally {
    process.env.TZ = previous;
  }
});

test("importing never silently overwrites: new, same and changed items are told apart", () => {
  const sample = decodeBackup(fs.readFileSync(path.join(fixtures, "export-sample.json"), "utf8"));
  const mine = sample.slice(0, 4).map((r, i) => ({
    ...r,
    deleted: false,
    payload: i === 3 ? { ...r.payload, title: "Edited here" } : { ...r.payload, updatedAt: 1 },
  }));
  const plan = planImport(mine, sample);
  assert.equal(plan.added.length, sample.length - 4);
  assert.equal(plan.same.length, 3, "only updatedAt differs");
  assert.deepEqual(
    plan.changed.map((r) => r.key),
    [sample[3].key],
  );
  assert.ok(
    decodeBackup(JSON.stringify({ format: "orbit-backup", version: 1, records: sample })),
    "version 1 still imports",
  );
});

test("only deletions, moves and imports offer Undo; ticks, check-ins and edits don't", () => {
  const s = new Store(":memory:"),
    t = new PlannerTools(s);
  const task = { id, title: "Read", listID: null, localDate: "2026-10-21", dueDate: null, completedAt: null };
  try {
    t.change([{ key: "tasks/" + id, payload: task }]);
    assert.equal(t.last, null, "creating");
    t.change([{ key: "tasks/" + id, payload: { ...task, completedAt: 1 } }]);
    assert.equal(t.last, null, "ticking off");
    t.change([{ key: "tasks/" + id, payload: { ...task, title: "Read more" } }]);
    assert.equal(t.last, null, "renaming");
    t.change([{ key: "habit_logs/" + id + "-2026-10-21", payload: { habitID: id, dayKey: "2026-10-21", count: 1 } }]);
    assert.equal(t.last, null, "logging a habit");
    t.change([{ key: "tasks/" + id, payload: { ...task, title: "Read more", localDate: null } }]);
    assert.equal(t.last?.kind, "moved", "Later");
    t.change([{ key: "tasks/" + id, payload: { ...task, title: "Read more", localDate: null, listID: "someday" } }]);
    assert.equal(t.last?.kind, "moved", "Someday");
    t.change([
      { key: "tasks/" + id, payload: task, deleted: true },
      { key: "habits/" + id, payload: { id, title: "Read" } },
    ]);
    assert.equal(t.last?.kind, "moved", "made into a habit");
    t.change([{ key: "habits/" + id, payload: { id, title: "Read" }, deleted: true }]);
    assert.equal(t.last?.kind, "deleted", "deleting");
    t.change([{ key: "tasks/" + id, payload: { ...task, title: "Imported" } }], "imported");
    assert.equal(t.last?.kind, "imported", "importing");
  } finally {
    s.close();
  }
});
