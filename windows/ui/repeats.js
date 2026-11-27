// Recurring tasks: a task with a `repeat` rule ("daily", "weekdays", "weekly", "monthly", "yearly") and
// `repeatEvery` (2 for every two weeks) makes its next copy when it is ticked off. The planned day and the
// due date both move forward by the rule, past the day it was finished, so missed ones never pile up.
// The copy's ID comes from the task's ID and its new day, so two devices finishing the same task offline
// make the same record. Mirrors ios/Shared/RepeatRules.swift; cases in shared/test-cases/repeats.json.
// (Older versions' `recurrenceRule` is separate: those tasks were turned into habits.)
(function (root) {
  const RULES = ["daily", "weekdays", "weekly", "monthly", "yearly"];
  /** The editor's choices: [value, label]. The value is "rule:every". */
  const CHOICES = [
    ["", "Never"],
    ["daily:1", "Every day"],
    ["weekdays:1", "Every weekday"],
    ["weekly:1", "Every week"],
    ["weekly:2", "Every 2 weeks"],
    ["monthly:1", "Every month"],
    ["yearly:1", "Every year"],
  ];

  const parse = (key) => key.split("-").map(Number);
  const format = (y, m, d) => `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
  const daysIn = (y, m) => new Date(Date.UTC(y, m, 0)).getUTCDate();
  function addDays(key, days) {
    const [y, m, d] = parse(key);
    const date = new Date(Date.UTC(y, m - 1, d + days));
    return format(date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate());
  }
  /** Months later, kept inside the month (January 31 + 1 month = February 28). */
  function addMonths(key, months) {
    const [y, m, d] = parse(key);
    const total = y * 12 + (m - 1) + months;
    const year = Math.floor(total / 12),
      month = (total % 12) + 1;
    return format(year, month, Math.min(d, daysIn(year, month)));
  }
  const weekday = (key) => {
    const [y, m, d] = parse(key);
    return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  };

  const valid = (repeat) => RULES.includes(repeat);
  const every = (task) => Math.max(1, Math.min(99, Math.floor(Number(task.repeatEvery) || 1)));

  /** One step of the rule from `key`. */
  function step(key, repeat, n) {
    if (repeat === "daily") return addDays(key, n);
    if (repeat === "weekly") return addDays(key, 7 * n);
    if (repeat === "monthly") return addMonths(key, n);
    if (repeat === "yearly") return addMonths(key, 12 * n);
    // Weekdays: the next Monday–Friday.
    let next = addDays(key, 1);
    while (weekday(next) === 0 || weekday(next) === 6) next = addDays(next, 1);
    return next;
  }

  /**
   * The next copy's days: `{ day, deadline }` for a task planned on `day` and/or due on `deadline`,
   * finished on `completedDay`. Both move by the same number of steps, until the copy lands after
   * `completedDay`. A task with neither is planned one step after the day it was finished.
   */
  function nextDays({ day = null, deadline = null, repeat, every: n = 1 }, completedDay) {
    if (!valid(repeat)) return null;
    n = Math.max(1, Math.floor(Number(n) || 1));
    const anchor = day || deadline || completedDay;
    let next = anchor,
      steps = 0;
    do {
      next = step(next, repeat, n);
      steps++;
    } while (next <= completedDay && steps < 5000);
    const move = (key) => {
      if (!key) return null;
      // Months are counted in one go, so skipping several months doesn't drift (31st → 28th → 28th…).
      if (repeat === "monthly") return addMonths(key, n * steps);
      if (repeat === "yearly") return addMonths(key, 12 * n * steps);
      let result = key;
      for (let i = 0; i < steps; i++) result = step(result, repeat, n);
      return result;
    };
    if (!day && !deadline) return { day: next, deadline: null };
    return { day: move(day), deadline: move(deadline) };
  }

  /** FNV-1a over a string with a seed, as an unsigned 32-bit number. */
  function fnv(text, seed) {
    let hash = seed >>> 0;
    for (let i = 0; i < text.length; i++) {
      hash ^= text.charCodeAt(i) & 0xff;
      hash = Math.imul(hash, 16777619) >>> 0;
    }
    return hash >>> 0;
  }
  /** The ID of the copy of task `id` planned (or due) on `day`: the same on every device. */
  function occurrenceID(id, day) {
    const text = `${String(id).toLowerCase()}|${day}`;
    const hex = [0, 1, 2, 3]
      .map((i) =>
        fnv(text, (2166136261 ^ Math.imul(i + 1, 0x9e3779b9)) >>> 0)
          .toString(16)
          .padStart(8, "0"),
      )
      .join("")
      .split("");
    hex[12] = "5";
    hex[16] = ((parseInt(hex[16], 16) & 3) | 8).toString(16);
    const s = hex.join("");
    return `${s.slice(0, 8)}-${s.slice(8, 12)}-${s.slice(12, 16)}-${s.slice(16, 20)}-${s.slice(20)}`;
  }

  /** "Every 2 weeks", or "" for a task that doesn't repeat. */
  function label(task) {
    if (!valid(task?.repeat)) return "";
    const n = every(task);
    if (task.repeat === "weekdays") return "Every weekday";
    const unit = { daily: "day", weekly: "week", monthly: "month", yearly: "year" }[task.repeat];
    return n === 1 ? `Every ${unit}` : `Every ${n} ${unit}s`;
  }
  /** The editor's value for a task ("weekly:2"), or "". */
  const choice = (task) => (valid(task?.repeat) ? `${task.repeat}:${every(task)}` : "");

  const api = { RULES, CHOICES, valid, every, nextDays, occurrenceID, label, choice, addMonths };
  if (typeof module === "object") module.exports = api;
  else root.OrbitRepeats = api;
})(typeof window === "object" ? window : globalThis);
