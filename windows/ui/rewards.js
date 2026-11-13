/* global require */
(function (root) {
  // Milestone badges and accent unlocks (shared/rewards.json; iPhone: ios/Shared/Rewards.swift).
  // Everything is worked out from synced data, so both apps agree without storing anything extra.
  // rewards-data.js declares a script-level constant (not a window property) in the page.
  const data = typeof module === "object" ? require("./rewards-data.js") : OrbitRewardsData;

  /**
   * completions: finished tasks (not notes) plus habit check-ins; activeDays: days with either.
   * @param {{completedDay: string|null, isNote?: boolean}[]} tasks  each task's planner day of completion
   * @param {{dayKey: string, count: number}[]} logs  habit check-ins
   */
  function metrics(tasks, logs) {
    const days = new Set();
    let completions = 0;
    for (const task of tasks)
      if (task.completedDay && !task.isNote) {
        completions++;
        days.add(task.completedDay);
      }
    for (const log of logs)
      if (log.count > 0) {
        completions += log.count;
        days.add(log.dayKey);
      }
    return { completions, activeDays: days.size };
  }
  /** Badges reached, in their listed order. */
  const earned = (values) =>
    data.badges.filter((badge) => (values[badge.metric] || 0) >= badge.goal).map((badge) => badge.id);
  /** Accents open to choose: the free ones, then each unlocked by an earned badge. */
  function accents(earnedIDs) {
    const have = new Set(earnedIDs);
    return [...data.freeAccents, ...data.badges.filter((b) => b.unlocks && have.has(b.id)).map((b) => b.unlocks)];
  }
  /** The badge that unlocks an accent, or null for a free one. */
  const unlockedBy = (accent) => data.badges.find((badge) => badge.unlocks === accent) || null;
  /** Every badge with how far along it is. */
  const progress = (values) =>
    data.badges.map((badge) => ({
      ...badge,
      value: Math.min(values[badge.metric] || 0, badge.goal),
      done: (values[badge.metric] || 0) >= badge.goal,
    }));

  const api = { data, metrics, earned, accents, unlockedBy, progress };
  if (typeof module === "object") module.exports = api;
  else root.OrbitRewards = api;
})(typeof globalThis === "undefined" ? this : globalThis);
