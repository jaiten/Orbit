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

test("notes group by last edit the way iOS does", () => {
  const now = new Date(2026, 10, 12, 15, 0);
  const daysAgo = (n) => new Date(2026, 10, 12 - n, 9, 0);
  assert.equal(OrbitNotes.dateGroupTitle(new Date(2026, 10, 12, 0, 5), now), "Today");
  assert.equal(OrbitNotes.dateGroupTitle(new Date(2026, 10, 12, 23, 0), now), "Today");
  assert.equal(OrbitNotes.dateGroupTitle(daysAgo(1), now), "Yesterday");
  assert.equal(OrbitNotes.dateGroupTitle(daysAgo(2), now), "Previous 7 Days");
  assert.equal(OrbitNotes.dateGroupTitle(daysAgo(7), now), "Previous 7 Days");
  assert.equal(OrbitNotes.dateGroupTitle(daysAgo(8), now), "Previous 30 Days");
  assert.equal(OrbitNotes.dateGroupTitle(daysAgo(30), now), "Previous 30 Days");
  assert.equal(OrbitNotes.dateGroupTitle(new Date(2026, 8, 1), now), "September");
  assert.equal(OrbitNotes.dateGroupTitle(new Date(2025, 11, 31), now), "2025");
  const groups = OrbitNotes.dateGroups(
    [daysAgo(0), daysAgo(0), daysAgo(1), daysAgo(3), new Date(2024, 1, 1)].map((d) => ({ updatedAt: d.getTime() })),
    (n) => n.updatedAt,
    now,
  );
  assert.deepEqual(
    groups.map((g) => [g.title, g.items.length]),
    [
      ["Today", 2],
      ["Yesterday", 1],
      ["Previous 7 Days", 1],
      ["2024", 1],
    ],
  );
});
