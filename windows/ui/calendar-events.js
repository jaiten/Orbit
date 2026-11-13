(function (root) {
  // Calendar events shared by the iPhone through sync. The iPhone reads its calendars and writes one
  // `calendars/<id>` record per calendar and one `events/<id>` record per event occurrence. Windows
  // shows them and asks for changes by adding a `request` to an event record; the iPhone applies the
  // request to the real calendar the next time it syncs, then writes the event back without it.

  const dayKey = (date) =>
    `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
  const dayStartMs = (key) => new Date(`${key}T00:00:00`).getTime();
  const addDays = (key, days) => {
    const date = new Date(`${key}T12:00:00`);
    date.setDate(date.getDate() + days);
    return dayKey(date);
  };

  /** An event as it should look now: a pending edit shows its new values; a pending delete hides it. */
  function effective(event) {
    const request = event.request;
    if (request?.kind === "delete") return null;
    if (request?.kind === "edit") {
      const { kind, at, ...changes } = request;
      return { ...event, ...changes, pending: true };
    }
    return event;
  }

  /** Visible events: not deleted, in a calendar that is shown, with pending edits applied. */
  function visible(events, calendars) {
    const hidden = new Set(calendars.filter((calendar) => calendar.shown === false).map((calendar) => calendar.id));
    return events
      .map(effective)
      .filter(
        (event) =>
          event &&
          !hidden.has(event.calendarID) &&
          (event.allDay ? typeof event.startDay === "string" : Number.isFinite(event.start)),
      );
  }

  /** All-day events covering a day (their end day is exclusive). */
  function allDayOn(events, key) {
    return events.filter(
      (event) => event.allDay && event.startDay <= key && key < (event.endDay || addDays(event.startDay, 1)),
    );
  }

  /**
   * Timed events overlapping a day, clipped to it, shaped like timed tasks (dueDate and
   * durationMinutes) so the day and week grids can lay them out with tasks.
   */
  function timedOn(events, key) {
    const from = dayStartMs(key),
      to = dayStartMs(addDays(key, 1));
    return events
      .filter((event) => !event.allDay && event.start < to && Math.max(event.end || 0, event.start + 1) > from)
      .map((event) => {
        const start = Math.max(event.start, from),
          end = Math.min(Math.max(event.end || 0, event.start + 5 * 60000), to);
        return { event, dueDate: start, durationMinutes: Math.max(5, Math.round((end - start) / 60000)) };
      });
  }

  /** The record to save for an edit made on this PC. */
  function editRequest(event, changes, now = Date.now()) {
    const base = effective(event) || event;
    const next = { ...base, ...changes };
    const request = next.allDay
      ? {
          kind: "edit",
          title: next.title,
          allDay: true,
          startDay: next.startDay,
          endDay: next.endDay && next.endDay > next.startDay ? next.endDay : addDays(next.startDay, 1),
          at: now,
        }
      : {
          kind: "edit",
          title: next.title,
          allDay: false,
          start: next.start,
          end: Math.max(next.end, next.start + 5 * 60000),
          at: now,
        };
    const { pending, ...original } = event;
    return { ...original, request };
  }

  function deleteRequest(event, now = Date.now()) {
    const { pending, ...original } = event;
    return { ...original, request: { kind: "delete", at: now } };
  }

  const api = { effective, visible, allDayOn, timedOn, editRequest, deleteRequest, addDays };
  if (typeof module === "object") module.exports = api;
  else root.OrbitCalendarEvents = api;
})(typeof globalThis === "undefined" ? this : globalThis);
