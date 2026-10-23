const collapsedTaskGroups = new Set(["Completed"]);
let searchQuery = "";
/** Hides rows that don't match the search; the text includes notes and tags. */
function applySearch() {
  const words = searchQuery.toLowerCase().split(/\s+/).filter(Boolean);
  document.querySelectorAll("#content [data-search]").forEach((row) => {
    row.hidden = !words.every((w) => row.dataset.search.includes(w));
  });
}
function bindLists() {
  if (!$("#search")) return;
  $("#search").oninput = (e) => {
    searchQuery = e.target.value;
    applySearch();
  };
  document.querySelectorAll("[data-task-group]").forEach((group) => {
    group.ontoggle = () => {
      if (group.open) collapsedTaskGroups.delete(group.dataset.taskGroup);
      else collapsedTaskGroups.add(group.dataset.taskGroup);
    };
  });
  document.querySelectorAll("[data-new-list]").forEach((button) => (button.onclick = () => openList()));
  applySearch();
}

function renderInbox(tasks) {
  const inbox = tasks.filter((t) => !selectedList || t.listID === selectedList);
  const name =
    selectedList === SOMEDAY ? "Someday" : rows("lists").find((l) => l.id === selectedList)?.name || "All Tasks";
  const empty = selectedList === SOMEDAY ? "Ideas for later go here." : "No tasks here.";
  const note = selectedList === SOMEDAY ? "Ideas for another time" : "Tasks grouped by day";
  return `<div class="narrow">
    <header class="page-head">
      <div><div class="eyebrow">Organize</div><h1>Lists</h1><p class="subtitle">${esc(name)} · ${note}</p></div>
      <input id="search" type="search" placeholder="Search" aria-label="Search tasks" value="${esc(searchQuery)}" />
    </header>
    <button data-new-list>+ New list</button>
    ${addField()}
    ${
      ["Today", "Overdue", "Upcoming", "No date", "Someday", "Completed"]
        .map((group) => {
          const items = inbox.filter((task) => OrbitPlanner.dateGroup(planItem(task), today()) === group);
          return items.length
            ? `<details class="task-date-group" data-task-group="${group}" ${collapsedTaskGroups.has(group) ? "" : "open"}><summary>${group} (${items.length})</summary><div class="check-list">${items.map(taskRow).join("")}</div></details>`
            : "";
        })
        .join("") || `<p class="empty">${empty}</p>`
    }
  </div>`;
}

function renderLists() {
  // Someday is built in: always first, never renamed or deleted.
  const someday = `<div class="sidebar-list"><button data-list="${SOMEDAY}" class="${selectedList === SOMEDAY ? "selected" : ""}"><span class="list-dot lavender"></span>Someday</button></div>`;
  $("#sidebar-lists").innerHTML =
    someday +
    rows("lists")
      .filter((l) => l.id !== SOMEDAY)
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
        page = "lists";
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
  $("#list-order-controls").hidden = !editingList;
  const ordered = orderedLists();
  const index = ordered.findIndex((list) => list.id === id);
  $("#list-move-up").disabled = index <= 0;
  $("#list-move-down").disabled = index < 0 || index === ordered.length - 1;
  $("#list-editor-title").textContent = editingList ? "Edit List" : "New List";
  $("#list-editor").showModal();
}

$("#new-list").onclick = () => openList();
$("#list-form").onsubmit = (e) => {
  e.preventDefault();
  const f = e.target;
  if (!f.elements.name.value.trim()) return;
  action(async () => {
    await put("lists", {
      ...(rows("lists").find((list) => list.id === editingList?.id) || {
        id: crypto.randomUUID(),
        sortOrder: rows("lists").length,
      }),
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
    // Deleting a list keeps its tasks; they move to Inbox.
    const changes = rows("tasks")
      .filter((t) => t.listID === editingList.id)
      .map((t) => ({ key: t._key, payload: { ...clean(t), listID: null, updatedAt: Date.now() } }));
    changes.push({ key: editingList._key, payload: clean(editingList), deleted: true });
    await api.batch(changes);
    selectedList = null;
    $("#list-editor").close();
    $("#list-delete-confirm").hidden = true;
  });

function orderedLists() {
  return rows("lists")
    .filter((list) => list.id !== SOMEDAY)
    .sort((a, b) => (a.sortOrder || 0) - (b.sortOrder || 0));
}
function moveList(delta) {
  void action(async () => {
    const ordered = orderedLists();
    const index = ordered.findIndex((list) => list.id === editingList?.id);
    const next = index + delta;
    if (index < 0 || next < 0 || next >= ordered.length) return;
    [ordered[index], ordered[next]] = [ordered[next], ordered[index]];
    await api.batch(
      ordered.map((list, sortOrder) => ({
        key: list._key,
        payload: { ...clean(list), sortOrder, updatedAt: Date.now() },
      })),
    );
    $("#list-move-up").disabled = next === 0;
    $("#list-move-down").disabled = next === ordered.length - 1;
  });
}
$("#list-move-up").onclick = () => moveList(-1);
$("#list-move-down").onclick = () => moveList(1);
