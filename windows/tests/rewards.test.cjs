const { test } = require("node:test");
const assert = require("node:assert/strict");
const rewards = require("../ui/rewards.js");
const cases = require("../../shared/test-cases/rewards.json");

for (const c of cases)
  test(`rewards: ${c.name}`, () => {
    const values = rewards.metrics(c.tasks, c.logs);
    assert.deepEqual(values, { completions: c.expect.completions, activeDays: c.expect.activeDays });
    const earned = rewards.earned(values);
    assert.deepEqual(earned, c.expect.earned);
    assert.deepEqual(rewards.accents(earned), c.expect.accents);
  });

test("every unlockable accent has colours and exactly one badge", () => {
  const tokens = require("../../shared/design-tokens.json");
  const unlocks = rewards.data.badges.filter((b) => b.unlocks).map((b) => b.unlocks);
  assert.equal(new Set(unlocks).size, unlocks.length);
  for (const accent of [...rewards.data.freeAccents, ...unlocks]) assert.ok(tokens.accents[accent], accent);
  assert.equal(rewards.unlockedBy("rose").id, "getting-going");
  assert.equal(rewards.unlockedBy("coral"), null);
});
