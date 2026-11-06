// Adding a task to the user's own calendar: Google Calendar or Outlook open in the browser with the event
// filled in, and an .ics file opens in whatever calendar app Windows uses (Outlook, Windows Calendar, or
// Apple Calendar via iCloud). Nothing is sent anywhere until the user saves it in their calendar.
// The iPhone app does the same through the system event editor (CalendarBridge.swift).

const pad = (n) => String(n).padStart(2, "0");
/** 20261106T143000Z */
const utcStamp = (ms) => {
  const d = new Date(ms);
  return `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}Z`;
};
/** "2026-11-06" → "20261106" */
const dayStamp = (day) => day.replace(/-/g, "");
const nextDay = (day) => {
  const d = new Date(day + "T12:00:00Z");
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10);
};

/**
 * The event for a task, or null when it has no date. Timed tasks keep their length (30 minutes by
 * default); dated tasks without a time become all-day events.
 */
function eventFor(task) {
  const title = String(task.title || "").trim() || "Orbit task";
  const notes = String(task.notes || "").trim();
  if (task.hasTime && task.dueDate) {
    const start = Number(task.dueDate);
    return { title, notes, start, end: start + Math.max(5, Number(task.durationMinutes) || 30) * 60000 };
  }
  if (typeof task.localDate === "string" && /^\d{4}-\d{2}-\d{2}$/.test(task.localDate))
    return { title, notes, day: task.localDate };
  return null;
}

function googleURL(event) {
  const url = new URL("https://calendar.google.com/calendar/render");
  url.searchParams.set("action", "TEMPLATE");
  url.searchParams.set("text", event.title);
  url.searchParams.set(
    "dates",
    event.day
      ? `${dayStamp(event.day)}/${dayStamp(nextDay(event.day))}`
      : `${utcStamp(event.start)}/${utcStamp(event.end)}`,
  );
  if (event.notes) url.searchParams.set("details", event.notes);
  return url.toString();
}

function outlookURL(event) {
  const url = new URL("https://outlook.live.com/calendar/0/deeplink/compose");
  url.searchParams.set("path", "/calendar/action/compose");
  url.searchParams.set("rru", "addevent");
  url.searchParams.set("subject", event.title);
  if (event.day) {
    url.searchParams.set("startdt", event.day);
    url.searchParams.set("enddt", nextDay(event.day));
    url.searchParams.set("allday", "true");
  } else {
    url.searchParams.set("startdt", new Date(event.start).toISOString());
    url.searchParams.set("enddt", new Date(event.end).toISOString());
  }
  if (event.notes) url.searchParams.set("body", event.notes);
  return url.toString();
}

/** RFC 5545 text: escape \ ; , and new lines, and fold lines at 75 octets. */
const icsText = (value) =>
  String(value).replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\r?\n/g, "\\n");
function fold(line) {
  const parts = [];
  let current = "";
  for (const char of line) {
    if (Buffer.byteLength(current + char) > (parts.length ? 74 : 75)) {
      parts.push(current);
      current = "";
    }
    current += char;
  }
  parts.push(current);
  return parts.join("\r\n ");
}
function ics(event, { uid, now = Date.now() } = {}) {
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Orbit//Planner//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "BEGIN:VEVENT",
    `UID:${uid || `${now}-${Math.random().toString(36).slice(2)}`}@orbit`,
    `DTSTAMP:${utcStamp(now)}`,
    ...(event.day
      ? [`DTSTART;VALUE=DATE:${dayStamp(event.day)}`, `DTEND;VALUE=DATE:${dayStamp(nextDay(event.day))}`]
      : [`DTSTART:${utcStamp(event.start)}`, `DTEND:${utcStamp(event.end)}`]),
    `SUMMARY:${icsText(event.title)}`,
    ...(event.notes ? [`DESCRIPTION:${icsText(event.notes)}`] : []),
    "END:VEVENT",
    "END:VCALENDAR",
  ];
  return lines.map(fold).join("\r\n") + "\r\n";
}

const SERVICES = ["google", "outlook", "ics"];
module.exports = { eventFor, googleURL, outlookURL, ics, SERVICES };
