(function (root) {
  const recordID = "00000000-0000-4000-8000-000000000004";
  const triggers = {
    event: "Calendar contains event",
    noEvent: "Calendar has no matching event",
    dates: "Date or date range",
    weeks: "Every few weeks",
    months: "Every few months",
  };
  const usesCalendar = (trigger) => trigger === "event" || trigger === "noEvent";
  const tags = (title) =>
    new Set(
      Array.from(title.toLowerCase().matchAll(/(?<![\p{L}\p{N}_@'-])@([\p{L}\p{N}_'-]+)/gu), (match) => match[1]),
    );
  const marker = /^[\p{L}\p{N}_'-]+$/u;
  const keyDate = (key) => {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) return null;
    const date = new Date(key + "T00:00:00Z");
    return Number.isFinite(+date) && date.toISOString().slice(0, 10) === key ? date : null;
  };
  function valid(rule) {
    if (typeof rule?.tag !== "string" || !marker.test(rule.tag) || rule.tag !== rule.tag.toLowerCase()) return false;
    if (usesCalendar(rule.trigger)) return !!rule.calendar && typeof rule.title === "string" && !!rule.title.trim();
    if (!keyDate(rule.start)) return false;
    if (rule.trigger === "dates") return !rule.end || (!!keyDate(rule.end) && rule.end >= rule.start);
    return (
      ["weeks", "months"].includes(rule.trigger) &&
      Number.isInteger(rule.interval) &&
      rule.interval >= 1 &&
      rule.interval <= 52
    );
  }
  function matches(rule, day, eventTitles) {
    if (!valid(rule)) return false;
    if (usesCalendar(rule.trigger)) {
      if (!eventTitles) return false;
      const found = eventTitles.some((title) => title.toLowerCase().includes(rule.title.trim().toLowerCase()));
      return rule.trigger === "event" ? found : !found;
    }
    if (day < rule.start) return false;
    if (rule.trigger === "dates") return day <= (rule.end || rule.start);
    const target = keyDate(day);
    if (!target) return false;
    const anchor = keyDate(rule.start);
    if (rule.trigger === "weeks") return (target - anchor) % (86400000 * 7 * rule.interval) === 0;
    const months =
      (target.getUTCFullYear() - anchor.getUTCFullYear()) * 12 + target.getUTCMonth() - anchor.getUTCMonth();
    return target.getUTCDate() === anchor.getUTCDate() && months % rule.interval === 0;
  }
  function onToday(task, day, active, plannerDay) {
    if (task.completedAt && plannerDay(task.completedAt) !== day) return false;
    return active.size > 0 && [...tags(task.title || "")].some((tag) => active.has(tag));
  }
  const api = { recordID, triggers, usesCalendar, tags, valid, matches, onToday };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.OrbitSomedayRules = api;
})(typeof window === "undefined" ? globalThis : window);
