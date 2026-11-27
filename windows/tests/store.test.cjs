const { test } = require("node:test");
const assert = require("node:assert/strict");
const { Store } = require("../store.cjs");
const { Sync } = require("../sync.cjs");
const { randomUUID } = require("node:crypto");
const { mkdtempSync, rmSync } = require("node:fs");
const { tmpdir } = require("node:os");
const path = require("node:path");
test("offline changes survive restart, including tombstones", () => {
  const folder = mkdtempSync(path.join(tmpdir(), "orbit-"));
  const file = path.join(folder, "test.sqlite");
  let s = new Store(file);
  s.put("tasks/a", { title: "Read" });
  s.put("tasks/a", { title: "Read" }, true);
  s.close();
  s = new Store(file);
  assert.equal(s.rows()[0].deleted, true);
  assert.equal(s.rows()[0].dirty, 1);
  s.close();
  rmSync(folder, { recursive: true });
});
test("old acknowledgment never clears a newer local edit", () => {
  const s = new Store(":memory:");
  s.put("tasks/a", { title: "First" });
  const sent = s.rows()[0];
  s.put("tasks/a", { title: "Second" });
  s.accept({ ...sent, revision: 1 }, sent);
  assert.equal(s.rows()[0].payload.title, "Second");
  assert.equal(s.rows()[0].dirty, 1);
  assert.equal(s.rows()[0].revision, 1);
  s.close();
});
test("conflicting edits preserve local content and can adopt remote", () => {
  const s = new Store(":memory:");
  s.put("tasks/a", { title: "Local", subtasks: [{ title: "A" }] });
  s.accept({
    key: "tasks/a",
    payload: { title: "Local", subtasks: [{ title: "B" }] },
    deleted: false,
    revision: 2,
    mutation: randomUUID(),
  });
  assert.ok(s.rows()[0].conflict);
  assert.equal(s.rows()[0].payload.subtasks[0].title, "A");
  s.resolve("tasks/a", "cloud");
  assert.equal(s.rows()[0].payload.subtasks[0].title, "B");
  assert.equal(s.rows()[0].dirty, 0);
  s.close();
});
test("local conflict resolution rebases without silently uploading", () => {
  const s = new Store(":memory:");
  s.put("tasks/a", { title: "Local" });
  s.accept({ key: "tasks/a", payload: { title: "Remote" }, deleted: false, revision: 3, mutation: randomUUID() });
  s.resolve("tasks/a", "local");
  assert.equal(s.rows()[0].revision, 3);
  assert.equal(s.rows()[0].dirty, 1);
  assert.equal(s.rows()[0].payload.title, "Local");
  s.close();
});
test("account binding prevents data leaking into another account", () => {
  const s = new Store(":memory:");
  s.bind("alice");
  assert.throws(() => s.bind("bob"));
  assert.equal(s.setting("owner"), "alice");
  s.close();
});
test("account deletion clears planner records and owner binding", () => {
  const s = new Store(":memory:");
  s.bind("alice");
  s.put("tasks/a", { title: "Private" });
  s.clearPlanner();
  assert.deepEqual(s.rows(), []);
  assert.equal(s.setting("owner"), undefined);
  assert.doesNotThrow(() => s.bind("new-account"));
  s.close();
});
test("sync retries pending records after network failure", async () => {
  const s = new Store(":memory:");
  s.put("tasks/a", { title: "Offline" });
  const client = {
    auth: { getSession: async () => ({ data: { session: { user: { id: "alice" } } } }) },
    rpc: async () => ({ error: new Error("offline") }),
  };
  const sync = new Sync(s, client, () => {});
  await sync.run();
  assert.equal(s.rows()[0].dirty, 1);
  assert.match(sync.status, /Saved locally/);
  assert.equal(sync.busy, false);
  s.close();
});

test("notes preserve a blank title while tasks and habits still require a name", () => {
  const store = new Store(":memory:");
  store.batch([
    { key: "tasks/body-note", payload: { title: "", notes: "The entire capture", isNote: true } },
    { key: "tasks/photo-note", payload: { title: "", notes: "", photos: [{ id: randomUUID() }], isNote: true } },
  ]);
  assert.equal(store.rows().length, 2);
  assert.equal(store.rows()[0].payload.title, "");
  assert.throws(() => store.put("tasks/empty", { title: "" }), /name is required/);
  assert.throws(() => store.put("habits/empty", { title: "", isNote: true }), /name is required/);
  store.close();
});

test("every write raises the change number, and changedSince returns just those records", () => {
  const { Store } = require("../store.cjs");
  const os = require("node:os"),
    path = require("node:path"),
    fs = require("node:fs");
  const folder = fs.mkdtempSync(path.join(os.tmpdir(), "orbit-seq-"));
  const store = new Store(path.join(folder, "planner.db"));
  try {
    store.put("tasks/a", { id: "a", title: "A" });
    store.put("tasks/b", { id: "b", title: "B" });
    const after = store.seq();
    assert.equal(store.changedSince(0).length, 2);
    assert.deepEqual(store.changedSince(after), []);
    store.put("tasks/a", { id: "a", title: "A again" });
    store.put("tasks/b", { id: "b", title: "B" }, true);
    const changed = store.changedSince(after);
    assert.deepEqual(changed.map((r) => r.key).sort(), ["tasks/a", "tasks/b"]);
    assert.equal(changed.find((r) => r.key === "tasks/b").deleted, true);
    assert.ok(store.seq() > after);
    // Records accepted from the cloud count as changes too.
    const before = store.seq();
    store.accept({ key: "tasks/c", payload: { id: "c", title: "C" }, deleted: false, revision: 1, mutation: "m" });
    assert.deepEqual(
      store.changedSince(before).map((r) => r.key),
      ["tasks/c"],
    );
    const generation = store.generation();
    store.clearPlanner();
    assert.notEqual(store.generation(), generation);
  } finally {
    store.close();
    fs.rmSync(folder, { recursive: true, force: true });
  }
});
