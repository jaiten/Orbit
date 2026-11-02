// What belongs on Today, and the moves between Today, Later and Someday.
// Shared with iOS (ios/Shared/TodayRules.swift); cases in shared/test-cases/today.json.
(function (root) {
  // The built-in Someday list has the same ID on every device, so creating it twice never conflicts.
  const SOMEDAY_LIST_ID = "00000000-0000-4000-8000-000000000001";

  /**
   * `item` is { day, completedDay, someday }: local calendar days ("YYYY-MM-DD") or null.
   * Today shows items dated today or earlier that are still open, plus anything finished today.
   * Another day shows open items dated that day and items completed that day.
   * Undated and Someday items never appear.
   */
  function onDay(item, day, today = day) {
    if (item.someday || !item.day) return false;
    if (item.completedDay) return item.completedDay === day;
    return day === today ? item.day <= day : item.day === day;
  }
  function isOverdue(item, today) {
    return !item.someday && !item.completedDay && !!item.day && item.day < today;
  }
  function somedayList(now = Date.now()) {
    return { id: SOMEDAY_LIST_ID, name: "Someday", color: "lavender", sortOrder: -1, updatedAt: now };
  }

  const localKey = (d) =>
    d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");

  // Day start: when a new planner day begins, synced as one preferences record. Minutes after
  // midnight, -60 (11 PM the evening before) to 240 (4 AM) in 30-minute steps; 2 AM by default.
  // Mirrors ios/Shared/DayStart.swift; cases in shared/test-cases/day-start.json.
  const PREFERENCES_ID = "00000000-0000-4000-8000-000000000002";
  const DAY_START_DEFAULT = 120;
  const DAY_START_CHOICES = Array.from({ length: 11 }, (_, i) => -60 + i * 30);
  const dayStartMinutes = (value) => (DAY_START_CHOICES.includes(value) ? value : DAY_START_DEFAULT);
  /** `time` moved back by the day start, so its calendar day is the planner day. */
  const plannerDate = (time, dayStart) => new Date(new Date(time).getTime() - dayStartMinutes(dayStart) * 60000);
  const plannerDayKey = (time, dayStart) => localKey(plannerDate(time, dayStart));
  function dayStartLabel(value) {
    const minutes = dayStartMinutes(value);
    if (minutes === 0) return "Midnight";
    const clock = (minutes + 1440) % 1440,
      hour = Math.floor(clock / 60);
    const text = `${hour % 12 || 12}:${String(clock % 60).padStart(2, "0")} ${hour < 12 ? "AM" : "PM"}`;
    return minutes < 0 ? text + " (the evening before)" : text;
  }
  /** Moves a task to `day`, keeping its time of day and reminder offsets. Someday items leave Someday. */
  function moveToDay(task, day, now = Date.now()) {
    let dueDate = null,
      reminders = task.reminders || [];
    if (task.hasTime && task.dueDate) {
      const old = new Date(task.dueDate),
        next = new Date(day + "T00:00:00");
      next.setHours(old.getHours(), old.getMinutes(), 0, 0);
      dueDate = next.getTime();
      reminders = reminders.map((r) => r + (dueDate - task.dueDate));
    }
    const listID = task.listID === SOMEDAY_LIST_ID ? null : task.listID;
    return { ...task, listID, localDate: day, dueDate, hasTime: !!dueDate, reminders, updatedAt: now };
  }
  /** Files a task in a category (or Someday) with no date or reminders, so it leaves Today. */
  function moveToList(task, listID, now = Date.now()) {
    return { ...task, listID, localDate: null, dueDate: null, hasTime: false, reminders: [], updatedAt: now };
  }
  /** Someday: no date, no reminders, never on Today. */
  function moveToSomeday(task, now = Date.now()) {
    return moveToList(task, SOMEDAY_LIST_ID, now);
  }
  /** "from Tue" within the last week, otherwise "from Oct 12". */
  function overdueLabel(day, today, locale) {
    const date = new Date(day + "T12:00:00"),
      now = new Date(today + "T12:00:00");
    const recent = (now - date) / 86400000 < 7;
    const text = date.toLocaleDateString(locale, recent ? { weekday: "short" } : { month: "short", day: "numeric" });
    return "from " + text;
  }

  function dateGroup(item, today) {
    if (item.completedDay) return "Completed";
    if (item.someday) return "Someday";
    if (!item.day) return "Someday";
    if (item.day === today) return "Today";
    return item.day < today ? "Overdue" : "Upcoming";
  }
  /**
   * The Tasks page groups, as on iPhone: Someday (the list, plus undated tasks with no category), then
   * dated tasks with no category by Overdue / Today / Upcoming, then each category in order, then
   * Completed. Entries are { day, completedDay, listID }; a list that is not a category (a note
   * section, or deleted) counts as no category, so nothing disappears.
   */
  function taskGroups(entries, categories, today) {
    const known = new Set(categories.map((c) => c.id));
    const uncategorized = (e) => !e.listID || (e.listID !== SOMEDAY_LIST_ID && !known.has(e.listID));
    const open = entries.filter((e) => !e.completedDay);
    const someday = (e) => e.listID === SOMEDAY_LIST_ID || (uncategorized(e) && !e.day);
    return [
      { id: "someday", name: "Someday", items: open.filter(someday) },
      ...["Overdue", "Today", "Upcoming"].map((name) => ({
        id: name.toLowerCase(),
        name,
        items: open.filter((e) => !someday(e) && uncategorized(e) && dateGroup({ day: e.day }, today) === name),
      })),
      ...categories.map((c) => ({ id: c.id, name: c.name, items: open.filter((e) => e.listID === c.id) })),
      { id: "completed", name: "Completed", items: entries.filter((e) => e.completedDay) },
    ].filter((group) => group.items.length);
  }
  // Category suggestions. Mirrors ios/Shared/CategorySuggestion.swift; cases in
  // shared/test-cases/category-suggestions.json.
  const STOP_WORDS = new Set(
    "the and for with from into about this that your our get make some more then than have need new week".split(" "),
  );
  function categoryWords(title) {
    const words = String(title ?? "")
      .toLowerCase()
      .match(/[\p{L}\p{N}]+/gu);
    return new Set(
      (words || [])
        .filter((w) => w.length >= 3 && !STOP_WORDS.has(w))
        .map((w) => (w.length > 3 && w.endsWith("s") ? w.slice(0, -1) : w)),
    );
  }
  /**
   * The category of earlier tasks with similar titles: each category scores the words its tasks share
   * with `title`; the top score wins unless it ties. `history` is [{ title, category }].
   */
  function suggestCategory(title, history) {
    const wanted = categoryWords(title);
    if (!wanted.size) return null;
    const scores = new Map();
    for (const item of history) {
      const shared = [...categoryWords(item.title)].filter((w) => wanted.has(w)).length;
      if (shared) scores.set(item.category, (scores.get(item.category) || 0) + shared);
    }
    const ranked = [...scores].sort((a, b) => b[1] - a[1]);
    return ranked.length && (ranked.length === 1 || ranked[0][1] > ranked[1][1]) ? ranked[0][0] : null;
  }
  function suggestsProgress(title) {
    const text =
      " " +
      title
        .toLowerCase()
        .split(/[^\p{L}\p{N}]+/u)
        .filter(Boolean)
        .join(" ") +
      " ";
    if (
      ["buy", "shop", "fold", "put away", "unload", "empty", "clean", "repair"].some((verb) =>
        text.startsWith(" " + verb + " "),
      )
    )
      return false;
    return [
      "laundry",
      "dishwasher",
      "washing machine",
      "wash clothes",
      "dry clothes",
      "bake",
      "baking",
      "roast",
      "roasting",
      "slow cook",
      "meal prep",
      "defrost",
      "marinate",
      "marinating",
      "charge car",
      "charge battery",
    ].some((phrase) => text.includes(" " + phrase + " "));
  }
  function setProgress(task, enabled, start = false, now = Date.now()) {
    return { ...task, progressTracking: enabled, startedAt: enabled && start ? now : null, updatedAt: now };
  }
  const api = {
    suggestsProgress,
    setProgress,
    dateGroup,
    taskGroups,
    suggestCategory,
    SOMEDAY_LIST_ID,
    onDay,
    isOverdue,
    somedayList,
    moveToDay,
    moveToList,
    moveToSomeday,
    overdueLabel,
    localKey,
    PREFERENCES_ID,
    DAY_START_DEFAULT,
    DAY_START_CHOICES,
    dayStartMinutes,
    plannerDate,
    plannerDayKey,
    dayStartLabel,
  };
  if (typeof module === "object") module.exports = api;
  else root.OrbitPlanner = api;
})(typeof window === "object" ? window : globalThis);
