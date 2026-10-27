// Notes: titled pages grouped into sections (stored as lists), plus the tasks filed in a section.
// A note is a task record with isNote: true, so it syncs, backs up and undoes like everything else.
const collapsedTaskGroups = new Set(["Completed"]);
const collapsedNoteSections = new Set(JSON.parse(localStorage.getItem("collapsedNoteSections") || "[]"));
let searchQuery = "",
  noteID = null,
  noteSection = null;
const docIcon =
  '<svg class="doc-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5M9 13h6M9 17h4"/></svg>';
const notes = () => rows("tasks").filter((t) => t.isNote);

/** Hides rows that don't match the search; the text includes notes and tags. Searching opens every group. */
function applySearch() {
  const words = searchQuery.toLowerCase().split(/\s+/).filter(Boolean);
  document.querySelectorAll("#content [data-search]").forEach((row) => {
    row.hidden = !words.every((w) => row.dataset.search.includes(w));
  });
  if (words.length) document.querySelectorAll("#content details.task-date-group").forEach((d) => (d.open = true));
}
function bindLists() {
  document.querySelectorAll("[data-new-note]").forEach(
    (b) =>
      (b.onclick = () => {
        openNote(null, b.dataset.newNote || selectedList || null);
        $("#note-title")?.focus();
      }),
  );
  document.querySelectorAll("[data-open-note]").forEach((b) => (b.onclick = () => openNote(b.dataset.openNote)));
  document.querySelectorAll("[data-note-section]").forEach(
    (b) =>
      (b.onclick = () => {
        const id = b.dataset.noteSection;
        if (collapsedNoteSections.has(id)) collapsedNoteSections.delete(id);
        else collapsedNoteSections.add(id);
        localStorage.setItem("collapsedNoteSections", JSON.stringify([...collapsedNoteSections]));
        render();
      }),
  );
  document.querySelectorAll("[data-new-list]").forEach((button) => (button.onclick = () => openList()));
  bindNoteEditor();
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
  applySearch();
}

function sectionName(id) {
  if (id === SOMEDAY) return "Someday";
  return rows("lists").find((l) => l.id === id)?.name || "Notes";
}
/** Your sections in order, then notes without one, then Someday. */
function noteSections() {
  const own = orderedLists().map((l) => ({ id: l.id, name: l.name, color: colorName(l.color), own: true }));
  return [...own, { id: "", name: "Unsorted", color: "clay" }, { id: SOMEDAY, name: "Someday", color: "lavender" }];
}
function noteRow(n) {
  const edited = new Date(n.updatedAt || Date.now()).toLocaleDateString([], { month: "short", day: "numeric" });
  const snippet = OrbitNotes.snippet(n.notes);
  const search = [n.title, n.notes].join(" ").toLowerCase();
  return `<button class="note-row" data-open-note="${esc(n.id)}" data-search="${esc(search)}" data-note-menu="${esc(n.id)}">${docIcon}<span class="note-text"><span class="note-title">${esc(n.title || "Untitled")}</span>${snippet ? `<span class="note-snippet">${esc(snippet)}</span>` : ""}</span><span class="note-edited">${esc(edited)}</span></button>`;
}

