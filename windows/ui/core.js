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
  completedOpen = localStorage.getItem("todayCompletedExpanded") !== "false",
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
  return `<button class="banner" data-review-conflicts>${what} two versions to review</button>`;
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

function openDialog(dialog) {
  document.querySelectorAll("dialog[open]").forEach((open) => {
    if (open !== dialog) open.close();
  });
  if (!dialog.open) dialog.showModal();
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
  loadSequence = 0,
  renderRevision = 0;
let pointerBusy = false;
document.addEventListener(
  "pointerdown",
  () => {
    pointerBusy = true;
  },
  true,
);
const endPointer = () =>
  setTimeout(() => {
    pointerBusy = false;
    flushPending();
  }, 0);
document.addEventListener("pointerup", endPointer, true);
document.addEventListener("pointercancel", endPointer, true);
window.addEventListener("blur", endPointer);
function interacting() {
  return (
    pointerBusy ||
    !!document.querySelector("dialog[open], details.mac-picker[open], #row-menu:not([hidden])") ||
    ["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement?.tagName)
  );
}
let pendingSyncStatus = null;
let syncStatusTimer;
function updateSync(value) {
  pendingSyncStatus = value;
  clearTimeout(syncStatusTimer);
  // Let a short sync cycle finish before changing the visible status. Keep typing quiet.
  syncStatusTimer = setTimeout(flushSyncStatus, value.syncing ? 1200 : 350);
}
function flushSyncStatus() {
  if (!pendingSyncStatus) return;
  if (
    page === "note" ||
    document.querySelector("dialog[open]") ||
    ["INPUT", "TEXTAREA"].includes(document.activeElement?.tagName)
  )
    return;
  const value = pendingSyncStatus;
  pendingSyncStatus = null;
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
  $("#sync-text").textContent = value.syncing
    ? "Syncing…"
    : status === "All changes synced"
      ? "Synced"
      : status.split(" · ")[0];
  icon.title = status;
  icon.setAttribute("aria-label", "Sync: " + status);
}
document.addEventListener("focusout", () => setTimeout(flushSyncStatus, 400));
document.addEventListener("close", () => setTimeout(flushSyncStatus, 400), true);
async function load(force = false) {
  const sequence = ++loadSequence;
  const revision = renderRevision;
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
  if (!force && signature === contentSignature) {
    pendingRender = false;
    return;
  }
  if (
    document.querySelector("dialog[open]") ||
    revision !== renderRevision ||
    ((!force || page === "note") && interacting())
  ) {
    pendingRender = true;
    setTimeout(flushPending, 0);
    return;
  }
  contentSignature = signature;
  pendingRender = false;
  render();
}
function flushPending() {
  if (pendingRender && !interacting()) void load();
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
/**
 * Inline task entry: Return saves, then the field is ready for the next item; Return on an empty field
 * leaves it. The field grows as you type, and long text (OrbitNotes) becomes a note.
 */
function addField(placeholder = "Add a task · gym tomorrow 6pm") {
  return `<form id="inline-add-form" class="inline-capture">
    <div class="add-field"><textarea id="inline-task-input" aria-label="New task" placeholder="${esc(placeholder)}" maxlength="5000" autocomplete="off" spellcheck="true" rows="1">${esc(inlineDraft)}</textarea>
      <span class="capture-tools">
        <button type="button" class="icon-button" id="inline-dictate" aria-label="Dictate task" title="Voice typing (Win+H)"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg></button
        ><button type="button" class="icon-button" data-quick-add aria-label="Task options" title="Date, time and section"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="5" width="18" height="16" rx="3"/><path d="M7 3v4m10-4v4M3 10h18"/></svg></button
        ><button type="submit" class="icon-button capture-submit" aria-label="Add a task" title="Add (Enter)"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 19V5M5 12l7-7 7 7"/></svg></button>
      </span>
    </div><div class="chip-row inline-chip" aria-live="polite"><p id="inline-preview" class="chip" hidden></p></div>
    <div id="inline-overlap" hidden><p id="inline-overlap-text"></p><button type="button" id="inline-save-overlap">Add anyway</button></div>
    <p id="inline-receipt" class="secondary" role="status"></p>
  </form>`;
}
/** "Your plan": the day's count and a bar that fills with a spring. */
function planCard(done, total) {
  return `<div class="card plan-card">
    <div class="eyebrow">Your plan</div>
    <div class="plan-count">${total ? `${done} of ${total} done` : "A clear day"}</div>
    <div class="plan-bar" role="progressbar" aria-label="Daily progress" aria-valuemin="0" aria-valuemax="${total}" aria-valuenow="${done}"><i data-fill="${total ? done / total : 0}"></i></div>
  </div>`;
}
/**
 * Habit boxes, oldest first. History pages arrange these in calendar order; compact Today grids
 * keep the wider layout so they do not become excessively tall.
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

function rowActions(id, title, habit = false) {
  return `<span class="row-actions"><button class="icon-button" ${habit ? "data-habit-edit" : "data-edit"}="${id}" aria-label="Edit ${habit ? "habit" : "task"}: ${title}" title="Edit (E)"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m16 3 5 5-12 12-6 1 1-6zM14 5l5 5"/></svg></button><button class="icon-button danger" data-delete-row="${id}" aria-label="Delete ${title}" title="Delete"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 6h18M8 6V3h8v3M5 6l1 15h12l1-15M10 10v7M14 10v7"/></svg></button></span>`;
}
function taskRow(t) {
  const time =
    t.hasTime && t.dueDate ? new Date(t.dueDate).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }) : "";
  const overdue = page === "today" && OrbitPlanner.isOverdue(planItem(t), today());
  const length = time && t.durationMinutes ? `${t.durationMinutes} min` : "";
  const timing = focusTimer?.taskID === t.id;
  const status =
    !t.completedAt && t.progressTracking
      ? t.startedAt
        ? timing
          ? "Timer running"
          : "In progress"
        : "Ready to start"
      : "";
  const detail = [status, overdue ? OrbitPlanner.overdueLabel(taskDate(t), today()) : "", time, length]
    .filter(Boolean)
    .join(" · ");
  const onToday = OrbitPlanner.onDay(planItem(t), today());
  const id = esc(t.id),
    title = esc(t.title);
  const addToToday =
    page === "tasks" && !t.completedAt && !onToday
      ? `<button class="pill today-action" data-today="${id}">Add to Today</button>`
      : "";
  const moves = overdue
    ? `<div class="row-pills" role="group" aria-label="Move ${title}">
        <button class="pill" data-today="${id}">Today</button><button class="pill" data-later="${id}">Later</button><button class="pill" data-someday="${id}">Someday</button>
      </div>`
    : "";
  const tracking = !t.completedAt && t.progressTracking === true;
  const started = tracking && !!t.startedAt;
  const controlLabel = t.completedAt ? "Reopen" : tracking ? (started ? "Finish" : "Start") : "Complete";
  const control = tracking
    ? `<span class="progress-tick ${started ? "started" : ""} ${started && poppedID === t.id ? "pop" : ""}" aria-hidden="true"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/><circle class="progress-arc" cx="12" cy="12" r="10"/>${started ? '<path d="M7 12l3 3 7-7"/>' : '<path class="play" d="M10 7l7 5-7 5z"/>'}</svg></span>`
    : tick(!!t.completedAt, poppedID === t.id);
  const options =
    !t.completedAt && (tracking || (t.progressTracking == null && OrbitPlanner.suggestsProgress(t.title)))
      ? `<details class="progress-options"><summary aria-label="Progress options for ${title}" title="Progress options">${tracking ? "⋯" : "✦"}</summary><div>${
          tracking
            ? `${started ? `<button data-progress="${id}" data-progress-action="reset">Reset progress</button>` : ""}<button data-progress="${id}" data-progress-action="dismiss">Turn off start &amp; finish</button>`
            : `<button data-progress="${id}" data-progress-action="enable">Track start &amp; finish</button><button data-progress="${id}" data-progress-action="dismiss">No thanks</button>`
        }</div></details>`
      : "";
  // In progress: a timer is one click away (on hover, and suggested right after starting).
  const minutes = Math.min(240, Math.max(5, t.durationMinutes || 30));
  const timer =
    started && !timing
      ? `<button class="timer-action ${poppedID === t.id ? "suggested" : ""}" data-start-timer="${id}" aria-label="Start a ${minutes}-minute timer for ${title}" title="Start a ${minutes}-minute timer"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="14" r="8"/><path d="M9 2h6M12 6V2M12 10v4l2 2"/></svg> ${minutes} min</button>`
      : "";
  const search = [t.title, t.notes, ...(t.tags || [])].join(" ").toLowerCase();
  return `<div class="row task-row check-tile ${t.completedAt ? "complete" : ""} ${overdue ? "overdue" : ""} ${started ? "in-progress" : ""}" data-flip="task-${id}" data-search="${esc(search)}" data-row-menu="task:${id}">
    <div class="row-line">
      <button class="row-tick" role="checkbox" aria-label="${controlLabel} ${title}" aria-checked="${!!t.completedAt}" data-toggle="${id}">${control}</button
      ><button class="row-body" aria-label="Edit ${title}" data-edit="${id}"><span class="row-title">${title}</span>${detail ? `<span class="row-detail">${detail}</span>` : ""}</button
      >${timer}${addToToday}${rowActions(id, title)}${options}
    </div>
    ${moves}
  </div>`;
}
/** A habit: colour dot, title and count. Tapping logs one check-in; right-click (or E) edits. */
function habitCard(h, { editable = false } = {}) {
  const done = checked(h);
  const id = esc(h.id),
    title = esc(h.title);
  return `<div class="row habit-row check-tile ${done ? "complete" : ""}" data-flip="habit-${id}" data-row-menu="habit:${id}">
    <div class="row-line">
      <button class="row-tick" role="checkbox" aria-label="${done ? "Undo" : "Log"} ${title}" aria-checked="${done}" data-habit-toggle="${id}" data-habit-menu="${id}" ${selected > today() ? "disabled" : ""}>${tick(done, poppedID === h.id)}</button>
      <button class="row-body" aria-label="Edit ${title}" data-habit-edit="${id}"><span class="row-title">${title}</span>${editable ? `<span class="dot ${colorName(h.color)}" aria-hidden="true"></span>` : ""}<span class="row-detail ${done ? "met" : ""}">${habitDetail(h)}</span></button>
      ${rowActions(id, title, true)}
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
  if (!t.completedAt && t.progressTracking === true && !t.startedAt) {
    poppedID = t.id;
    await put("tasks", OrbitPlanner.setProgress(t, true, true));
    return;
  }
  poppedID = t.completedAt ? null : t.id;
  if (!t.completedAt && focusTimer?.taskID === t.id) stopTimer();
  await put("tasks", {
    ...t,
    startedAt: t.completedAt ? null : t.startedAt,
    completedAt: t.completedAt ? null : Date.now(),
    updatedAt: Date.now(),
  });
}
async function log(id, undo, date = selected) {
  const h = rows("habits").find((h) => h.id === id);
  const current = dayKey(new Date());
  if (date > current || date < OrbitHabits.addDays(current, -1) || !h) return;
  const old = rows("habit_logs").find((l) => l.habitID === id && l.dayKey === date);
  if (!undo && checked(h, date)) return;
  const data = old || { id: crypto.randomUUID(), habitID: id, dayKey: date, count: 0 };
  data.count = Math.max(0, data.count + (undo ? -1 : 1));
  poppedID = undo ? null : id;
  data.updatedAt = Date.now();
  data._key = `habit_logs/${id}-${date}`;
  await put("habit_logs", data);
}
async function backfillYesterday(id) {
  const h = rows("habits").find((habit) => habit.id === id);
  if (!h) return;
  const date = OrbitHabits.addDays(today(), -1);
  const old = rows("habit_logs").find((item) => item.habitID === id && item.dayKey === date);
  const data = old || { id: crypto.randomUUID(), habitID: id, dayKey: date, count: 0 };
  data.count = Math.max(data.count, OrbitHabits.dailyTarget(h));
  data.updatedAt = Date.now();
  data._key = `habit_logs/${id}-${date}`;
  await put("habit_logs", data);
}

// Shared tile handlers, used by every page that shows tasks or habits.
function bindTiles() {
  document.querySelectorAll("[data-delete-row]").forEach((button) => {
    button.onclick = () => void action(() => deleteItem(button.closest(".check-tile")));
  });
  document.querySelectorAll(".progress-options").forEach((menu) => {
    menu.onkeydown = (event) => {
      if (event.key === "Escape") {
        event.stopPropagation();
        menu.open = false;
        menu.querySelector("summary").focus();
      }
    };
    menu.onfocusout = (event) => {
      if (!menu.contains(event.relatedTarget)) menu.open = false;
    };
  });
  document.querySelectorAll("[data-progress]").forEach(
    (b) =>
      (b.onclick = () =>
        action(async () => {
          const t = rows("tasks").find((item) => item.id === b.dataset.progress);
          if (!t || t.completedAt) return;
          const kind = b.dataset.progressAction;
          if (kind === "finish") await toggle(t.id);
          else await put("tasks", OrbitPlanner.setProgress(t, kind !== "dismiss", kind === "start"));
        })),
  );
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
  document.querySelectorAll("[data-new-habit]").forEach((b) => (b.onclick = () => openHabit(null)));
  document.querySelectorAll("[data-start-timer]").forEach((b) => (b.onclick = () => startTimer(b.dataset.startTimer)));
  if ($("[data-stop-timer]")) $("[data-stop-timer]").onclick = () => stopTimer();
  document.querySelectorAll("[data-row-menu], [data-note-menu]").forEach((row) => (row.oncontextmenu = openRowMenu));
  document.querySelectorAll("[data-quick-add]").forEach((b) => (b.onclick = () => openQuickAdd()));
  bindInlineCapture();
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

// Focus timer: one at a time, kept across restarts. Finishing shows a Windows notification.
let focusTimer = JSON.parse(localStorage.getItem("focusTimer") || "null");
function saveTimer() {
  if (focusTimer) localStorage.setItem("focusTimer", JSON.stringify(focusTimer));
  else localStorage.removeItem("focusTimer");
}
function startTimer(id) {
  const t = rows("tasks").find((task) => task.id === id);
  if (!t) return;
  const minutes = Math.min(240, Math.max(5, t.durationMinutes || 30));
  focusTimer = { taskID: t.id, title: t.title, startedAt: Date.now(), endsAt: Date.now() + minutes * 60000 };
  saveTimer();
  render();
}
function stopTimer() {
  focusTimer = null;
  saveTimer();
  render();
}
const timeLeft = (ms) => {
  const total = Math.max(0, Math.ceil(ms / 1000));
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
};
function focusBanner() {
  if (!focusTimer) return "";
  const left = focusTimer.endsAt - Date.now();
  return `<div class="focus-banner" role="timer" aria-label="Focus timer for ${esc(focusTimer.title)}">
    <svg class="ui-icon focus-glyph" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="14" r="8"/><path d="M9 2h6M12 6V2M12 10v4l2 2"/></svg><span class="focus-title">${esc(focusTimer.title)}</span>
    <span id="focus-left" class="focus-left">${left > 0 ? timeLeft(left) : "Finished"}</span>
    <button class="pill" data-stop-timer>${left > 0 ? "Stop" : "Done"}</button>
  </div>`;
}
setInterval(() => {
  if (!focusTimer) return;
  const left = focusTimer.endsAt - Date.now();
  if (left <= 0 && !focusTimer.notified) {
    focusTimer.notified = true;
    saveTimer();
    void api.timerDone?.(focusTimer.title).catch(() => {});
    if (!interacting()) render();
  }
  if ($("#focus-left")) $("#focus-left").textContent = left > 0 ? timeLeft(left) : "Finished";
}, 1000);

let rowMenuScrollPosition = null;
/** Right-click (or the Menu key) on a row: copy its text and other quick actions. */
function openRowMenu(e) {
  e.preventDefault();
  const [kind, id] = (e.currentTarget.dataset.rowMenu || "note:" + e.currentTarget.dataset.noteMenu).split(":");
  const item = rows(kind === "habit" ? "habits" : "tasks").find((r) => r.id === id);
  if (!item) return;
  const text = [item.title, item.notes?.trim()].filter(Boolean).join("\n\n");
  const entries = [["Copy text", () => api.copy(text)]];
  if (kind !== "habit") entries.push(["Select item", () => selectRow(kind, id)]);
  if (kind === "habit") entries.push(["Edit…", () => openHabit(id)]);
  if (kind === "note") entries.push(["Open", () => openNote(id)]);
  if (kind === "task") {
    entries.push(["Edit…", () => openTask(id)]);
    if (!item.completedAt && item.progressTracking === true && item.startedAt)
      entries.push(
        focusTimer?.taskID === id ? ["Stop timer", () => stopTimer()] : ["Start timer", () => startTimer(id)],
      );
    entries.push([
      "Make it a Note",
      () =>
        action(() =>
          put("tasks", {
            ...item,
            isNote: true,
            localDate: null,
            dueDate: null,
            hasTime: false,
            reminders: [],
            progressTracking: null,
            startedAt: null,
            updatedAt: Date.now(),
          }),
        ),
    ]);
  }
  let menu = $("#row-menu");
  if (!menu) {
    menu = document.createElement("div");
    menu.id = "row-menu";
    menu.className = "row-menu";
    menu.setAttribute("role", "menu");
    document.body.append(menu);
  }
  menu.replaceChildren(
    ...entries.map(([label, run]) => {
      const button = document.createElement("button");
      button.setAttribute("role", "menuitem");
      button.textContent = label;
      button.onclick = () => {
        closeRowMenu();
        void Promise.resolve(run()).catch((error) => showNotice(error.message));
      };
      return button;
    }),
  );
  const box = e.currentTarget.getBoundingClientRect();
  const x = e.clientX || box.left + 24,
    y = e.clientY || box.bottom;
  menu.hidden = false;
  menu.style.left = Math.min(x, window.innerWidth - menu.offsetWidth - 8) + "px";
  menu.style.top = Math.min(y, window.innerHeight - menu.offsetHeight - 8) + "px";
  menu.querySelector("button").focus({ preventScroll: true });
  rowMenuScrollPosition = { x: scrollX, y: scrollY };
}
function closeRowMenu() {
  if ($("#row-menu")) $("#row-menu").hidden = true;
}
document.addEventListener("click", (e) => {
  if (!e.target.closest?.("#row-menu")) closeRowMenu();
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && $("#row-menu") && !$("#row-menu").hidden) {
    e.stopPropagation();
    closeRowMenu();
  }
});
window.addEventListener("blur", closeRowMenu);
document.addEventListener(
  "scroll",
  (event) => {
    // A layout change can queue a scroll event before the menu opens. Dismiss only
    // when the document actually moves from its position at opening.
    if (event.target === document && rowMenuScrollPosition?.x === scrollX && rowMenuScrollPosition?.y === scrollY)
      return;
    closeRowMenu();
  },
  true,
);
