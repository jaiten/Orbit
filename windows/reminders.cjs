// Native reminders for tasks and habits, driven by one timer for the next reminder.
const habits = require("./ui/habits.js");
const { SOMEDAY_LIST_ID } = require("./ui/planner.js");

const localKey = (d) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
/** Reminders older than this when the timer finally runs (sleep, busy PC) are skipped, not delivered late. */
const LATE_LIMIT = 15 * 60000;
/** The timer never waits longer than this, so midnight and time-zone changes are picked up. */
const MAX_WAIT = 60 * 60000;

/**
 * Upcoming reminders from the records, soonest first, over the next `days` days.
 * Task reminders are fixed instants. Habit reminder times are minutes after local midnight,
 * only on days the habit is due and not yet checked.
 */
function upcoming(records, now = Date.now(), days = 2) {
  const live = records.filter((r) => !r.deleted);
  const of = (entity) => live.filter((r) => r.key.startsWith(entity + "/")).map((r) => r.payload);
  const logs = of("habit_logs");
  const result = [];
  for (const t of of("tasks")) {
    if (t.completedAt || t.listID === SOMEDAY_LIST_ID) continue;
    (t.reminders || []).forEach((at, index) => {
      if (Number.isFinite(at)) result.push({ id: `task:${t.id}:${index}`, title: t.title, body: "Reminder", at });
    });
  }
  const start = new Date(now);
  for (let offset = 0; offset < days; offset++) {
    const day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + offset);
    const key = localKey(day);
    for (const h of of("habits")) {
      if (!habits.dueOn(h, logs, key) || habits.checkedOn(h, logs, key)) continue;
      for (const [kind, minutes] of [
        ["reminder", h.reminderMinutes],
        ["nudge", h.nudgeMinutes],
      ]) {
        if (!Number.isInteger(minutes)) continue;
        const at = new Date(day.getFullYear(), day.getMonth(), day.getDate(), Math.floor(minutes / 60), minutes % 60);
        const body = kind === "nudge" ? "Not checked yet today." : "Habit reminder";
        result.push({ id: `habit:${h.id}:${key}:${kind}`, title: h.title, body, at: at.getTime() });
      }
    }
  }
  return result.filter((r) => r.at > now - LATE_LIMIT).sort((a, b) => a.at - b.at);
}

/** Keeps one timer for the next reminder. `show` displays a notification; `read` returns the records. */
class ReminderScheduler {
  constructor({ read, show, enabled = () => true, clock = { now: Date.now, setTimeout, clearTimeout } }) {
    Object.assign(this, { read, show, enabled, clock, timer: null, shown: new Set(), next: null });
  }
  /** Re-plans from the current records. Call after every change, sync, wake and on launch. */
  reschedule() {
    if (this.timer) this.clock.clearTimeout(this.timer);
    this.timer = null;
    this.next = null;
    if (!this.enabled()) return null;
    const now = this.clock.now();
    for (const due of upcoming(this.read(), now).filter((r) => r.at <= now && !this.shown.has(r.id))) {
      this.shown.add(due.id);
      this.show(due);
    }
    this.next = upcoming(this.read(), now).find((r) => r.at > now && !this.shown.has(r.id)) || null;
    const wait = this.next ? Math.min(this.next.at - now, MAX_WAIT) : MAX_WAIT;
    this.timer = this.clock.setTimeout(() => this.reschedule(), Math.max(1000, wait));
    this.timer?.unref?.();
    return this.next;
  }
  stop() {
    if (this.timer) this.clock.clearTimeout(this.timer);
    this.timer = null;
  }
}

module.exports = { upcoming, ReminderScheduler, LATE_LIMIT, MAX_WAIT };