function renderNotes(tasks) {
  const known = new Set(rows("lists").map((l) => l.id));
  const all = notes().sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0));
  const inSection = (n, id) => (id ? n.listID === id : !n.listID || (n.listID !== SOMEDAY && !known.has(n.listID)));
  const sections = noteSections().filter((s) => !selectedList || s.id === selectedList);
  const body = sections
    .map((s) => {
      const items = all.filter((n) => inSection(n, s.id));
      if (!items.length && !s.own && !selectedList) return "";
      const key = s.id || "none";
      const open = selectedList || !collapsedNoteSections.has(key);
      const list = open
        ? items.length
          ? `<div class="note-list">${items.map(noteRow).join("")}</div>`
          : `<p class="empty">No notes in ${esc(s.name)} yet.</p>`
        : "";
      // A chosen section is the page heading already; its notes follow directly.
      if (selectedList) return `<section class="note-section">${list}</section>`;
      return `<section class="note-section">
        <div class="note-section-head">
          <button class="note-toggle" data-note-section="${esc(key)}" aria-expanded="${!!open}"><span class="chevron ${open ? "open" : ""}" aria-hidden="true">›</span><span class="list-dot ${s.color}"></span><h2>${esc(s.name)}</h2><span class="note-count">${items.length}</span></button>
          <button class="icon-button" data-new-note="${esc(s.id)}" aria-label="New note in ${esc(s.name)}">${plus}</button>
        </div>
        ${list}
      </section>`;
    })
    .join("");
  // Tasks filed in a section stay reachable here; Today → All shows every task by date.
  const filed = tasks.filter((t) => (selectedList ? t.listID === selectedList : true));
  const groups = ["Today", "Overdue", "Upcoming", "No date", "Someday", "Completed"]
    .map((group) => {
      const items = filed.filter((task) => OrbitPlanner.dateGroup(planItem(task), today()) === group);
      return items.length
        ? `<details class="task-date-group" data-task-group="${group}" ${collapsedTaskGroups.has(group) || !selectedList ? "" : "open"}><summary>${group} (${items.length})</summary><div class="check-list">${items.map(taskRow).join("")}</div></details>`
        : "";
    })
    .join("");
  const heading = selectedList ? sectionName(selectedList) : "Notes";
  return `<div class="narrow notes-page">
    <header class="page-head">
      <div><div class="eyebrow">Write it down</div><h1>${esc(heading)}</h1><p class="subtitle">Ideas, lists and anything longer than a task.</p></div>
      <input id="search" type="search" placeholder="Search" aria-label="Search notes and tasks" value="${esc(searchQuery)}" />
    </header>
    <div class="notes-actions"><button class="pill" data-new-note="${esc(selectedList || "")}">+ New note</button><button class="pill quiet" data-new-list>+ New section</button></div>
    ${addField()}
    ${all.length || selectedList ? "" : '<p class="empty">No notes yet. Start a page, or type something long into Add a task.</p>'}
    ${body}
    ${groups ? `<div class="section-label"><h2>${selectedList ? "Tasks in " + esc(heading) : "Tasks"}</h2><span>To-dos</span></div>${groups}` : ""}
  </div>`;
}

/** A note as a page: icon, large title, properties and the text, like Notion. */
function openNote(id, section = null) {
  noteID = id;
  noteSection = id ? (notes().find((n) => n.id === id)?.listID ?? null) : section;
  page = "note";
  render();
}
function renderNoteEditor() {
  const note = notes().find((n) => n.id === noteID);
  const section = note ? note.listID || "" : noteSection || "";
  const options = [`<option value="">No section</option>`]
    .concat(orderedLists().map((l) => `<option value="${esc(l.id)}">${esc(l.name)}</option>`))
    .concat(`<option value="${SOMEDAY}">Someday</option>`)
    .join("");
  const edited = note
    ? new Date(note.updatedAt || Date.now()).toLocaleString([], { dateStyle: "medium", timeStyle: "short" })
    : "Not saved yet";
  return `<article class="note-page" aria-label="Note">
    <button class="back-link" data-back-notes>‹ ${esc(section ? sectionName(section) : "Notes")}</button>
    <div class="note-glyph">${docIcon}</div>
    <textarea id="note-title" class="note-title-input" rows="1" maxlength="500" placeholder="Untitled" aria-label="Note title" spellcheck="true">${esc(note?.title === "Untitled" ? "" : note?.title || "")}</textarea>
    <dl class="note-props">
      <div><dt>Section</dt><dd><select id="note-section" aria-label="Section">${options.replace(`value="${esc(section)}"`, `value="${esc(section)}" selected`)}</select></dd></div>
      <div><dt>Edited</dt><dd id="note-edited">${esc(edited)}</dd></div>
    </dl>
    <hr />
    <textarea id="note-body" class="note-body" placeholder="Start writing…" aria-label="Note text" spellcheck="true">${esc(note?.notes || "")}</textarea>
    <footer class="note-tools">
      <button data-copy-note>Copy text</button>${note ? `<button data-note-to-task>Make it a Task</button><button class="danger" data-delete-note>Delete</button>` : ""}
    </footer>
  </article>`;
}

