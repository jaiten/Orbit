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
  /** Later: no date, so it waits in its list until it is added to Today again. */
  function moveLater(task, now = Date.now()) {
    return { ...task, localDate: null, dueDate: null, hasTime: false, reminders: [], updatedAt: now };
  }
  /** Someday: no date, no reminders, never on Today. */
  function moveToSomeday(task, now = Date.now()) {
    return { ...moveLater(task, now), listID: SOMEDAY_LIST_ID };
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
    SOMEDAY_LIST_ID,
    onDay,
    isOverdue,
    somedayList,
    moveToDay,
    moveLater,
    moveToSomeday,
    overdueLabel,
    localKey,
  };
  if (typeof module === "object") module.exports = api;
  else root.OrbitPlanner = api;
})(typeof window === "object" ? window : globalThis);
