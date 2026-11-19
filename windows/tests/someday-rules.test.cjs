const test = require("node:test");
const assert = require("node:assert/strict");
const rules = require("../ui/someday-rules.js");
const planning = require("../ui/planning.js");

test("calendar absence only triggers Mum when calendar data is available", () => {
  const dad = { tag: "dads", trigger: "event", calendar: "Family", title: "Kidz @ James" };
  const mum = { ...dad, tag: "mum", trigger: "noEvent" };
  for (const [titles, expected] of [
    [null, [false, false]],
    [[], [false, true]],
    [["Pickup: kidz @ james"], [true, false]],
  ]) {
    assert.deepEqual(
      [dad, mum].map((rule) => rules.matches(rule, "2026-11-18", titles)),
      expected,
    );
  }
});

test("recurrence follows calendar days, explicit month dates, and inclusive ranges", () => {
  const weekly = { tag: "school", trigger: "weeks", start: "2026-03-01", interval: 2 };
  assert.equal(rules.matches(weekly, "2026-03-15"), true);
  assert.equal(rules.matches(weekly, "2026-03-08"), false);
  const monthly = { ...weekly, trigger: "months", start: "2026-01-31" };
  assert.equal(rules.matches(monthly, "2026-02-28"), false);
  assert.equal(rules.matches(monthly, "2026-03-31"), true);
  assert.equal(rules.matches({ ...weekly, trigger: "dates", end: "2026-03-08" }, "2026-03-08"), true);
});

test("a configured capture keeps the full tag and a completed task stays on its completion day", () => {
  assert.deepEqual([...rules.tags("Email me@home, then pack @DADS.")], ["dads"]);
  const parsed = planning.parse("Pack @dads", null, new Date(2026, 10, 18), {
    conditional: true,
    places: [{ name: "dads", days: [3] }],
  });
  assert.deepEqual([parsed.title, parsed.someday, parsed.date], ["Pack @dads", true, null]);
  const active = new Set(["dads"]);
  const plannerDay = () => "2026-11-18";
  assert.equal(rules.onToday(parsed, "2026-11-19", active, plannerDay), true);
  assert.equal(rules.onToday({ ...parsed, completedAt: 1 }, "2026-11-19", active, plannerDay), false);
});
