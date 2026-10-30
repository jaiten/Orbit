// Keyboard shortcuts. Ctrl+/ shows this list in the app.
const SHORTCUT_PAGES = ["today", "calendar", "tasks", "lists", "habits", "settings"];
const SHORTCUT_HELP = [
  ["Ctrl+N", "New note in Notes; quick add elsewhere"],
  ["Ctrl+Shift+V", "Switch Calendar between week and month"],
  ["Ctrl+1 … Ctrl+6", "Today, Calendar, Tasks, Notes, Habits, Settings"],
  ["Ctrl+F", "Search notes and tasks"],
  ["Space or Enter", "Complete or check the focused item"],
  ["Shift+F10 or right-click", "Item menu: copy text, timer and more"],
  ["E", "Edit the focused item"],
  ["Delete", "Delete the focused item (Undo appears)"],
  ["Esc", "Close a dialog"],
  ["Ctrl+Z", "Undo a delete or move"],
  ["Ctrl+/", "Show these shortcuts"],
  ["Just start typing", "Add a task (on Notes: start a new page)"],
];

function openShortcuts() {
  $("#shortcuts-list").innerHTML = SHORTCUT_HELP.map(
    ([keys, text]) => `<dt><kbd>${keys}</kbd></dt><dd>${text}</dd>`,
  ).join("");
  openDialog($("#shortcuts-dialog"));
}

async function goTo(name) {
  if (page === "note") await saveNote();
  if (name === "lists") {
    resumeNote();
    return;
  }
  closeRowMenu();
  if (name === "today") selected = today();
  page = name;
  selectedList = null;
  render();
}

async function deleteItem(tile) {
  const taskID = tile.querySelector("[data-toggle]")?.dataset.toggle;
  const habitID = tile.querySelector("[data-habit-toggle]")?.dataset.habitToggle;
  const task = rows("tasks").find((t) => t.id === taskID);
  if (task) return put("tasks", task, true);
  const habit = rows("habits").find((h) => h.id === habitID);
  if (!habit) return;
  // A habit's check-ins go with it; Undo brings both back.
  const logs = rows("habit_logs").filter((l) => l.habitID === habit.id);
  return api.batch([
    { key: habit._key, payload: clean(habit), deleted: true },
    ...logs.map((l) => ({ key: l._key, payload: clean(l), deleted: true })),
  ]);
}

document.addEventListener("keydown", (e) => {
  const dialogOpen = !!document.querySelector("dialog[open]");
  const key = e.key.toLowerCase();
  if (e.ctrlKey && !e.altKey && !e.metaKey) {
    if (dialogOpen) return;
    if (key === "n" && !e.shiftKey) {
      if (page === "lists" || page === "note") void createNote(selectedList);
      else openQuickAdd();
    } else if (key === "v" && e.shiftKey && page === "calendar") {
      calendarView = calendarView === "week" ? "month" : "week";
      render();
    } else if (/^[1-6]$/.test(key)) goTo(SHORTCUT_PAGES[Number(key) - 1]);
    else if (key === "f") {
      void (async () => {
        if (page === "note") await saveNote();
        page = "lists";
        selectedList = null;
        render();
        $("#search")?.focus();
      })();
    } else if (key === "/") openShortcuts();
    else if (
      key === "z" &&
      !e.shiftKey &&
      !e.target.closest?.("[contenteditable=true]") &&
      !["INPUT", "TEXTAREA"].includes(e.target.tagName) &&
      !$("#undo-toast").hidden
    )
      void action(() => api.undo());
    else return;
    e.preventDefault();
    return;
  }
  const typing = ["INPUT", "TEXTAREA", "SELECT"].includes(e.target.tagName) || e.target.isContentEditable;
  if (typing || dialogOpen || e.altKey || e.metaKey || e.ctrlKey) return;
  if (page === "today" && ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(e.key)) {
    e.preventDefault();
    selected =
      e.key === "ArrowLeft"
        ? OrbitHabits.addDays(selected, -1)
        : e.key === "ArrowRight"
          ? OrbitHabits.addDays(selected, 1)
          : today();
    render();
    return;
  }
  // Space and Enter press the focused tile's button natively; E and Delete act on the focused tile.
  const tile = e.target.closest?.(".check-tile");
  if (!tile || (key !== "e" && e.key !== "Delete")) {
    // Anything else typed while nothing is being edited starts a new item: a page on Notes, a task elsewhere.
    if (e.key.length === 1 && e.key.trim() && !e.isComposing && startTyping(e.key)) e.preventDefault();
    return;
  }
  if (key === "e") {
    e.preventDefault();
    const habit = tile.querySelector("[data-habit-menu]")?.dataset.habitMenu;
    if (habit) openHabit(habit);
    else tile.querySelector("[data-edit]")?.click();
  } else if (e.key === "Delete") {
    e.preventDefault();
    void action(() => deleteItem(tile));
  }
});

/** Starts capture with the first typed character. Returns false when there is nowhere sensible to type. */
function startTyping(char) {
  if ($("#row-menu") && !$("#row-menu").hidden) return false;
  if (page === "note") {
    const field = $("#note-body");
    if (!field) return false;
    field.focus();
    document.execCommand("insertText", false, char);
    field.dispatchEvent(new Event("input", { bubbles: true }));
    return true;
  }
  if (page === "lists") {
    openNote(null, selectedList || null, char);
    return true;
  }
  const field = $("#inline-task-input");
  if (field) {
    field.focus();
    field.value += char;
    field.setSelectionRange(field.value.length, field.value.length);
    field.dispatchEvent(new Event("input", { bubbles: true }));
    return true;
  }
  if (["account", "review", "settings"].includes(page)) return false;
  openQuickAdd();
  const input = $("#quick-add-form").elements.text;
  input.value = char;
  updateQuickPreview();
  return true;
}
