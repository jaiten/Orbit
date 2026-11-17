// Habit schedule rules shared by the renderer, the main process and tests.
// Dates are floating local calendar days ("YYYY-MM-DD"); the arithmetic below uses UTC
// only as a calendar so daylight-saving changes never shift a day.
// The same cases run on iOS: shared/test-cases/habits.json.
(function (root) {
  const SCHEDULES = ["DAILY", "WEEKDAYS", "WEEKENDS", "WEEKLY", "MONTHLY"];
  /** Weekly and monthly habits count towards a target over their week or calendar month, not each day. */
  const PERIODS = ["WEEKLY", "MONTHLY"];
  /**
   * A counter is a habit with no target: every tap adds one to the day's count ("no phone in the
   * washroom: 3 today"). It is never due, never checked and never part of progress, streaks or
   * reminders; its check-ins are simply how many times it happened that day.
   */
  const COUNTER = "COUNTER";
  const isCounter = (habit) => habit.frequencyRule === COUNTER;

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

  /** First day of the calendar month containing `key`. */
  const monthStartKey = (key) => key.slice(0, 8) + "01";
  function nextMonthKey(key) {
    const date = parseKey(monthStartKey(key));
    date.setUTCMonth(date.getUTCMonth() + 1);
    return formatKey(date);
  }
  function previousMonthKey(key) {
    const date = parseKey(monthStartKey(key));
    date.setUTCMonth(date.getUTCMonth() - 1);
    return formatKey(date);
  }

  function schedule(habit) {
    return SCHEDULES.includes(habit.frequencyRule) ? habit.frequencyRule : "DAILY";
  }
  /** "week" or "month" for habits counted over a period, otherwise null. */
  const period = (habit) => ({ WEEKLY: "week", MONTHLY: "month" })[schedule(habit)] ?? null;
  function dailyTarget(habit) {
    return PERIODS.includes(schedule(habit)) ? 1 : Math.max(1, habit.target || 1);
  }
  function scheduledOn(habit, key) {
    if (isCounter(habit)) return false;
    const day = weekday(key);
    if (schedule(habit) === "WEEKDAYS") return day >= 1 && day <= 5;
    if (schedule(habit) === "WEEKENDS") return day === 0 || day === 6;
    return true;
  }
  function dayCount(habit, logs, key) {
    return logs.filter((l) => l.habitID === habit.id && l.dayKey === key).reduce((sum, l) => sum + l.count, 0);
  }
  function checkedOn(habit, logs, key) {
    return !isCounter(habit) && dayCount(habit, logs, key) >= dailyTarget(habit);
  }
  /** How many times in the `days` days ending with `key` (for a counter's "12 this week"). */
  function countOver(habit, logs, key, days = 7) {
    const start = addDays(key, 1 - days);
    return logs
      .filter((l) => l.habitID === habit.id && l.dayKey >= start && l.dayKey <= key)
      .reduce((sum, l) => sum + l.count, 0);
  }
  /** Check-ins in the habit's period: the day, the week for weekly habits, the month for monthly ones. */
  function periodProgress(habit, logs, key, weekStart = 0) {
    if (!period(habit)) return dayCount(habit, logs, key);
    const monthly = period(habit) === "month";
    const start = monthly ? monthStartKey(key) : weekStartKey(key, weekStart),
      end = monthly ? nextMonthKey(key) : addDays(start, 7);
    return logs
      .filter((l) => l.habitID === habit.id && l.dayKey >= start && l.dayKey < end)
      .reduce((sum, l) => sum + l.count, 0);
  }
  /**
   * A habit is shown on a day it is scheduled. A weekly or monthly habit stops asking once its target
   * for the week or month is met.
   */
  function dueOn(habit, logs, key, weekStart = 0) {
    if (!scheduledOn(habit, key)) return false;
    if (!period(habit)) return true;
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
  /**
   * Scheduled days checked in a row ending on `key` (unscheduled days are skipped), or for a weekly
   * habit, weeks in a row that met the weekly target. Cases: shared/test-cases/streaks.json.
   */
  function streak(habit, logs, key, weekStart = 0) {
    let count = 0;
    if (isCounter(habit)) return 0;
    if (schedule(habit) === "WEEKLY") {
      const target = Math.max(1, habit.target || 1);
      for (let week = weekStartKey(key, weekStart); count < 520; week = addDays(week, -7)) {
        if (periodProgress(habit, logs, week, weekStart) < target) break;
        count++;
      }
      return count;
    }
    if (schedule(habit) === "MONTHLY") {
      const target = Math.max(1, habit.target || 1);
      for (let month = monthStartKey(key); count < 120; month = previousMonthKey(month)) {
        if (periodProgress(habit, logs, month, weekStart) < target) break;
        count++;
      }
      return count;
    }
    for (let day = key, i = 0; i < 3660; day = addDays(day, -1), i++) {
      if (!scheduledOn(habit, day)) continue;
      if (!checkedOn(habit, logs, day)) break;
      count++;
    }
    return count;
  }
  const MILESTONES = {
    day: [7, 14, 30, 50, 100, 200, 365],
    week: [4, 8, 12, 26, 52],
    month: [3, 6, 12, 24],
  };
  /** "7 days in a row" (or weeks, or months) when a streak lands exactly on a milestone, otherwise null. */
  function milestone(habit, count) {
    const unit = period(habit) || "day";
    return MILESTONES[unit].includes(count) ? `${count} ${unit}s in a row` : null;
  }
  function label(habit) {
    if (isCounter(habit)) return "Counter";
    return { DAILY: "Daily", WEEKDAYS: "Weekdays", WEEKENDS: "Weekends", WEEKLY: "Weekly", MONTHLY: "Monthly" }[
      schedule(habit)
    ];
  }
  const COLORS = ["sage", "lavender", "clay", "honey"];
  /**
   * A new habit's default colour, so habits mix: the least used so far, never the newest habit's,
   * trying colours in order after the newest one. `existing` is habit colours, oldest first.
   */
  function nextColor(existing) {
    const counts = Object.fromEntries(COLORS.map((c) => [c, 0]));
    existing.forEach((c) => {
      if (c in counts) counts[c] += 1;
    });
    const last = existing[existing.length - 1];
    const start = COLORS.includes(last) ? COLORS.indexOf(last) + 1 : 0;
    const order = COLORS.map((_, i) => COLORS[(start + i) % COLORS.length]);
    const fewest = Math.min(...COLORS.map((c) => counts[c]));
    return order.find((c) => counts[c] === fewest && c !== last) ?? order.find((c) => c !== last);
  }

  const api = {
    SCHEDULES,
    COUNTER,
    isCounter,
    countOver,
    addDays,
    weekday,
    weekStartKey,
    schedule,
    period,
    dailyTarget,
    scheduledOn,
    dayCount,
    checkedOn,
    periodProgress,
    dueOn,
    checkedDays,
    streak,
    milestone,
    consistency,
    label,
    COLORS,
    nextColor,
  };
  if (typeof module === "object") module.exports = api;
  else root.OrbitHabits = api;
})(typeof window === "object" ? window : globalThis);
