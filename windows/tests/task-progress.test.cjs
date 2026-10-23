const test = require("node:test");
const assert = require("node:assert/strict");
const { suggestsProgress, setProgress } = require("../ui/planner.js");
const { cases } = require("../../shared/test-cases/task-progress.json");
test("progress suggestions match chore phrases without matching shopping or quick follow-ups", () => {
  for (const row of cases) assert.equal(suggestsProgress(row.title), row.expect, row.title);
});
test("starting is durable activity, not completion, and can be reset or declined", () => {
  const task = { id: "laundry", title: "Laundry", completedAt: null };
  const enabled = setProgress(task, true, false, 100);
  assert.equal(enabled.startedAt, null);
  const started = setProgress(enabled, true, true, 200);
  assert.equal(started.startedAt, 200);
  assert.equal(started.completedAt, null);
  assert.equal(started.updatedAt, 200);
  assert.equal(setProgress(started, true, false, 300).startedAt, null);
  const declined = setProgress(started, false, false, 400);
  assert.equal(declined.progressTracking, false);
  assert.equal(declined.startedAt, null);
  assert.equal(task.progressTracking, undefined);
});
