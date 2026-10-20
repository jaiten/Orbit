const { isDeepStrictEqual } = require("node:util");
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function decodeBackup(data) {
  if (Buffer.byteLength(data) > 50000000) throw Error("Backup is too large");
  const b = JSON.parse(data);
  if (b.format !== "orbit-backup" || b.version !== 1 || !Array.isArray(b.records) || b.records.length > 100000)
    throw Error("Unsupported Orbit backup");
  const seen = new Set();
  for (const r of b.records) {
    const p = r.payload,
      entity = typeof r.key === "string" ? r.key.split("/")[0] : "";
    if (seen.has(r.key) || !p || typeof p !== "object" || !uuid.test(p.id) || JSON.stringify(p).length > 100000)
      throw Error("Invalid backup record");
    seen.add(r.key);
    if (entity === "habit_logs") {
      if (
        !uuid.test(p.habitID) ||
        !/^\d{4}-\d{2}-\d{2}$/.test(p.dayKey) ||
        r.key !== `habit_logs/${p.habitID.toLowerCase()}-${p.dayKey}` ||
        !Number.isInteger(p.count) ||
        p.count < 0
      )
        throw Error("Invalid habit history");
    } else {
      if (
        !["tasks", "habits", "lists", "idea_prompts"].includes(entity) ||
        r.key !== `${entity}/${p.id.toLowerCase()}` ||
        typeof p[entity === "lists" ? "name" : entity === "idea_prompts" ? "text" : "title"] !== "string" ||
        !p[entity === "lists" ? "name" : entity === "idea_prompts" ? "text" : "title"].trim()
      )
        throw Error("Invalid planner item");
    }
    for (const name of ["dueDate", "completedAt", "createdAt", "updatedAt", "shownAt"]) {
      if (p[name] !== undefined && p[name] !== null && !Number.isFinite(p[name])) throw Error("Invalid date");
    }
    if (
      entity === "tasks" &&
      (typeof p.notes !== "string" ||
        typeof p.hasTime !== "boolean" ||
        typeof p.recurrenceRule !== "string" ||
        !Array.isArray(p.reminders) ||
        !p.reminders.every(Number.isFinite) ||
        !Array.isArray(p.tags) ||
        !p.tags.every((t) => typeof t === "string") ||
        !Array.isArray(p.subtasks) ||
        !p.subtasks.every((s) => uuid.test(s.id) && typeof s.title === "string" && typeof s.completed === "boolean") ||
        !Number.isInteger(p.durationMinutes) ||
        p.durationMinutes < 5 ||
        p.durationMinutes > 1440 ||
        !Number.isInteger(p.priority) ||
        p.priority < 0 ||
        p.priority > 3)
    )
      throw Error("Invalid task details");
    if (
      entity === "habits" &&
      (!Number.isInteger(p.target) || p.target < 1 || !["DAILY", "WEEKLY"].includes(p.frequencyRule))
    )
      throw Error("Invalid habit goal");
  }
  return b.records.map(({ key, payload }) => ({ key, payload }));
}
function encodeBackup(rows) {
  return JSON.stringify(
    {
      format: "orbit-backup",
      version: 1,
      records: rows.filter((r) => !r.deleted).map(({ key, payload }) => ({ key, payload })),
    },
    null,
    2,
  );
}
class PlannerTools {
  constructor(store) {
    this.store = store;
    this.last = null;
  }
  change(changes) {
    const before = new Map(
      this.store
        .rows()
        .filter((r) => !r.deleted)
        .map((r) => [r.key, r.payload]),
    );
    this.store.batch(changes);
    const after = new Map(
      this.store
        .rows()
        .filter((r) => !r.deleted)
        .map((r) => [r.key, r.payload]),
    );
    const keys = [...new Set([...before.keys(), ...after.keys()])].filter(
      (k) => !isDeepStrictEqual(before.get(k), after.get(k)),
    );
    if (keys.length)
      this.last = {
        before: new Map(keys.map((k) => [k, before.get(k)])),
        after: new Map(keys.map((k) => [k, after.get(k)])),
        created: Date.now(),
      };
  }
  get available() {
    return !!this.last && Date.now() - this.last.created < 30000;
  }
  undo() {
    if (!this.available) throw Error("Undo has expired");
    const { before, after } = this.last;
    const current = new Map(
      this.store
        .rows()
        .filter((r) => !r.deleted)
        .map((r) => [r.key, r.payload]),
    );
    if ([...after].some(([k, p]) => !isDeepStrictEqual(current.get(k), p))) {
      this.last = null;
      throw Error("This item changed on another device. Undo was stopped to preserve those changes.");
    }
    this.store.batch(
      [...before].map(([key, p]) => ({
        key,
        payload: { ...(p || after.get(key)), updatedAt: Date.now() },
        deleted: !p,
      })),
    );
    this.last = null;
  }
}
module.exports = { decodeBackup, encodeBackup, PlannerTools };
