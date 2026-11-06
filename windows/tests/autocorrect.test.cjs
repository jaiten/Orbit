const test = require("node:test");
const assert = require("node:assert/strict");
const auto = require("../ui/autocorrect.js");

const on = { enabled: true, apostrophes: true, spelling: false };
test("apostrophes are added and the typed capitals kept", () => {
  assert.equal(auto.correct("dont", on, {}), "don't");
  assert.equal(auto.correct("Dont", on, {}), "Don't");
  assert.equal(auto.correct("DONT", on, {}), "DON'T");
  assert.equal(auto.correct("im", on, {}), "I'm");
  assert.equal(auto.correct("i", on, {}), "I");
  assert.equal(auto.correct("youre", on, {}), "you're");
  // Real words that only sometimes take an apostrophe are left alone.
  for (const word of ["its", "were", "well", "ill", "id", "lets", "shell", "shed", "hell", "wed"])
    assert.equal(auto.correct(word, on, {}), null, word);
  assert.equal(auto.correct("dont", { ...on, apostrophes: false }, {}), null);
});
test("common typos and your own rules", () => {
  assert.equal(auto.correct("teh", on, {}), "the");
  assert.equal(auto.correct("Teh", on, {}), "The");
  assert.equal(auto.correct("recieve", on, {}), "receive");
  const rules = auto.parseRules("btw = by the way\nomw -> on my way\nteh → teh\nnot a rule");
  assert.deepEqual(rules, { btw: "by the way", omw: "on my way", teh: "teh" });
  assert.equal(auto.correct("btw", on, rules), "by the way");
  // A rule mapping a word to itself switches that correction off.
  assert.equal(auto.correct("teh", on, rules), null);
  assert.equal(auto.correct("dont", { ...on, enabled: false }, {}), null);
  assert.equal(auto.correct("hello", on, {}), null);
});
test("a swapped pair of letters is one slip", () => {
  assert.equal(auto.distance("recieve", "receive"), 1);
  assert.equal(auto.distance("form", "from"), 1);
  assert.equal(auto.distance("cat", "dog"), 3);
});
