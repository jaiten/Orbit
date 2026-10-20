(function (root) {
  function convert(entity, source, logs, today, now = Date.now()) {
    const { _key, conversionData, ...original } = source;
    const backup = conversionData ? JSON.parse(conversionData) : null;
    const target = entity === "tasks" ? "habits" : "tasks";
    let payload;
    if (entity === "tasks") {
      payload = backup?.source || {
        id: source.id,
        title: source.title,
        frequencyRule: source.recurrenceRule === "FREQ=WEEKLY" ? "WEEKLY" : "DAILY",
        target: 1,
        color: "clay",
        icon: "leaf",
        reminderMinutes: null,
        nudgeMinutes: null,
        createdAt: now,
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
      const key = (d) =>
        d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
      const end = new Date(start);
      end.setDate(end.getDate() + (source.frequencyRule === "WEEKLY" ? 7 : 1));
      payload.completedAt =
        history.filter((l) => l.dayKey >= key(start) && l.dayKey < key(end)).reduce((s, l) => s + l.count, 0) >=
        source.target
          ? now
          : null;
      for (const l of history)
        changes.push({ key: "habit_logs/" + source.id + "-" + l.dayKey, payload: l, deleted: true });
    } else {
      const restored = backup?.logs || [];
      for (const l of restored) changes.push({ key: "habit_logs/" + source.id + "-" + l.dayKey, payload: l });
      // Existing history is restored unchanged; a newly completed task starts one check-in.
      if (
        !backup &&
        source.completedAt &&
        new Date(source.completedAt).toLocaleDateString() === new Date(now).toLocaleDateString()
      ) {
        const l = { id: source.id, habitID: source.id, dayKey: today, count: 1, updatedAt: now };
        changes.push({ key: "habit_logs/" + source.id + "-" + today, payload: l });
      }
    }
    return changes;
  }
  if (typeof module === "object") module.exports = { convert };
  else root.OrbitConversions = { convert };
})(typeof window === "object" ? window : globalThis);
