// Habit schedule rules shared by the renderer, the main process and tests.
// Dates are floating local calendar days ("YYYY-MM-DD"); the arithmetic below uses UTC
// only as a calendar so daylight-saving changes never shift a day.
// The same cases run on iOS: shared/test-cases/habits.json.
(function (root) {
  const SCHEDULES = ["DAILY", "WEEKDAYS", "WEEKENDS", "WEEKLY"];

  function parseKey(key) {
    const [y, m, d] = key.split("-").map(Number);
    return new Date(Date.UTC(y, m - 1, d));
  }
  function formatKey(date) {
    return date.toISOString().slice(0, 10);
  }
  function addDays(key, days) {
    const date = parseKey(key);
    date.setUTCDate(date.getUTCDate() + days);
    return formatKey(date);
  }
  function weekday(key) {
    return parseKey(key).getUTCDay();
  }
  /** First day of the week containing `key`; weekStart uses Date#getDay numbering (0 = Sunday). */
  function weekStartKey(key, weekStart = 0) {
    return addDays(key, -((weekday(key) - weekStart + 7) % 7));
  }

  function schedule(habit) {
    return SCHEDULES.includes(habit.frequencyRule) ? habit.frequencyRule : "DAILY";
  }
  function dailyTarget(habit) {
    return schedule(habit) === "WEEKLY" ? 1 : Math.max(1, habit.target || 1);
  }
  function scheduledOn(habit, key) {
    const day = weekday(key);
    if (schedule(habit) === "WEEKDAYS") return day >= 1 && day <= 5;
    if (schedule(habit) === "WEEKENDS") return day === 0 || day === 6;
    return true;
  }
  function dayCount(habit, logs, key) {
    return logs.filter((l) => l.habitID === habit.id && l.dayKey === key).reduce((sum, l) => sum + l.count, 0);
  }
  function checkedOn(habit, logs, key) {
    return dayCount(habit, logs, key) >= dailyTarget(habit);
  }
  /** Check-ins in the habit's period: the day, or the week for weekly habits. */
  function periodProgress(habit, logs, key, weekStart = 0) {
    if (schedule(habit) !== "WEEKLY") return dayCount(habit, logs, key);
    const start = weekStartKey(key, weekStart),
      end = addDays(start, 7);
    return logs
      .filter((l) => l.habitID === habit.id && l.dayKey >= start && l.dayKey < end)
      .reduce((sum, l) => sum + l.count, 0);
  }
  /** A habit is shown on a day it is scheduled. A weekly habit stops asking once its weekly target is met. */
  function dueOn(habit, logs, key, weekStart = 0) {
    if (!scheduledOn(habit, key)) return false;
    if (schedule(habit) !== "WEEKLY") return true;
    return checkedOn(habit, logs, key) || periodProgress(habit, logs, key, weekStart) < Math.max(1, habit.target || 1);
  }
  /** Days checked in the last `days` days, ending with `key`. Missed days are not counted against anything. */
  function checkedDays(habit, logs, key, days = 7) {
    let count = 0;
    for (let i = 0; i < days; i++) if (checkedOn(habit, logs, addDays(key, -i))) count++;
    return count;
  }
  /**
   * Share of habits scheduled on `key` (and created by then, `createdDay`) that were checked.
   * Daily targets give partial credit; a weekly habit counts a check-in on that day.
   */
  function consistency(habits, logs, key) {
    const active = habits.filter((h) => (!h.createdDay || h.createdDay <= key) && scheduledOn(h, key));
    if (!active.length) return 0;
    return active.reduce((sum, h) => sum + Math.min(1, dayCount(h, logs, key) / dailyTarget(h)), 0) / active.length;
  }
  function label(habit) {
    return { DAILY: "Daily", WEEKDAYS: "Weekdays", WEEKENDS: "Weekends", WEEKLY: "Weekly" }[schedule(habit)];
  }

  const api = {
    SCHEDULES,
    addDays,
    weekday,
    weekStartKey,
    schedule,
    dailyTarget,
    scheduledOn,
    dayCount,
    checkedOn,
    periodProgress,
    dueOn,
    checkedDays,
    consistency,
    label,
  };
  if (typeof module === "object") module.exports = api;
  else root.OrbitHabits = api;
})(typeof window === "object" ? window : globalThis);
