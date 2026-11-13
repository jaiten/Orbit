// Pane widths and visibility are local preferences; dragging never re-renders an editor.
const paneState = {
  main: {
    width: Number(localStorage.getItem("mainSidebarWidth")) || 216,
    open: localStorage.getItem("mainSidebarOpen") !== "false",
  },
  notes: {
    width: Number(localStorage.getItem("notesSidebarWidth")) || 248,
    open: localStorage.getItem("notesSidebarOpen") !== "false",
    // Until it is dragged, the notes list grows with the window so titles and previews stay readable.
    custom: localStorage.getItem("notesSidebarCustom") === "true",
  },
};
/** The notes list's width when it hasn't been set by hand: about a quarter of the room, 248–380px. */
const autoNotesWidth = () =>
  Math.round(Math.max(248, Math.min(380, (innerWidth - (paneState.main.open ? paneState.main.width : 0)) * 0.26)));
const notesWidth = () => (paneState.notes.custom ? paneState.notes.width : autoNotesWidth());
const sidebarIcon =
  '<svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16"/></svg>';
function applyPaneLayout() {
  const root = document.documentElement;
  root.style.setProperty(
    "--sidebar-width",
    paneState.main.open ? Math.max(180, Math.min(360, paneState.main.width)) + "px" : "0px",
  );
  root.style.setProperty(
    "--notes-width",
    Math.max(180, Math.min(notesWidth(), 400, innerWidth - (paneState.main.open ? paneState.main.width : 0) - 320)) +
      "px",
  );
  $("#notes-pane-grip")?.setAttribute("aria-valuenow", String(notesWidth()));
  root.dataset.sidebarClosed = String(!paneState.main.open);
  root.dataset.notesClosed = String(!paneState.notes.open);
  $(".sidebar").hidden = !paneState.main.open;
  $("#toggle-sidebar").setAttribute("aria-label", paneState.main.open ? "Hide main sidebar" : "Show main sidebar");
  $("#toggle-sidebar").title = paneState.main.open ? "Hide main sidebar" : "Show main sidebar";
  document.querySelectorAll(".notes-nav").forEach((nav) => (nav.hidden = !paneState.notes.open));
  document.querySelectorAll("[data-toggle-notes]").forEach((button) => {
    button.innerHTML = sidebarIcon;
    button.title = paneState.notes.open ? "Hide note list" : "Show note list";
    button.setAttribute("aria-label", button.title);
  });
}
function savePanes() {
  for (const [name, pane] of Object.entries(paneState)) {
    localStorage.setItem(name + "SidebarWidth", String(pane.width));
    localStorage.setItem(name + "SidebarOpen", String(pane.open));
  }
  localStorage.setItem("notesSidebarCustom", String(paneState.notes.custom));
  resizeNoteFields();
}
function bindPaneGrip(grip, name) {
  if (!grip) return;
  const pane = paneState[name],
    min = 180,
    max = name === "main" ? 360 : 400;
  grip.setAttribute("aria-valuenow", String(name === "notes" ? notesWidth() : pane.width));
  grip.onpointerdown = (event) => {
    if (event.button !== 0) return;
    event.preventDefault();
    if (name === "notes" && !pane.custom) pane.width = autoNotesWidth();
    if (name === "notes") pane.custom = true;
    const x = event.clientX,
      width = pane.width;
    grip.setPointerCapture(event.pointerId);
    document.body.classList.add("resizing-pane");
    // Dragging well past the narrowest width closes the sidebar (its show button then appears).
    let closing = false;
    grip.onpointermove = (move) => {
      const raw = width + move.clientX - x;
      closing = raw < min - 70;
      document.body.classList.toggle("closing-pane", closing);
      pane.width = Math.max(min, Math.min(max, raw));
      grip.setAttribute("aria-valuenow", String(pane.width));
      applyPaneLayout();
    };
    const finish = () => {
      grip.onpointermove = null;
      document.body.classList.remove("resizing-pane", "closing-pane");
      if (closing) {
        pane.open = false;
        pane.width = Math.max(min, width);
        applyPaneLayout();
      }
      savePanes();
    };
    grip.onpointerup = finish;
    grip.onpointercancel = finish;
  };
  grip.ondblclick = () => {
    // Double-click returns to the default: for the notes list, growing with the window again.
    if (name === "notes") pane.custom = false;
    pane.width = name === "main" ? 216 : 248;
    applyPaneLayout();
    savePanes();
  };
  grip.onkeydown = (event) => {
    if (!["ArrowLeft", "ArrowRight", "Home"].includes(event.key)) return;
    event.preventDefault();
    event.stopPropagation();
    if (name === "notes") {
      if (!pane.custom) pane.width = autoNotesWidth();
      pane.custom = event.key !== "Home";
    }
    pane.width =
      event.key === "Home"
        ? name === "main"
          ? 216
          : 248
        : Math.max(min, Math.min(max, pane.width + (event.key === "ArrowRight" ? 16 : -16)));
    grip.setAttribute("aria-valuenow", String(pane.width));
    applyPaneLayout();
    savePanes();
  };
}
function bindPaneLayout() {
  applyPaneLayout();
  bindPaneGrip($("#main-pane-grip"), "main");
  bindPaneGrip($("#notes-pane-grip"), "notes");
  document.querySelectorAll("[data-toggle-notes]").forEach((button) => (button.onclick = () => togglePane("notes")));
}
/** Shows or hides a sidebar ("main" or "notes"); also Ctrl+B and Ctrl+Shift+B. */
function togglePane(name) {
  paneState[name].open = !paneState[name].open;
  applyPaneLayout();
  savePanes();
}
$("#toggle-sidebar").innerHTML = sidebarIcon;
$("#toggle-sidebar").onclick = () => togglePane("main");
window.addEventListener("resize", () => {
  applyPaneLayout();
  resizeNoteFields();
});
applyPaneLayout();
