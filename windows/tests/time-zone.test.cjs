const { test } = require("node:test");
const assert = require("node:assert/strict");
const { offsetIn, correctedZone, parseWindowsZone } = require("../time-zone.cjs");

const november = Date.UTC(2026, 10, 13, 18);

test("offsets are read per zone and moment", () => {
  assert.equal(offsetIn("America/Los_Angeles", november), -480);
  assert.equal(offsetIn("America/Vancouver", november), -420);
  assert.equal(offsetIn("UTC", november), 0);
  assert.equal(offsetIn("Asia/Kolkata", november), 330);
});

test("British Columbia on Windows corrects an engine that guessed Los Angeles", () => {
  const windows = parseWindowsZone(
    "British Columbia Standard Time|(UTC-07:00) Pacific Time (British Columbia)|-420|False",
  );
  assert.deepEqual(windows, {
    id: "British Columbia Standard Time",
    name: "(UTC-07:00) Pacific Time (British Columbia)",
    offset: -420,
    daylight: false,
  });
  assert.equal(correctedZone(windows, "America/Los_Angeles", { now: november }), "America/Vancouver");
});

test("nothing changes when the engine already agrees with Windows", () => {
  const windows = {
    id: "Pacific Standard Time",
    name: "(UTC-08:00) Pacific Time (US & Canada)",
    offset: -480,
    daylight: true,
  };
  assert.equal(correctedZone(windows, "America/Los_Angeles", { now: november }), null);
});

test("an unknown Windows zone falls back to a zone with the same offset and clock changes", () => {
  const windows = { id: "Mystery Standard Time", name: "(UTC-07:00) Somewhere", offset: -420, daylight: false };
  const zone = correctedZone(windows, "America/Los_Angeles", { now: november });
  assert.ok(zone.startsWith("America/"), zone);
  assert.equal(offsetIn(zone, november), -420);
  assert.equal(offsetIn(zone, Date.UTC(2026, 6, 1)), -420, "no daylight saving");
  assert.equal(
    correctedZone(windows, "America/Los_Angeles", { now: november, zones: [] }),
    "Etc/GMT+7",
    "with no named zone left, a fixed offset",
  );
});
