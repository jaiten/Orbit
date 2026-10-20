const test = require("node:test"),
  assert = require("node:assert/strict");
const { merge } = require("../merge.cjs");
const { Store } = require("../store.cjs");
test("metadata-only differences do not ask for conflict review", () => {
  assert.deepEqual(
    merge(
      { id: "a", title: "Gym", updatedAt: 1, conversionData: null, tags: [] },
      { id: "a", title: "Gym", updatedAt: 2 },
      null,
    ),
    { id: "a", title: "Gym", updatedAt: 2 },
  );
});
test("independent field edits combine without losing either change", () => {
  const base = { id: "a", title: "Read", notes: "First", updatedAt: 1 };
  const result = merge(
    { ...base, title: "Read a chapter", updatedAt: 3 },
    { ...base, notes: "Second", updatedAt: 2 },
    base,
  );
  assert.equal(result.title, "Read a chapter");
  assert.equal(result.notes, "Second");
});
test("incompatible edits to one field remain recoverable", () => {
  assert.equal(merge({ title: "Gym" }, { title: "Walk" }, { title: "Read" }), null);
});
test("stored baseline survives edits, allowing automatic revision rebase", () => {
  const s = new Store(":memory:");
  try {
    const base = {
      key: "tasks/a",
      payload: { id: "a", title: "Read", notes: "First" },
      deleted: false,
      revision: 1,
      mutation: "old",
    };
    s.accept(base);
    s.put(base.key, { ...base.payload, title: "Read more" });
    s.accept({ ...base, revision: 2, payload: { ...base.payload, notes: "Second" } });
    const r = s.rows()[0];
    assert.equal(r.conflict, null);
    assert.equal(r.revision, 2);
    assert.equal(r.dirty, 1);
    assert.equal(r.payload.notes, "Second");
    assert.equal(r.payload.title, "Read more");
  } finally {
    s.close();
  }
});

test("submillisecond date encoding noise is not a competing edit", () => {
  assert.ok(
    merge({ title: "Gym", reminders: [1792460000000.0002] }, { title: "Gym", reminders: [1792460000000] }, null),
  );
});

test("two devices converting the same task do not need a review", () => {
  const local = {
    id: "a",
    title: "Stretch",
    frequencyRule: "DAILY",
    conversionData: '{"source":{"id":"a","b":1}}',
    updatedAt: 1,
  };
  const remote = { ...local, conversionData: '{"source":{"b":1,"id":"a"}}', updatedAt: 2 };
  assert.deepEqual(merge(local, remote, null), remote);
});
