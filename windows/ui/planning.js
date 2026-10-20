const OrbitPlanning = (() => {
  const key = (d) =>
    `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  function parse(input, defaultDate = null, now = new Date()) {
    let title = input.trim(),
      date = defaultDate,
      hasTime = false,
      dueDate = null;
    const day = title.match(/\b(today|tomorrow)\b/i);
    if (day) {
      const d = new Date(now);
      d.setDate(d.getDate() + (day[0].toLowerCase() === "tomorrow" ? 1 : 0));
      date = key(d);
      title = title.replace(day[0], "");
    }
    const time = title.match(/\b(1[0-2]|0?[1-9])(?::([0-5][0-9]))?\s*(am|pm)\b/i);
    if (time) {
      const d = date ? new Date(date + "T12:00:00") : new Date(now);
      d.setHours((Number(time[1]) % 12) + (time[3].toLowerCase() === "pm" ? 12 : 0), Number(time[2] || 0), 0, 0);
      if (!day && !defaultDate && d < now) d.setDate(d.getDate() + 1);
      hasTime = true;
      date = key(d);
      dueDate = d.getTime();
      title = title.replace(time[0], "");
    }
    return { title: title.replace(/\s+/g, " ").trim(), localDate: date, hasTime, dueDate };
  }
  return { parse };
})();
if (typeof module !== "undefined") module.exports = OrbitPlanning;
