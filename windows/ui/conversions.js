(function (root) {
  // Repeating tasks from earlier versions map onto habit schedules. Anything else becomes a one-off task.
  const SCHEDULE_FOR_RULE = {
    "FREQ=DAILY": "DAILY",
    "FREQ=WEEKLY": "WEEKLY",
    "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR": "WEEKDAYS",
    "FREQ=WEEKLY;BYDAY=SA,SU": "WEEKENDS",
  };
  const localKey = (d) =>
    d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");

  function convert(entity, source, logs, today, now = Date.now(), options = {}) {
    const { _key, conversionData, ...original } = source;
    const backup = conversionData ? JSON.parse(conversionData) : null;
    const target = entity === "tasks" ? "habits" : "tasks";
    let payload;
    if (entity === "tasks") {
      const reminder = source.reminders?.length ? new Date(source.reminders[0]) : null;
      payload = backup?.source || {
        id: source.id,
        title: source.title,
        frequencyRule: SCHEDULE_FOR_RULE[source.recurrenceRule] || "DAILY",
        target: 1,
        color: "sage",
        icon: "leaf",
        reminderMinutes: reminder ? reminder.getHours() * 60 + reminder.getMinutes() : null,
        nudgeMinutes: null,
        createdAt: options.createdAt ?? now,
      };
    } else {
      payload = backup?.source || {
        id: source.id,
        title: source.title,
        notes: "",
        listID: null,
        dueDate: null,
        localDate: today,
        hasTime: false,
        durationMinutes: 30,
        reminders: [],
        recurrenceRule: "",
        priority: 0,
        tags: [],
        subtasks: [],
        completedAt: null,
        nextOccurrenceID: null,
        sortOrder: now,
      };
      // Only habits repeat. A restored task is always one-off.
      payload = { ...payload, recurrenceRule: "", nextOccurrenceID: null };
    }
    const history = logs.filter((l) => l.habitID === source.id).map(({ _key, ...l }) => l);
    const data = { source: original };
    if (entity === "habits") data.logs = history;
    payload = { ...payload, title: source.title, updatedAt: now, conversionData: JSON.stringify(data) };
    const changes = [
      { key: target + "/" + source.id, payload },
      { key: entity + "/" + source.id, payload: original, deleted: true },
    ];
    if (entity === "habits") {
      const start = new Date(today + "T12:00:00");
      if (source.frequencyRule === "WEEKLY") start.setDate(start.getDate() - start.getDay());
      const end = new Date(start);
      end.setDate(end.getDate() + (source.frequencyRule === "WEEKLY" ? 7 : 1));
      const done = history
        .filter((l) => l.dayKey >= localKey(start) && l.dayKey < localKey(end))
        .reduce((s, l) => s + l.count, 0);
      payload.completedAt = done >= source.target ? now : null;
      for (const l of history)
        changes.push({ key: "habit_logs/" + source.id + "-" + l.dayKey, payload: l, deleted: true });
    } else {
      const restored = backup?.logs || [];
      for (const l of restored) changes.push({ key: "habit_logs/" + source.id + "-" + l.dayKey, payload: l });
      // Existing history is restored unchanged; a newly completed task starts one check-in.
      if (!backup && source.completedAt && localKey(new Date(source.completedAt)) === localKey(new Date(now))) {
        const l = { id: source.id, habitID: source.id, dayKey: today, count: 1, updatedAt: now };
        changes.push({ key: "habit_logs/" + source.id + "-" + today, payload: l });
      }
    }
    return changes;
  }

  /**
   * Turns each open repeating task into a habit with the same ID. Earlier completed occurrences
   * become check-ins (their task records stay as they are). The output depends only on the
   * records, so two devices migrating the same data produce matching payloads.
   */
  function migrateRecurring(tasks, logs, now = Date.now()) {
    const changes = [];
    const previous = new Map(tasks.filter((t) => t.nextOccurrenceID).map((t) => [t.nextOccurrenceID, t]));
    const existingLogs = new Set(logs.map((l) => l.habitID + "-" + l.dayKey));
    for (const task of tasks) {
      if (!task.recurrenceRule || task.nextOccurrenceID || task.completedAt) continue;
      if (!SCHEDULE_FOR_RULE[task.recurrenceRule]) {
        // Monthly and custom rules have no habit equivalent; keep the task once, on its date.
        const { _key, ...payload } = task;
        changes.push({ key: _key || "tasks/" + task.id, payload: { ...payload, recurrenceRule: "", updatedAt: now } });
        continue;
      }
      const days = new Set();
      const checkIns = [];
      for (let earlier = previous.get(task.id), guard = 0; earlier && guard < 10000; guard++) {
        if (earlier.completedAt) {
          const day = localKey(new Date(earlier.completedAt));
          if (!days.has(day) && !existingLogs.has(task.id + "-" + day)) {
            days.add(day);
            checkIns.push({ id: earlier.id, habitID: task.id, dayKey: day, count: 1, updatedAt: now });
          }
        }
        earlier = previous.get(earlier.id);
      }
      const firstDay = [...days, task.localDate].filter(Boolean).sort()[0];
      const createdAt = firstDay ? new Date(firstDay + "T00:00:00").getTime() : now;
      changes.push(...convert("tasks", task, [], localKey(new Date(now)), now, { createdAt }));
      for (const l of checkIns) changes.push({ key: "habit_logs/" + task.id + "-" + l.dayKey, payload: l });
    }
    return changes;
  }

  const api = { convert, migrateRecurring, SCHEDULE_FOR_RULE };
  if (typeof module === "object") module.exports = api;
  else root.OrbitConversions = api;
})(typeof window === "object" ? window : globalThis);