let noteSaveTimer = null;
/** Saves without a forced re-render, so typing keeps its place; the first words create the page. */
async function saveNote() {
  clearTimeout(noteSaveTimer);
  const titleField = $("#note-title"),
    bodyField = $("#note-body");
  if (!titleField || !bodyField) return;
  const title = titleField.value.trim(),
    text = bodyField.value;
  const section = $("#note-section").value || null;
  const existing = notes().find((n) => n.id === noteID);
  if (!existing && !title && !text.trim()) return;
  const finalTitle = title || (text.trim() ? OrbitNotes.split(text).title : "Untitled");
  if (existing && existing.title === finalTitle && existing.notes === text && (existing.listID || null) === section)
    return;
  const record = existing || { ...newTask(finalTitle, null), isNote: true };
  noteID = record.id;
  try {
    await saveTasks([{ ...record, title: finalTitle, notes: text, listID: section, updatedAt: Date.now() }]);
    if ($("#note-edited")) $("#note-edited").textContent = "Saved";
  } catch (e) {
    showNotice(e.message);
  }
}
function bindNoteEditor() {
  if (!$("#note-title")) return;
  const later = () => {
    clearTimeout(noteSaveTimer);
    noteSaveTimer = setTimeout(() => void saveNote(), 600);
  };
  $("#note-title").oninput = later;
  $("#note-body").oninput = later;
  $("#note-title").onkeydown = (e) => {
    if (e.key === "Enter") {
      e.preventDefault();
      $("#note-body").focus();
    }
  };
  $("#note-section").onchange = () => void saveNote();
  $("#note-title").onblur = () => void saveNote();
  $("#note-body").onblur = () => void saveNote();
  $("[data-back-notes]").onclick = async () => {
    await saveNote();
    const section = $("#note-section").value;
    page = "lists";
    selectedList = section || null;
    render();
  };
  $("[data-copy-note]").onclick = () => {
    const title = $("#note-title").value.trim(),
      text = $("#note-body").value.trim();
    void api.copy(text ? `${title}\n\n${text}` : title).then(() => showNotice("Copied"));
  };
  if ($("[data-note-to-task]"))
    $("[data-note-to-task]").onclick = () =>
      action(async () => {
        await saveNote();
        const n = notes().find((item) => item.id === noteID) || rows("tasks").find((item) => item.id === noteID);
        if (!n) return;
        await put("tasks", { ...n, isNote: false, updatedAt: Date.now() });
        page = "lists";
      });
  if ($("[data-delete-note]"))
    $("[data-delete-note]").onclick = () =>
      action(async () => {
        const n = notes().find((item) => item.id === noteID);
        if (n) await put("tasks", n, true);
        noteID = null;
        page = "lists";
      });
}

function renderLists() {
  // Someday is built in: always last, never renamed or deleted.
  const someday = `<div class="sidebar-list"><button data-list="${SOMEDAY}" class="${selectedList === SOMEDAY ? "selected" : ""}"><span class="list-dot lavender"></span>Someday</button></div>`;
  $("#sidebar-lists").innerHTML =
    orderedLists()
      .map((l) => {
        const color = colorName(l.color);
        return `<div class="sidebar-list"><button data-list="${esc(l.id)}" class="${selectedList === l.id ? "selected" : ""}"><span class="list-dot ${color}"></span>${esc(l.name)}</button><button data-edit-list="${esc(l.id)}" aria-label="Edit ${esc(l.name)} section">⋯</button></div>`;
      })
      .join("") + someday;
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
  $("#list-editor-title").textContent = editingList ? "Edit Section" : "New Section";
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
    // Deleting a section keeps its notes and tasks; they move out of it.
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
