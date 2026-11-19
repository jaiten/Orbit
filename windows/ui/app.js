// Page routing and start-up. Pages live in ui/pages; shared helpers in core.js, motion in motion.js.
let shownView = null;
/** The current page as HTML, from what is in memory now. */
function pageHTML() {
  // Reuse entity snapshots only while building this synchronous page. Every later build,
  // including optimistic edits and sync refreshes, starts from the current records again.
  return withRenderRows(buildPageHTML);
}
function buildPageHTML() {
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
  return (pages[page] || renderSettings)();
}
function render() {
  renderRevision++;
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
  const fresh = document.createElement("div");
  fresh.innerHTML = pageHTML();
  keepUnchangedPanels(fresh, changedPage);
  $("#content").replaceChildren(...fresh.childNodes);
  renderLists();
  bind();
  if (changedPage) {
    window.scrollTo(0, 0);
    showShortcutHint();
    if (page === "settings") void checkForUpdates();
  }
  applyFills();
  if (before) settleRows(before);
  else enterPage();
  movePill();
  poppedID = null;
  if (focusSelector) document.querySelector(focusSelector)?.focus({ preventScroll: true });
  if (state.recoveryReady && !$("#password-editor").open) openDialog($("#password-editor"));
}

/**
 * Today's cards whose content is the same as last time stay on screen as they are, instead of being
 * rebuilt: ticking a task leaves the habits card (its rows, hover and columns) untouched. Compared with
 * the HTML each card was drawn from, since a shown card also carries its column layout.
 */
let panelSources = new Map();
function keepUnchangedPanels(fresh, changedPage) {
  const sources = new Map();
  fresh.querySelectorAll(".today-panel[data-today-panel]").forEach((panel) => {
    const id = panel.dataset.todayPanel,
      source = panel.outerHTML;
    sources.set(id, source);
    if (changedPage || panelSources.get(id) !== source) return;
    const shown = $("#content").querySelector(`.today-panel[data-today-panel="${CSS.escape(id)}"]`);
    if (shown) panel.replaceWith(shown);
  });
  panelSources = sources;
}

function bind() {
  paintHistoryButtons();
  bindTiles();
  bindToday();
  bindTasks();
  bindCalendar();
  bindHabits();
  bindSettings();
  bindUpdates();
  refreshSelection();
  bindPaneLayout();
  flushSyncStatus();
  bindAccount();
  bindReview();
  bindLists();
}

document.querySelectorAll("[data-page]").forEach(
  (b) =>
    (b.onclick = () => {
      void goTo(b.dataset.page);
    }),
);
applyNavOrder();
bindNavDrag();
$("#sidebar-search").onclick = async () => {
  if (page === "note") await saveNote();
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
let lastCalendarDay = today(),
  lastZone = zoneSignature();
function refreshCalendarDay() {
  const now = today();
  const zoneChanged = zoneSignature() !== lastZone;
  lastZone = zoneSignature();
  if (zoneChanged) reschedule();
  if (now === lastCalendarDay && !zoneChanged) return;
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
