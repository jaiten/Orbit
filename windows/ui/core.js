// Shared renderer state and helpers. Loaded first; page scripts build on these globals.
const accents = { coral: "#e8745e", sage: "#6e8c78", lavender: "#8c85bf", honey: "#bd8738" };
function applyAccent(name) {
  if (!accents[name]) name = "coral";
  document.documentElement.dataset.accent = name;
  localStorage.setItem("accent", name);
}
applyAccent(localStorage.getItem("accent") || "coral");

const visitDate = new Date().toLocaleDateString("en-CA");
if (localStorage.getItem("lastVisit") !== visitDate) {
  localStorage.setItem("lastVisit", visitDate);
  localStorage.setItem("visitDays", String(Number(localStorage.getItem("visitDays") || 0) + 1));
}

const api = window.orbit;
const $ = (s) => document.querySelector(s);
let state = { records: [] },
  page = "today",
  selected = dayKey(new Date()),
  editing = null,
  editingHabit = null,
  editingList = null,
  selectedList = null,
  accountEmail = "",
  resendAfter = 0,
  completedOpen = true,
  historyHabitID = null;

function dayKey(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
function localDay(key) {
  return new Date(key + "T12:00:00");
}
function esc(s) {
  return String(s ?? "").replace(
    /[&<>"']/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c],
  );
}
const rows = (entity) =>
  state.records.filter((r) => r.key.startsWith(entity + "/") && !r.deleted).map((r) => ({ ...r.payload, _key: r.key }));
function taskDate(t) {
  return t.hasTime && t.dueDate ? dayKey(new Date(t.dueDate)) : t.localDate;
}
function clean({ _key, ...payload }) {
  return payload;
}
function put(entity, data, deleted = false) {
  const { _key, ...payload } = data;
  return api.put(_key || `${entity}/${payload.id}`, payload, deleted);
}

function showNotice(message) {
  const notice = $("#notice"),
    text = document.createElement("span"),
    close = document.createElement("button");
  text.textContent = message;
  close.textContent = "×";
  close.setAttribute("aria-label", "Dismiss message");
  close.onclick = () => {
    notice.hidden = true;
  };
  notice.replaceChildren(text, close);
  notice.hidden = false;
}

let actionBusy = false;
async function action(fn) {
  if (actionBusy) return;
  actionBusy = true;
  try {
    await fn();
    await load(true);
  } catch (e) {
    showNotice(e.message);
  } finally {
    actionBusy = false;
  }
}

// Sync can deliver new records while a dialog or field is in use; defer the render until it is safe.
let contentSignature = "",
  pendingRender = false,
  loadSequence = 0;
function interacting() {
  return (
    !!document.querySelector("#quick-add input")?.value ||
    !!document.querySelector("dialog[open], .floating-add[open]") ||
    ["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement?.tagName)
  );
}
function updateSync(value) {
  const icon = $("#sync-status");
  const status = value.status || "Saved on this PC";
  icon.dataset.state = value.syncing
    ? "syncing"
    : /Saved locally|review/.test(status)
      ? "attention"
      : state.email
        ? "synced"
        : "local";
  if ($("#sync-details")) $("#sync-details").textContent = status;
  icon.title = status;
  icon.setAttribute("aria-label", "Sync: " + status);
}
async function load(force = false) {
  const sequence = ++loadSequence;
  const next = await api.read();
  if (sequence !== loadSequence) return;
  const signature = JSON.stringify({
    records: next.records.map((r) => ({ key: r.key, payload: r.payload, deleted: r.deleted, conflict: r.conflict })),
    email: next.email,
    configured: next.configured,
    recoveryReady: next.recoveryReady,
  });
  const notice = next.accountNotice;
  state = next;
  updateSync(next);
  updateUndo(next);
  if (notice) {
    page = "settings";
    showNotice(notice);
    force = true;
  }
  if (!force && signature === contentSignature) return;
  if (document.querySelector("dialog[open], .floating-add[open]") || (!force && interacting())) {
    pendingRender = true;
    return;
  }
  contentSignature = signature;
  pendingRender = false;
  render();
}
function flushPending() {
  if (pendingRender && !interacting()) void load(true);
}
document.addEventListener("toggle", flushPending, true);
document.addEventListener("close", flushPending, true);
document.addEventListener("focusout", () => setTimeout(flushPending, 0));

// Week start follows the system locale (Sunday or Monday), like iOS.
const weekStart = (() => {
  try {
    const locale = new Intl.Locale(navigator.language);
    const info = locale.getWeekInfo?.() ?? locale.weekInfo;
    return (info?.firstDay ?? 7) % 7;
  } catch {
    return 0;
  }
})();
const habitLogs = () => rows("habit_logs");
function dailyCount(h, date = selected) {
  return OrbitHabits.dayCount(h, habitLogs(), date);
}
function checked(h, date = selected) {
  return OrbitHabits.checkedOn(h, habitLogs(), date);
}
function progress(h, date = selected) {
  return OrbitHabits.periodProgress(h, habitLogs(), date, weekStart);
}
function dueOn(h, date = selected) {
  return OrbitHabits.dueOn(h, habitLogs(), date, weekStart);
}
function habitDetail(h, date = selected) {
  const schedule = OrbitHabits.schedule(h);
  const count = `${progress(h, date)} / ${h.target} ${schedule === "WEEKLY" ? "this week" : "today"}`;
  return schedule === "DAILY" || schedule === "WEEKLY" ? count : `${OrbitHabits.label(h)} · ${count}`;
}

const pencil =
  '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m15 5 4 4M4 20l4-1L20 7a2.8 2.8 0 0 0-4-4L4 15z"/></svg>';
const check = '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="m5 10 3.2 3.2L15 6.5"/></svg>';

function taskRow(t) {
  const time =
    t.hasTime && t.dueDate ? new Date(t.dueDate).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }) : "";
  const size = t.title.length <= 22 && !t.hasTime ? "short" : "long";
  return `<div class="task-row check-tile ${size} ${t.completedAt ? "complete" : ""}">
 <button class="tile-toggle" role="checkbox" aria-label="${t.completedAt ? "Reopen" : "Complete"} ${esc(t.title)}" aria-checked="${!!t.completedAt}" data-toggle="${esc(t.id)}"><span class="tick-symbol">${t.completedAt ? check : ""}</span><span class="tile-copy"><span>${esc(t.title)}</span>${time ? `<small>${time}</small>` : ""}</span></button>
 <button class="tile-edit" aria-label="Edit ${esc(t.title)}" data-edit="${esc(t.id)}">${pencil}</button>
 ${page === "lists" ? `<button class="today-action" data-today="${esc(t.id)}">Add to Today</button>` : ""}</div>`;
}
function habitCard(h) {
  const done = checked(h);
  return `<div class="habit-card check-tile ${h.title.length <= 22 ? "short" : "long"} ${done ? "complete" : ""}">
 <button class="tile-toggle" role="checkbox" aria-label="${done ? "Undo" : "Log"} ${esc(h.title)}" aria-checked="${done}" data-habit-toggle="${esc(h.id)}" ${selected > dayKey(new Date()) ? "disabled" : ""}><span class="tick-symbol">${done ? check : ""}</span><span class="tile-copy"><span>${esc(h.title)}</span><small>${habitDetail(h)}</small></span></button>
 <button class="tile-edit" aria-label="Edit ${esc(h.title)}" data-habit-edit="${esc(h.id)}">${pencil}</button></div>`;
}

function newTask(title, date) {
  return {
    id: crypto.randomUUID(),
    title,
    notes: "",
    listID: page === "lists" ? selectedList : null,
    dueDate: null,
    localDate: date,
    hasTime: false,
    durationMinutes: 30,
    reminders: [],
    recurrenceRule: "",
    priority: 0,
    tags: [],
    subtasks: [],
    completedAt: null,
    nextOccurrenceID: null,
    sortOrder: Date.now(),
    updatedAt: Date.now(),
  };
}
async function toggle(id) {
  const t = rows("tasks").find((t) => t.id === id);
  if (!t) return;
  await put("tasks", { ...t, completedAt: t.completedAt ? null : Date.now(), updatedAt: Date.now() });
}
async function log(id, undo) {
  const h = rows("habits").find((h) => h.id === id);
  if (selected > dayKey(new Date()) || !h) return;
  const old = rows("habit_logs").find((l) => l.habitID === id && l.dayKey === selected);
  if (!undo && checked(h)) return;
  const data = old || { id: crypto.randomUUID(), habitID: id, dayKey: selected, count: 0 };
  data.count = Math.max(0, data.count + (undo ? -1 : 1));
  data.updatedAt = Date.now();
  data._key = `habit_logs/${id}-${selected}`;
  await put("habit_logs", data);
}

// Shared tile handlers, used by every page that shows tasks or habits.
function bindTiles() {
  document.querySelectorAll("[data-edit]").forEach((b) => (b.onclick = () => openTask(b.dataset.edit)));
  document.querySelectorAll("[data-toggle]").forEach((b) => (b.onclick = () => action(() => toggle(b.dataset.toggle))));
  document
    .querySelectorAll("[data-habit-toggle]")
    .forEach(
      (b) =>
        (b.onclick = () =>
          action(() =>
            log(b.dataset.habitToggle, checked(rows("habits").find((h) => h.id === b.dataset.habitToggle))),
          )),
    );
  document.querySelectorAll("[data-habit-edit]").forEach((b) => (b.onclick = () => openHabit(b.dataset.habitEdit)));
  document.querySelectorAll("[data-today]").forEach(
    (b) =>
      (b.onclick = () =>
        action(() => {
          const t = rows("tasks").find((t) => t.id === b.dataset.today);
          return put("tasks", {
            ...t,
            localDate: dayKey(new Date()),
            dueDate: null,
            hasTime: false,
            updatedAt: Date.now(),
          });
        })),
  );
}
