// Shared renderer state and helpers. Loaded first; page scripts build on these globals.
// Accent colours live in tokens.css, generated from shared/design-tokens.json.
const accents = ["coral", "sage", "lavender", "honey"];
function applyAccent(name) {
  if (!accents.includes(name)) name = "coral";
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
const SOMEDAY = OrbitPlanner.SOMEDAY_LIST_ID;
const today = () => dayKey(new Date());
function planItem(t) {
  return {
    day: taskDate(t) || null,
    completedDay: t.completedAt ? dayKey(new Date(t.completedAt)) : null,
    someday: t.listID === SOMEDAY,
  };
}
/** Saves tasks, creating the built-in Someday list the first time something moves there. */
function saveTasks(tasks, extra = []) {
  const changes = tasks.map((t) => ({ key: t._key || "tasks/" + t.id, payload: clean(t) }));
  const needsSomeday = tasks.some((t) => t.listID === SOMEDAY);
  const hasSomeday = state.records.some((r) => r.key === "lists/" + SOMEDAY && !r.deleted);
  if (needsSomeday && !hasSomeday) changes.unshift({ key: "lists/" + SOMEDAY, payload: OrbitPlanner.somedayList() });
  return api.batch([...changes, ...extra]);
}
/** A small notice on Today when sync kept two versions of something; links to the review screen. */
function conflictBanner() {
  const count = state.records.filter((r) => r.conflict).length;
  if (!count) return "";
  const what = count === 1 ? "1 item has" : `${count} items have`;
  return `<button class="banner" data-review-conflicts>${what} two versions to review →</button>`;
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
let onboardingShown = false,
  contentSignature = "",
  pendingRender = false,
  loadSequence = 0;
function interacting() {
  return (
    !!document.querySelector("dialog[open]") ||
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
  // The sidebar shows the short form ("Saved locally"); the full message is in the tooltip and Account.
  $("#sync-text").textContent = status.split(" · ")[0];
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
  if (next.onboarded === false && !onboardingShown) {
    onboardingShown = true;
    showOnboarding();
  }
  if (notice) {
    page = "account";
    showNotice(notice);
    force = true;
  }
  if (!force && signature === contentSignature) return;
  if (document.querySelector("dialog[open]") || (!force && interacting())) {
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
  const count = `${progress(h, date)} of ${h.target} ${schedule === "WEEKLY" ? "this week" : "today"}`;
  return schedule === "DAILY" || schedule === "WEEKLY" ? count : `${OrbitHabits.label(h)} · ${count}`;
}

const pencil =
  '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m15 5 4 4M4 20l4-1L20 7a2.8 2.8 0 0 0-4-4L4 15z"/></svg>';
const plus = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>';
const HABIT_COLORS = ["sage", "lavender", "honey", "clay"];
const colorName = (c) => (HABIT_COLORS.includes(c) ? c : "sage");
/** Default colour for a new habit, so habits mix (OrbitHabits.nextColor); `extra` are colours about to be added. */
const nextHabitColor = (extra = []) =>
  OrbitHabits.nextColor([
    ...rows("habits")
      .sort((a, b) => (a.createdAt || 0) - (b.createdAt || 0))
      .map((h) => h.color),
    ...extra,
  ]);

// The item just completed or checked: its tick plays the completion animation once, on the next render.
let poppedID = null;
/** Round checkbox: a coral ring; done fills it and draws a white tick. */
function tick(done, pop = false) {
  return `<span class="tick ${done ? "done" : ""} ${pop && done ? "pop" : ""}" aria-hidden="true"><i></i><svg viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg></span>`;
}
/** Section heading with a tiny uppercase note on the right ("Time blocks"). */
function sectionLabel(title, note = "") {
  return `<div class="section-label"><h2>${title}</h2>${note ? `<span>${note}</span>` : ""}</div>`;
}
/** The quiet field that opens quick add. */
function addField(hint = "Add a task · gym tomorrow 6pm") {
  return `<button class="add-field" data-quick-add aria-label="Add a task" aria-keyshortcuts="Control+N">${plus}<span>${hint}</span><kbd aria-hidden="true">Ctrl+N</kbd></button>`;
}
/** "Your plan": the day's count and a bar that fills with a spring. */
function planCard(done, total) {
  return `<div class="card plan-card">
    <div class="eyebrow">Your plan</div>
    <div class="plan-count">${done} of ${total} done</div>
    <div class="plan-bar" role="progressbar" aria-label="Daily progress" aria-valuemin="0" aria-valuemax="${total}" aria-valuenow="${done}"><i data-fill="${total ? done / total : 0}"></i></div>
  </div>`;
}
/**
 * GitHub-style boxes: a column per week, a row per day, oldest first.
 * Opacity is set from data-o after render (the page's CSP blocks inline styles).
 */
function boxGrid(levels, color, label, weeks = 12) {
  const done = levels.filter((l) => l >= 1).length;
  const cells = levels
    .map((level) =>
      level < 0
        ? '<i class="future"></i>'
        : `<i data-o="${level <= 0 ? 0 : (0.3 + 0.7 * Math.min(1, level)).toFixed(2)}"></i>`,
    )
    .join("");
  return `<div class="box-grid fill-${color}" role="img" aria-label="${esc(label)}: ${done} of ${levels.length} days over the last ${weeks} weeks">${cells}</div>`;
}

function taskRow(t) {
  const time =
    t.hasTime && t.dueDate ? new Date(t.dueDate).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }) : "";
  const overdue = page === "today" && OrbitPlanner.isOverdue(planItem(t), today());
  const length = time && t.durationMinutes ? `${t.durationMinutes} min` : "";
  const detail = [overdue ? OrbitPlanner.overdueLabel(taskDate(t), today()) : "", time, length]
    .filter(Boolean)
    .join(" · ");
  const onToday = OrbitPlanner.onDay(planItem(t), today());
  const id = esc(t.id),
    title = esc(t.title);
  const addToToday =
    page === "lists" && !t.completedAt && !onToday
      ? `<button class="pill today-action" data-today="${id}">Add to Today</button>`
      : "";
  const moves = overdue
    ? `<div class="row-pills" role="group" aria-label="Move ${title}">
        <button class="pill" data-today="${id}">Today</button><button class="pill" data-later="${id}">Later</button><button class="pill" data-someday="${id}">Someday</button>
      </div>`
    : "";
  const search = [t.title, t.notes, ...(t.tags || [])].join(" ").toLowerCase();
  return `<div class="row task-row check-tile ${t.completedAt ? "complete" : ""} ${overdue ? "overdue" : ""}" data-flip="task-${id}" data-search="${esc(search)}">
    <div class="row-line">
      <button class="row-tick" role="checkbox" aria-label="${t.completedAt ? "Reopen" : "Complete"} ${title}" aria-checked="${!!t.completedAt}" data-toggle="${id}">${tick(!!t.completedAt, poppedID === t.id)}</button
      ><button class="row-body" aria-label="Edit ${title}" data-edit="${id}"><span class="row-title">${title}</span>${detail ? `<span class="row-detail">${detail}</span>` : ""}</button
      >${addToToday}
    </div>
    ${moves}
  </div>`;
}
/** A habit: colour dot, title and count. Tapping logs one check-in; right-click (or E) edits. */
function habitCard(h, { editable = false } = {}) {
  const done = checked(h);
  const id = esc(h.id),
    title = esc(h.title);
  return `<div class="row habit-row check-tile ${done ? "complete" : ""}" data-flip="habit-${id}">
    <div class="row-line">
      <button class="row-body" role="checkbox" aria-label="${done ? "Undo" : "Log"} ${title}" aria-checked="${done}" data-habit-toggle="${id}" data-habit-menu="${id}" ${selected > dayKey(new Date()) ? "disabled" : ""}
        ><span class="dot ${colorName(h.color)} ${poppedID === h.id && done ? "pop" : ""}" aria-hidden="true"></span
        ><span class="row-title">${title}</span><span class="row-detail ${done ? "met" : ""}">${habitDetail(h)}</span></button
      >${editable ? `<button class="row-edit" aria-label="Edit ${title}" data-habit-edit="${id}">${pencil}</button>` : ""}
    </div>
  </div>`;
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
  poppedID = t.completedAt ? null : t.id;
  await put("tasks", { ...t, completedAt: t.completedAt ? null : Date.now(), updatedAt: Date.now() });
}
async function log(id, undo) {
  const h = rows("habits").find((h) => h.id === id);
  if (selected > dayKey(new Date()) || !h) return;
  const old = rows("habit_logs").find((l) => l.habitID === id && l.dayKey === selected);
  if (!undo && checked(h)) return;
  const data = old || { id: crypto.randomUUID(), habitID: id, dayKey: selected, count: 0 };
  data.count = Math.max(0, data.count + (undo ? -1 : 1));
  poppedID = undo ? null : id;
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
  document.querySelectorAll("[data-habit-menu]").forEach(
    (b) =>
      (b.oncontextmenu = (e) => {
        e.preventDefault();
        openHabit(b.dataset.habitMenu);
      }),
  );
  document.querySelectorAll("[data-quick-add]").forEach((b) => (b.onclick = () => openQuickAdd()));
  // Choosing Today, Later or Someday springs the row away before the list re-forms.
  const move = (attribute, change) =>
    document.querySelectorAll(`[data-${attribute}]`).forEach(
      (b) =>
        (b.onclick = () =>
          action(async () => {
            const row = b.closest(".row");
            if (row && attribute !== "today") await leave(row);
            await saveTasks([change(rows("tasks").find((t) => t.id === b.getAttribute("data-" + attribute)))]);
          })),
    );
  move("today", (t) => OrbitPlanner.moveToDay(t, today()));
  move("later", (t) => OrbitPlanner.moveLater(t));
  move("someday", (t) => OrbitPlanner.moveToSomeday(t));
}
