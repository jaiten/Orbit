// Page routing and start-up. Pages live in ui/pages; shared helpers in core.js, motion in motion.js.
let shownView = null;
function render() {
  // Keep keyboard focus on the same item across re-renders (Space/Enter toggles it repeatedly).
  const focused = document.activeElement?.closest?.("[data-toggle], [data-habit-toggle]");
  const focusSelector = focused?.dataset.toggle
    ? `[data-toggle="${focused.dataset.toggle}"]`
    : focused?.dataset.habitToggle
      ? `[data-habit-toggle="${focused.dataset.habitToggle}"]`
      : null;
  // Account and Review are reached from Settings and Today, History from Habits; their parent stays highlighted.
  const navPage = ["account", "review"].includes(page)
    ? "settings"
    : ["history", "habit-history"].includes(page)
      ? "habits"
      : page === "note"
        ? "lists"
        : page;
  document.querySelectorAll("[data-page]").forEach((b) => b.classList.toggle("selected", b.dataset.page === navPage));
  // Notes are task records too, but never to-dos: only the Notes page shows them.
  const tasks = rows("tasks")
    .filter((t) => !t.isNote)
    .sort((a, b) => (a.sortOrder || 0) - (b.sortOrder || 0));
  const habits = rows("habits").sort((a, b) => (a.createdAt || 0) - (b.createdAt || 0));
  const pages = {
    today: () => renderToday(tasks, habits),
    tasks: () => renderTasks(tasks),
    lists: () => renderNotes(tasks),
    note: renderNoteEditor,
    calendar: () => renderCalendar(tasks),
    history: () => renderHistoryIndex(habits),
    "habit-history": () => renderHabitHistory(habits),
    habits: () => renderHabits(habits),
    account: renderAccount,
    review: renderReview,
  };
  // A new page cross-fades in; the same page re-forms with rows springing to their new places.
  const view =
    page +
    "|" +
    (selectedList || "") +
    "|" +
    (page === "habit-history" ? historyHabitID : page === "note" ? noteID || "new" : "") +
    "|" +
    (page === "calendar" ? calendarView : "");
  const changedPage = view !== shownView;
  const before = !changedPage ? captureRows() : null;
  shownView = view;
  // Notes fill the window edge to edge, like a document app; other pages keep the reading width.
  document.body.dataset.view = page === "note" ? "lists" : page;
  $("#content").innerHTML = (pages[page] || renderSettings)();
  renderLists();
  bind();
  if (changedPage) window.scrollTo(0, 0);
  applyFills();
  if (before) settleRows(before);
  else enterPage();
  movePill();
  poppedID = null;
  if (focusSelector) document.querySelector(focusSelector)?.focus();
  if (state.recoveryReady && !$("#password-editor").open) $("#password-editor").showModal();
}

function bind() {
  bindTiles();
  bindToday();
  bindTasks();
  bindCalendar();
  bindHabits();
  bindSettings();
  bindAccount();
  bindReview();
  bindLists();
}

document.querySelectorAll("[data-page]").forEach(
  (b) =>
    (b.onclick = () => {
      page = b.dataset.page;
      selectedList = null;
      render();
    }),
);
$("#sidebar-search").onclick = () => {
  page = "lists";
  selectedList = null;
  render();
  $("#search")?.focus();
};
$("#sync-status").onclick = () => {
  page = "account";
  selectedList = null;
  render();
};

api.onChange(() => void load());
api.onSyncStatus((value) => {
  state.status = value.status;
  state.syncing = value.syncing;
  updateSync(value);
});
void load();

// Keep "today" current when the app stays open across midnight, sleeps, or the time zone changes.
const zoneSignature = () => Intl.DateTimeFormat().resolvedOptions().timeZone + new Date().getTimezoneOffset();
let lastCalendarDay = dayKey(new Date()),
  lastZone = zoneSignature();
function refreshCalendarDay() {
  const now = dayKey(new Date());
  const zoneChanged = zoneSignature() !== lastZone;
  lastZone = zoneSignature();
  if (zoneChanged) reschedule();
  if (now === lastCalendarDay && !zoneChanged) return;
  if (selected === lastCalendarDay) selected = now;
  lastCalendarDay = now;
  if (interacting()) pendingRender = true;
  else render();
}
window.addEventListener("focus", refreshCalendarDay);
api.onQuickAdd(() => {
  if (!document.querySelector("dialog[open]")) openQuickAdd();
});
// Reminders are planned in the main process; tell it which zone the page is in.
const reschedule = () => void api.reschedule(Intl.DateTimeFormat().resolvedOptions().timeZone);
reschedule();
api.onWake(refreshCalendarDay);
setInterval(refreshCalendarDay, 60000);
