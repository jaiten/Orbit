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

test("note icons use the same preset IDs on Windows and iOS", () => {
  const fs = require("node:fs");
  const path = require("node:path");
  const swift = fs.readFileSync(path.join(__dirname, "../../ios/Shared/NoteRules.swift"), "utf8");
  const iosIDs = [];
  for (const match of swift.matchAll(/\.init\(symbol: "([^"]+)"/g)) iosIDs.push(match[1]);
  const windowsIDs = OrbitNotes.icons.map((choice) => choice.id);
  assert.ok(windowsIDs.length >= 20);
  assert.deepEqual(windowsIDs, iosIDs);
  const paths = new Set();
  for (const choice of OrbitNotes.icons) {
    paths.add(choice.path);
    assert.equal(OrbitNotes.resolveIcon(choice.id), choice);
  }
  assert.equal(paths.size, windowsIDs.length);
});

test("older notes and unknown icon IDs keep the document icon", () => {
  for (const value of [undefined, null, "", "unknown", "<svg onload=alert(1)>"]) {
    assert.equal(OrbitNotes.resolveIcon(value).id, "doc.text");
  }
});
