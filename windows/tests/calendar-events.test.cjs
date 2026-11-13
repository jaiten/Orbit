const { test } = require("node:test");
const assert = require("node:assert/strict");
const events = require("../ui/calendar-events.js");

const at = (text) => new Date(text).getTime();
const timed = (id, start, end, extra = {}) => ({
  id,
  calendarID: "c1",
  title: id,
  allDay: false,
  start: at(start),
  end: at(end),
  ...extra,
});

test("hidden calendars and pending deletes stay out of view; pending edits show their new values", () => {
  const list = [
    timed("a", "2026-11-13T09:00:00", "2026-11-13T10:00:00"),
    timed("b", "2026-11-13T11:00:00", "2026-11-13T12:00:00", { calendarID: "c2" }),
    timed("c", "2026-11-13T13:00:00", "2026-11-13T14:00:00", { request: { kind: "delete", at: 1 } }),
    timed("d", "2026-11-13T15:00:00", "2026-11-13T16:00:00", {
      request: {
        kind: "edit",
        title: "Moved",
        allDay: false,
        start: at("2026-11-14T08:00:00"),
        end: at("2026-11-14T09:00:00"),
        at: 1,
      },
    }),
  ];
  const shown = events.visible(list, [
    { id: "c1", shown: true },
    { id: "c2", shown: false },
  ]);
  assert.deepEqual(
    shown.map((e) => e.id),
    ["a", "d"],
  );
  assert.equal(shown[1].title, "Moved");
  assert.equal(shown[1].pending, true);
  assert.deepEqual(
    events.timedOn(shown, "2026-11-14").map((item) => item.event.id),
    ["d"],
  );
});

test("all-day events cover each day up to their exclusive end day", () => {
  const trip = { id: "trip", calendarID: "c1", allDay: true, startDay: "2026-11-13", endDay: "2026-11-16" };
  assert.equal(events.allDayOn([trip], "2026-11-12").length, 0);
  assert.equal(events.allDayOn([trip], "2026-11-15").length, 1);
  assert.equal(events.allDayOn([trip], "2026-11-16").length, 0);
  assert.equal(events.allDayOn([{ ...trip, endDay: undefined }], "2026-11-13").length, 1);
});

test("timed events crossing midnight are clipped to each day", () => {
  const late = timed("late", "2026-11-13T23:00:00", "2026-11-14T01:30:00");
  const [first] = events.timedOn([late], "2026-11-13");
  const [second] = events.timedOn([late], "2026-11-14");
  assert.equal(first.durationMinutes, 60);
  assert.equal(second.dueDate, at("2026-11-14T00:00:00"));
  assert.equal(second.durationMinutes, 90);
});

test("edits and deletes keep the phone's snapshot and add a request for the iPhone to apply", () => {
  const event = timed("a", "2026-11-13T09:00:00", "2026-11-13T10:00:00");
  const edited = events.editRequest(
    event,
    { title: "Dentist", start: at("2026-11-13T10:00:00"), end: at("2026-11-13T09:00:00") },
    7,
  );
  assert.equal(edited.title, "a");
  assert.deepEqual(edited.request, {
    kind: "edit",
    title: "Dentist",
    allDay: false,
    start: at("2026-11-13T10:00:00"),
    end: at("2026-11-13T10:05:00"),
    at: 7,
  });
  const allDay = events.editRequest(event, { allDay: true, startDay: "2026-11-20" }, 8);
  assert.deepEqual(allDay.request, {
    kind: "edit",
    title: "a",
    allDay: true,
    startDay: "2026-11-20",
    endDay: "2026-11-21",
    at: 8,
  });
  assert.deepEqual(events.deleteRequest({ ...event, pending: true }, 9).request, { kind: "delete", at: 9 });
  assert.equal("pending" in events.deleteRequest({ ...event, pending: true }, 9), false);
});
