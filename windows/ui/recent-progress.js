/* global require */
(function (root) {
  const habitsAPI = typeof module === "object" ? require("./habits.js") : root.OrbitHabits;
  function day(tasks, habits, logs, key, includeTasks = true) {
    const active = habits.filter(
      (habit) => (!habit.createdDay || habit.createdDay <= key) && habitsAPI.scheduledOn(habit, key),
    );
    // A moved completion belongs to its completion day, never to two days.
    const items = includeTasks ? tasks.filter((task) => !task.isNote && (task.completedDay || task.day) === key) : [];
    const habitDone = active.reduce(
      (sum, habit) => sum + Math.min(1, habitsAPI.dayCount(habit, logs, key) / habitsAPI.dailyTarget(habit)),
      0,
    );
    const done = habitDone + items.filter((task) => task.completedDay && task.completedDay <= key).length;
    const total = active.length + items.length;
    return { ratio: total ? done / total : 0, total, done, taskCount: items.length, habitCount: active.length };
  }
  const api = { day };
  if (typeof module === "object") module.exports = api;
  else root.OrbitRecentProgress = api;
})(typeof globalThis === "undefined" ? this : globalThis);
