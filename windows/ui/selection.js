// Select rows with Ctrl-click (or a row's context menu), Shift-click for a run of rows, then Ctrl+C copies
// them as a list. Tasks, notes and habits can all be selected. Copy never mutates records.
// Keys are "task:id", "note:id" or "habit:id", as the rows' own data attributes name them.
const selectedRows = new Set();
let selectionAnchor = null;
const rowKey = (row) => row.dataset.rowMenu || (row.dataset.noteMenu ? "note:" + row.dataset.noteMenu : "");
const selectableRows = () => [...document.querySelectorAll("[data-row-menu], [data-note-menu]")];
function selectionItem(key) {
  const [kind, id] = key.split(":");
  return rows(kind === "habit" ? "habits" : "tasks").find((item) => item.id === id);
}
function selectRow(kind, id) {
  const key = `${kind}:${id}`;
  if (selectedRows.has(key)) selectedRows.delete(key);
  else selectedRows.add(key);
  selectionAnchor = key;
  refreshSelection();
}
/** Shift-click: every row between the last one clicked and this one joins the selection. */
function selectRange(key) {
  const keys = [...new Set(selectableRows().map(rowKey))];
  const from = keys.indexOf(selectionAnchor);
  const to = keys.indexOf(key);
  if (from < 0 || to < 0) return selectRow(...key.split(":"));
  for (const between of keys.slice(Math.min(from, to), Math.max(from, to) + 1)) selectedRows.add(between);
  refreshSelection();
}
function refreshSelection() {
  for (const key of selectedRows) if (!selectionItem(key)) selectedRows.delete(key);
  if (!selectedRows.size) selectionAnchor = null;
  selectableRows().forEach((row) => row.classList.toggle("is-selected", selectedRows.has(rowKey(row))));
  const bar = $("#selection-bar");
  bar.hidden = !selectedRows.size;
  $("#selection-count").textContent = `${selectedRows.size} selected`;
}
/** The selection as a list, in the order it appears on screen: "- title" per item, a note's text indented. */
function selectionText() {
  const order = [...new Set(selectableRows().map(rowKey))];
  const keys = [...selectedRows].sort((a, b) => {
    const ai = order.indexOf(a),
      bi = order.indexOf(b);
    return (ai < 0 ? Infinity : ai) - (bi < 0 ? Infinity : bi);
  });
  return keys
    .map((key) => {
      const item = selectionItem(key);
      if (!item) return "";
      const body = key.startsWith("note:") || item.isNote ? item.notes?.trim() : "";
      const title = item.title?.trim() || body?.split("\n")[0] || "";
      const rest = body && body.split("\n")[0].trim() === title ? body.split("\n").slice(1).join("\n").trim() : body;
      return [`- ${title}`, ...(rest ? rest.split("\n").map((line) => `  ${line}`) : [])].join("\n");
    })
    .filter(Boolean)
    .join("\n");
}
async function copySelected() {
  try {
    const sealed = [...selectedRows].some((key) => key.startsWith("note:") && OrbitLocks.isSealed(selectionItem(key)));
    if (sealed && !(await OrbitLocks.unlock())) return;
    await api.copy(selectionText());
    showSelectionNotice(`Copied ${selectedRows.size} item${selectedRows.size === 1 ? "" : "s"}`);
  } catch (error) {
    showNotice(error.message);
  }
}
function showSelectionNotice(text) {
  const count = $("#selection-count");
  if (!count) return;
  count.textContent = text;
  setTimeout(() => {
    if (selectedRows.size) count.textContent = `${selectedRows.size} selected`;
  }, 1400);
}
$("#copy-selected").onclick = () => void copySelected();
$("#clear-selection").onclick = () => {
  selectedRows.clear();
  refreshSelection();
};
// A Ctrl- or Shift-click (or any click while selecting) neither moves focus nor selects text, so the row
// shows only its selected look: no focus ring (pressing Shift otherwise counts as keyboard use).
document.addEventListener(
  "mousedown",
  (event) => {
    const row = event.target.closest?.("[data-row-menu], [data-note-menu]");
    if (!row || event.button !== 0 || event.target.closest(".row-actions, [data-delete-row], .note-actions")) return;
    if (event.ctrlKey || event.metaKey || event.shiftKey || selectedRows.size) {
      event.preventDefault();
      if (document.activeElement && row.contains(document.activeElement)) document.activeElement.blur();
    }
  },
  true,
);
document.addEventListener(
  "click",
  (event) => {
    const row = event.target.closest("[data-row-menu], [data-note-menu]");
    if (
      !row &&
      selectedRows.size &&
      !event.target.closest(
        "button, input, textarea, select, a, summary, [contenteditable], [role=button], #selection-bar, #row-menu",
      )
    ) {
      selectedRows.clear();
      refreshSelection();
    }
    if (!row) return;
    // The pencil and the bin still edit and delete while selecting.
    if (event.target.closest(".row-actions, [data-delete-row], [data-delete-note], .note-actions")) return;
    const multi = event.ctrlKey || event.metaKey;
    if (!(multi || event.shiftKey || selectedRows.size)) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    const key = rowKey(row);
    if (event.shiftKey && selectionAnchor) selectRange(key);
    else selectRow(...key.split(":"));
    window.getSelection()?.removeAllRanges();
  },
  true,
);
document.addEventListener("keydown", (event) => {
  if (
    !selectedRows.size ||
    event.target.closest?.("[contenteditable=true]") ||
    ["INPUT", "TEXTAREA", "SELECT"].includes(event.target.tagName)
  )
    return;
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "c") {
    event.preventDefault();
    void copySelected();
  }
  if (event.key === "Escape") {
    selectedRows.clear();
    refreshSelection();
  }
});
