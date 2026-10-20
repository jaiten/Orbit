// Page routing and start-up. Pages live in ui/pages; shared helpers in core.js.
function render() {
  document.querySelectorAll("[data-page]").forEach((b) => b.classList.toggle("selected", b.dataset.page === page));
  const tasks = rows("tasks").sort((a, b) => (a.sortOrder || 0) - (b.sortOrder || 0));
  const habits = rows("habits").sort((a, b) => (a.createdAt || 0) - (b.createdAt || 0));
  const pages = {
    today: () => renderToday(tasks, habits),
    lists: () => renderInbox(tasks),
    calendar: () => renderCalendar(tasks),
    history: () => renderHistoryIndex(habits),
    "habit-history": () => renderHabitHistory(habits),
    habits: () => renderHabits(habits),
  };
  $("#content").innerHTML = (pages[page] || renderSettings)();
  renderLists();
  bind();
  if (state.recoveryReady && !$("#password-editor").open) $("#password-editor").showModal();
}

function bind() {
  bindTiles();
  bindToday();
  bindCalendar();
  bindHabits();
  bindSettings();
}

document.querySelectorAll("[data-page]").forEach(
  (b) =>
    (b.onclick = () => {
      page = b.dataset.page;
      selectedList = null;
      render();
    }),
);
$("#sync-status").onclick = () => {
  page = "settings";
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
  if (now === lastCalendarDay && !zoneChanged) return;
  if (selected === lastCalendarDay) selected = now;
  lastCalendarDay = now;
  if (interacting()) pendingRender = true;
  else render();
}
window.addEventListener("focus", refreshCalendarDay);
api.onWake(refreshCalendarDay);
setInterval(refreshCalendarDay, 60000);

document.addEventListener("keydown", (e) => {
  if (e.ctrlKey && !e.shiftKey && !e.altKey && e.key.toLowerCase() === "n" && !document.querySelector("dialog[open]")) {
    e.preventDefault();
    openQuickAdd();
  }
});
