function renderInbox(tasks) {
  const inbox = tasks.filter((t) => !t.completedAt && (!selectedList || t.listID === selectedList));
  const name = rows("lists").find((l) => l.id === selectedList)?.name || "All to-dos";
  return `<div class="eyebrow">Keep it somewhere</div><h1>${esc(name)}</h1><p class="subtitle">Capture it now. Make room for it when you’re ready.</p>${inbox.map(taskRow).join("") || '<p class="empty">Nothing waiting here. A little breathing room.</p>'}<form class="quick" id="quick-add"><input name="title" aria-label="Capture a task" placeholder="Something for later…" required maxlength="500"><button>Add</button></form>`;
}

function renderLists() {
  $("#sidebar-lists").innerHTML = rows("lists")
    .sort((a, b) => (a.sortOrder || 0) - (b.sortOrder || 0))
    .map((l) => {
      const color = ["sage", "lavender", "honey", "clay"].includes(l.color) ? l.color : "sage";
      return `<div class="sidebar-list"><button data-list="${esc(l.id)}" class="${selectedList === l.id ? "selected" : ""}"><span class="list-dot ${color}"></span>${esc(l.name)}</button><button data-edit-list="${esc(l.id)}" aria-label="Edit ${esc(l.name)} list">⋯</button></div>`;
    })
    .join("");
  document.querySelectorAll("[data-list]").forEach(
    (b) =>
      (b.onclick = () => {
        selectedList = b.dataset.list;
        page = "inbox";
        render();
      }),
  );
  document.querySelectorAll("[data-edit-list]").forEach((b) => (b.onclick = () => openList(b.dataset.editList)));
}

function openList(id) {
  $("#list-delete-confirm").hidden = true;
  editingList = rows("lists").find((l) => l.id === id) || null;
  const f = $("#list-form");
  f.elements.name.value = editingList?.name || "";
  f.elements.color.value = editingList?.color || "sage";
  $("#delete-list").hidden = !editingList;
  $("#list-editor").showModal();
}

$("#new-list").onclick = () => openList();
$("#list-form").onsubmit = (e) => {
  e.preventDefault();
  const f = e.target;
  if (!f.elements.name.value.trim()) return;
  action(async () => {
    await put("lists", {
      ...(editingList || { id: crypto.randomUUID(), sortOrder: rows("lists").length }),
      name: f.elements.name.value.trim(),
      color: f.elements.color.value,
      updatedAt: Date.now(),
    });
    $("#list-editor").close();
  });
};
$("#delete-list").onclick = () => {
  $("#list-delete-confirm").hidden = false;
};
$("#confirm-delete-list").onclick = () =>
  action(async () => {
    if (!editingList) return;
    // Deleting a list keeps its to-dos; they move to Inbox.
    const changes = rows("tasks")
      .filter((t) => t.listID === editingList.id)
      .map((t) => ({ key: t._key, payload: { ...clean(t), listID: null, updatedAt: Date.now() } }));
    changes.push({ key: editingList._key, payload: clean(editingList), deleted: true });
    await api.batch(changes);
    selectedList = null;
    $("#list-editor").close();
    $("#list-delete-confirm").hidden = true;
  });
