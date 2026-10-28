(function (root) {
  // Connected overlap groups share the same lane count, so timed blocks never hide one another.
  function place(tasks) {
    const items = tasks
      .map((task) => {
        const date = new Date(task.dueDate),
          start = date.getHours() * 60 + date.getMinutes();
        const duration = Math.max(5, task.durationMinutes || 30);
        return {
          task,
          start,
          end: Math.min(1440, start + duration),
          visualEnd: Math.min(1440, start + Math.max(19, duration)),
          lane: 0,
          lanes: 1,
        };
      })
      .filter((item) => Number.isFinite(item.start))
      .sort((a, b) => a.start - b.start || b.end - a.end);
    let group = [],
      laneEnds = [],
      end = -1;
    const finish = () => {
      group.forEach((item) => (item.lanes = laneEnds.length));
      group = [];
      laneEnds = [];
    };
    for (const item of items) {
      if (item.start >= end) finish();
      let lane = laneEnds.findIndex((last) => last <= item.start);
      if (lane < 0) lane = laneEnds.length;
      // A short event still needs a clickable 20px card. Keep adjacent short cards in separate lanes.
      laneEnds[lane] = item.visualEnd;
      item.lane = lane;
      group.push(item);
      end = Math.max(end, item.visualEnd);
    }
    finish();
    return items;
  }
  const api = { place };
  if (typeof module === "object") module.exports = api;
  else root.OrbitCalendarLayout = api;
})(typeof globalThis === "undefined" ? this : globalThis);
