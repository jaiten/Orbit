const { isDeepStrictEqual } = require("node:util");
const { sameContent } = require("./merge.cjs");
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function decodeBackup(data) {
  if (Buffer.byteLength(data) > 50000000) throw Error("Backup is too large");
  const b = JSON.parse(data);
  // Version 2 adds exportedAt and app; records are unchanged, so version 1 files still import.
  if (
    b.format !== "orbit-backup" ||
    ![1, 2].includes(b.version) ||
    !Array.isArray(b.records) ||
    b.records.length > 100000
  )
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
        (!p[entity === "lists" ? "name" : entity === "idea_prompts" ? "text" : "title"].trim() &&
          !(entity === "tasks" && p.isNote === true && (p.notes?.trim() || p.photos?.length)))
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
      (!Number.isInteger(p.target) ||
        p.target < 1 ||
        !["DAILY", "WEEKDAYS", "WEEKENDS", "WEEKLY"].includes(p.frequencyRule))
    )
      throw Error("Invalid habit goal");
  }
  return b.records.map(({ key, payload }) => ({ key, payload }));
}
/** The export format shared with iOS (PlannerBackup.swift): version 2, records sorted by key. */
function encodeBackup(rows, exportedAt = new Date()) {
  const records = rows
    .filter((r) => !r.deleted)
    .map(({ key, payload }) => ({ key, payload }))
    .sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
  return JSON.stringify(
    { format: "orbit-backup", version: 2, exportedAt: exportedAt.toISOString(), app: "Orbit", records },
    null,
    2,
  );
}

/**
 * Compares an import with what is here, by record key: new items are added, identical ones are
 * skipped, and items that differ are listed so they are only replaced when the user says so.
 */
function planImport(rows, records) {
  const current = new Map(rows.filter((r) => !r.deleted).map((r) => [r.key, r.payload]));
  const plan = { added: [], same: [], changed: [] };
  for (const record of records) {
    const mine = current.get(record.key);
    if (!mine) plan.added.push(record);
    else if (sameContent(mine, record.payload)) plan.same.push(record);
    else plan.changed.push(record);
  }
  return plan;
}

const localDay = (ms) => {
  const d = new Date(ms);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};
const csvField = (value) => {
  const text = String(value ?? "");
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
};
/** Tasks as CSV (same columns and order as iOS). Dates and times are local to this device. */
function encodeTasksCSV(rows, somedayID) {
  const live = rows.filter((r) => !r.deleted);
  const lists = new Map(live.filter((r) => r.key.startsWith("lists/")).map((r) => [r.payload.id, r.payload.name]));
  const tasks = live
    .filter((r) => r.key.startsWith("tasks/"))
    .map(({ payload: t }) => {
      const timed = t.hasTime && Number.isFinite(t.dueDate);
      const clock = timed ? new Date(t.dueDate) : null;
      return {
        id: t.id,
        title: t.title,
        list: t.listID === somedayID ? "Someday" : (lists.get(t.listID) ?? "Inbox"),
        date: timed ? localDay(t.dueDate) : t.localDate || "",
        time: clock
          ? `${String(clock.getHours()).padStart(2, "0")}:${String(clock.getMinutes()).padStart(2, "0")}`
          : "",
        minutes: timed ? t.durationMinutes : "",
        completed: t.completedAt ? localDay(t.completedAt) : "",
        notes: t.notes || "",
        tags: (t.tags || []).join("; "),
      };
    })
    .sort((a, b) =>
      (a.date || "9999") < (b.date || "9999")
        ? -1
        : (a.date || "9999") > (b.date || "9999")
          ? 1
          : a.time !== b.time
            ? a.time < b.time
              ? -1
              : 1
            : a.title !== b.title
              ? a.title < b.title
                ? -1
                : 1
              : a.id < b.id
                ? -1
                : 1,
    );
  const header = ["Title", "List", "Date", "Time", "Minutes", "Completed", "Notes", "Tags", "ID"];
  const lines = tasks.map((t) =>
    [t.title, t.list, t.date, t.time, t.minutes, t.completed, t.notes, t.tags, t.id].map(csvField).join(","),
  );
  return [header.join(","), ...lines].join("\r\n") + "\r\n";
}
/**
 * Which changes are worth an Undo: deleting something, or moving a task (to another list or day,
 * Later or Someday, or into a habit). Ticks, check-ins and edits are easy to redo by hand, so they
 * get none. Returns "deleted", "moved" or null. The iPhone app uses the same rule (UndoJournal.kind).
 */
function undoKind(before, after) {
  const keys = [...before.keys()];
  const removed = keys.filter((k) => before.get(k) && !after.get(k));
  const added = keys.filter((k) => !before.get(k) && after.get(k));
  if (removed.length) return added.some((k) => /^(tasks|habits)\//.test(k)) ? "moved" : "deleted";
  const moved = keys.some((k) => {
    const old = before.get(k),
      now = after.get(k);
    return (
      k.startsWith("tasks/") &&
      old &&
      now &&
      ["listID", "localDate", "dueDate"].some((field) => (old[field] ?? null) !== (now[field] ?? null))
    );
  });
  return moved ? "moved" : null;
}

class PlannerTools {
  constructor(store) {
    this.store = store;
    this.last = null;
  }
  /** Applies changes. Deletions and moves can be undone; `kind` forces one (imports are always undoable). */
  change(changes, kind = null) {
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
    if (!keys.length) return;
    const changed = {
      before: new Map(keys.map((k) => [k, before.get(k)])),
      after: new Map(keys.map((k) => [k, after.get(k)])),
    };
    const what = kind ?? undoKind(changed.before, changed.after);
    if (what) this.last = { ...changed, kind: what, created: Date.now() };
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
module.exports = { decodeBackup, encodeBackup, planImport, encodeTasksCSV, PlannerTools, undoKind };
