const test = require("node:test");
const assert = require("node:assert/strict");
const OrbitNotes = require("../ui/notes.js");
const { cases } = require("../../shared/test-cases/notes.json");

for (const c of cases) {
  test(`note rules: ${c.text.slice(0, 40)}`, () => {
    assert.equal(OrbitNotes.isNote(c.text), c.isNote);
    assert.deepEqual(OrbitNotes.split(c.text), { title: c.title, body: c.body });
  });
}
