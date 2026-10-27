// Beta: select rows with Ctrl-click, or start from a row's context menu. Copy never mutates records.
const selectedRows = new Set();
function selectRow(kind, id) {
  if (kind === "habit") return;
  if (selectedRows.has(id)) selectedRows.delete(id);
  else selectedRows.add(id);
  refreshSelection();
}
function refreshSelection() {
  for (const id of selectedRows) if (!rows("tasks").some((item) => item.id === id)) selectedRows.delete(id);
  document.querySelectorAll("[data-row-menu], [data-note-menu]").forEach((row) => {
    const id = row.dataset.rowMenu?.split(":")[1] || row.dataset.noteMenu;
    row.classList.toggle("is-selected", selectedRows.has(id));
  });
  const bar = $("#selection-bar");
  bar.hidden = !selectedRows.size;
  $("#selection-count").textContent = `${selectedRows.size} selected`;
}
async function copySelected() {
  const text = [...selectedRows]
    .map((id) => rows("tasks").find((item) => item.id === id))
    .filter(Boolean)
    .map((item) => [item.title, item.notes].filter((value) => value?.trim()).join("\n\n"))
    .join("\n\n");
  try {
    await api.copy(text);
  } catch (error) {
    showNotice(error.message);
  }
}
$("#copy-selected").onclick = () => void copySelected();
$("#clear-selection").onclick = () => {
  selectedRows.clear();
  refreshSelection();
};
document.addEventListener(
  "click",
  (event) => {
    const row = event.target.closest("[data-row-menu], [data-note-menu]");
    if (!row || row.dataset.rowMenu?.startsWith("habit:") || !(event.ctrlKey || event.metaKey || selectedRows.size))
      return;
    event.preventDefault();
    event.stopImmediatePropagation();
    const id = row.dataset.rowMenu?.split(":")[1] || row.dataset.noteMenu;
    selectRow("task", id);
  },
  true,
);
document.addEventListener("keydown", (event) => {
  if (!selectedRows.size || ["INPUT", "TEXTAREA", "SELECT"].includes(event.target.tagName)) return;
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "c") {
    event.preventDefault();
    void copySelected();
  }
  if (event.key === "Escape") {
    selectedRows.clear();
    refreshSelection();
  }
});
