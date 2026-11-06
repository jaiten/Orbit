const test = require("node:test");
const assert = require("node:assert/strict");
const cal = require("../calendar-export.cjs");

const timed = {
  title: "Dentist, check-up",
  notes: "Bring card;\nask about x-ray",
  hasTime: true,
  dueDate: Date.UTC(2026, 10, 6, 14, 30),
  durationMinutes: 45,
};
const allDay = { title: "Passport", localDate: "2026-11-30", hasTime: false };

test("only dated tasks become events; timed ones keep their length", () => {
  assert.equal(cal.eventFor({ title: "Someday" }), null);
  assert.deepEqual(cal.eventFor(timed), {
    title: "Dentist, check-up",
    notes: "Bring card;\nask about x-ray",
    start: timed.dueDate,
    end: timed.dueDate + 45 * 60000,
  });
  assert.deepEqual(cal.eventFor(allDay), { title: "Passport", notes: "", day: "2026-11-30" });
});
test("Google and Outlook links carry the event", () => {
  const google = new URL(cal.googleURL(cal.eventFor(timed)));
  assert.equal(google.hostname, "calendar.google.com");
  assert.equal(google.searchParams.get("dates"), "20261106T143000Z/20261106T151500Z");
  assert.equal(google.searchParams.get("text"), "Dentist, check-up");
  assert.equal(new URL(cal.googleURL(cal.eventFor(allDay))).searchParams.get("dates"), "20261130/20261201");
  const outlook = new URL(cal.outlookURL(cal.eventFor(allDay)));
  assert.equal(outlook.hostname, "outlook.live.com");
  assert.equal(outlook.searchParams.get("enddt"), "2026-12-01");
  assert.equal(outlook.searchParams.get("allday"), "true");
});
test(".ics files escape text and use dates for all-day events", () => {
  const file = cal.ics(cal.eventFor(timed), { uid: "t1", now: Date.UTC(2026, 10, 1) });
  assert.match(file, /DTSTART:20261106T143000Z\r\nDTEND:20261106T151500Z/);
  assert.match(file, /SUMMARY:Dentist\\, check-up/);
  assert.ok(file.includes(String.raw`DESCRIPTION:Bring card\;\nask about x-ray`));
  assert.match(
    cal.ics(cal.eventFor(allDay), { uid: "t2" }),
    /DTSTART;VALUE=DATE:20261130\r\nDTEND;VALUE=DATE:20261201/,
  );
  const long = cal.ics({ title: "x".repeat(200), notes: "", start: 0, end: 1 }, { uid: "t3" });
  assert.ok(long.split("\r\n").every((line) => Buffer.byteLength(line) <= 75));
});
