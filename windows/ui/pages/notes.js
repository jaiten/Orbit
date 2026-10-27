// Notes, laid out like Notion: a notes sidebar (sections and their pages) beside one page that is the
// whole writing surface. A note is a task record with isNote: true, so it syncs, backs up and undoes
// like everything else. With no page open, the right side is the section's overview: its pages and
// the tasks filed in it.
const collapsedTaskGroups = new Set(["Completed"]);
const collapsedNoteSections = new Set(JSON.parse(localStorage.getItem("collapsedNoteSections") || "[]"));
let searchQuery = "",
  noteFilter = "",
  noteID = null,
  noteSection = null;
const docIcon =
  '<svg class="doc-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5M9 13h6M9 17h4"/></svg>';
const icon = (d) => `<svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="${d}"/></svg>`;
const ICONS = {
  compose: "M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z",
  plus: "M12 5v14M5 12h14",
  copy: "M8 8h11v13H8zM5 16H4V3h11v1",
  task: "M9 11l3 3 8-8M20 12v7a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h9",
  trash: "M3 6h18M8 6V4h8v2M6 6l1 14h10l1-14",
  chevron: "m9 6 6 6-6 6",
};
const notes = () => rows("tasks").filter((t) => t.isNote);

/** Hides rows that don't match the search; the text includes notes and tags. Searching opens every group. */
function applySearch() {
  const words = searchQuery.toLowerCase().split(/\s+/).filter(Boolean);
  document.querySelectorAll("#content .notes-pane [data-search]").forEach((row) => {
    row.hidden = !words.every((w) => row.dataset.search.includes(w));
  });
  if (words.length) document.querySelectorAll("#content details.task-date-group").forEach((d) => (d.open = true));
}
function applyNoteFilter() {
  const words = noteFilter.toLowerCase().split(/\s+/).filter(Boolean);
  document.querySelectorAll("#content .notes-nav [data-search]").forEach((row) => {
    row.hidden = !words.every((w) => row.dataset.search.includes(w));
  });
}
function bindLists() {
  document.querySelectorAll("[data-new-note]").forEach(
    (b) =>
      (b.onclick = () => {
        openNote(null, b.dataset.newNote || null);
        $("#note-title")?.focus();
      }),
  );
  document.querySelectorAll("[data-open-note]").forEach((b) => (b.onclick = () => openNote(b.dataset.openNote)));
  document.querySelectorAll("[data-notes-home]").forEach(
    (b) =>
      (b.onclick = () => {
        page = "lists";
        // "all" is every note; "" is notes without a section.
        selectedList = b.dataset.notesHome === "all" ? null : b.dataset.notesHome;
        noteID = null;
        render();
      }),
  );
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
  if ($("#note-filter")) {
    $("#note-filter").oninput = (e) => {
      noteFilter = e.target.value;
      applyNoteFilter();
    };
    applyNoteFilter();
  }
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
function notesIn(id) {
  const known = new Set(rows("lists").map((l) => l.id));
  return notes()
    .filter((n) => (id ? n.listID === id : !n.listID || (n.listID !== SOMEDAY && !known.has(n.listID))))
    .sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0));
}
const edited = (n) => {
  const d = new Date(n.updatedAt || Date.now());
  return d.toDateString() === new Date().toDateString()
    ? d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })
    : d.toLocaleDateString([], { month: "short", day: "numeric" });
};

/** The notes sidebar: everything, then each section with its pages, then New section. */
function notesNav() {
  const openID = page === "note" ? noteID : null;
  const sections = noteSections()
    .map((s) => {
      const items = notesIn(s.id);
      if (!items.length && !s.own) return "";
      const key = s.id || "none";
      const open = !collapsedNoteSections.has(key) || items.some((n) => n.id === openID);
      const selected = page === "lists" && (selectedList || "") === s.id && selectedList !== null;
      return `<div class="notes-nav-group">
        <div class="notes-nav-row ${selected ? "selected" : ""}">
          <button class="notes-nav-toggle" data-note-section="${esc(key)}" aria-expanded="${open}" aria-label="${open ? "Collapse" : "Expand"} ${esc(s.name)}"><span class="chevron ${open ? "open" : ""}">${icon(ICONS.chevron)}</span></button>
          <button class="notes-nav-name" data-notes-home="${esc(s.id)}" title="${esc(s.name)}"><span class="list-dot ${s.color}"></span>${esc(s.name)}<span class="note-count">${items.length || ""}</span></button>
          <button class="icon-button small" data-new-note="${esc(s.id)}" aria-label="New note in ${esc(s.name)}" title="New note in ${esc(s.name)}">${icon(ICONS.plus)}</button>
        </div>
        ${
          open
            ? `<div class="notes-nav-pages">${
                items
                  .map(
                    (n) =>
                      `<button class="notes-nav-page ${n.id === openID ? "selected" : ""}" data-open-note="${esc(n.id)}" data-note-menu="${esc(n.id)}" data-search="${esc([n.title, n.notes].join(" ").toLowerCase())}">${docIcon}<span>${esc(n.title || "Untitled")}</span></button>`,
                  )
                  .join("") || `<p class="notes-nav-empty">No pages</p>`
              }</div>`
            : ""
        }
      </div>`;
    })
    .join("");
  return `<aside class="notes-nav" aria-label="Notes">
    <div class="notes-nav-head">
      <span>Notes</span>
      <button class="icon-button" data-new-note="${esc(selectedList || "")}" aria-label="New note" title="New note">${icon(ICONS.compose)}</button>
    </div>
    <input id="note-filter" type="search" placeholder="Find a page" aria-label="Find a page" value="${esc(noteFilter)}" />
    <button class="notes-nav-all ${page === "lists" && selectedList === null ? "selected" : ""}" data-notes-home="all">All notes<span class="note-count">${notes().length}</span></button>
    <div class="notes-nav-sections">${sections}</div>
    <button class="notes-nav-add" data-new-list>${icon(ICONS.plus)}New section</button>
  </aside>`;
}

function noteCard(n) {
  const snippet = OrbitNotes.snippet(n.notes);
  const search = [n.title, n.notes].join(" ").toLowerCase();
  return `<button class="note-card" data-open-note="${esc(n.id)}" data-note-menu="${esc(n.id)}" data-search="${esc(search)}">
    <span class="note-card-title">${docIcon}<span>${esc(n.title || "Untitled")}</span></span>
    <span class="note-card-text">${esc(snippet) || '<span class="muted">Empty page</span>'}</span>
    <span class="note-card-meta">${esc(n.listID ? sectionName(n.listID) : "Unsorted")} · ${esc(edited(n))}</span>
  </button>`;
}

/** The overview: a section's (or every) page as cards, and the tasks filed there. */
function renderNotes(tasks) {
  const heading =
    selectedList !== null && selectedList !== undefined ? sectionName(selectedList) || "Unsorted" : "Notes";
  const pages =
    selectedList === null || selectedList === undefined
      ? notes().sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0))
      : notesIn(selectedList);
  const filed = tasks.filter((t) =>
    selectedList === null || selectedList === undefined ? true : (t.listID || "") === selectedList,
  );
  const groups = ["Today", "Overdue", "Upcoming", "No date", "Someday", "Completed"]
    .map((group) => {
      const items = filed.filter((task) => OrbitPlanner.dateGroup(planItem(task), today()) === group);
      return items.length
        ? `<details class="task-date-group" data-task-group="${group}" ${collapsedTaskGroups.has(group) || !selectedList ? "" : "open"}><summary>${group} <span class="note-count">${items.length}</span></summary><div class="check-list">${items.map(taskRow).join("")}</div></details>`
        : "";
    })
    .join("");
  const title = selectedList === "" ? "Unsorted" : heading;
  return `<div class="notes-app">
    ${notesNav()}
    <section class="notes-pane notes-overview">
      <header class="page-head">
        <div><div class="eyebrow">${selectedList === null ? "Write it down" : "Section"}</div><h1>${esc(title)}</h1><p class="subtitle">${pages.length} ${pages.length === 1 ? "page" : "pages"}${filed.length ? ` · ${filed.length} ${filed.length === 1 ? "task" : "tasks"}` : ""}</p></div>
        <div class="head-tools">
          <input id="search" type="search" placeholder="Search" aria-label="Search notes and tasks" value="${esc(searchQuery)}" />
          <button class="primary-pill" data-new-note="${esc(selectedList || "")}">${icon(ICONS.compose)}New page</button>
        </div>
      </header>
      ${
        pages.length
          ? `<div class="note-grid">${pages.map(noteCard).join("")}</div>`
          : `<div class="empty-state">${docIcon}<p><strong>No pages yet</strong><br />Start typing anywhere to begin a new page.</p></div>`
      }
      ${groups ? `<div class="section-label"><h2>${selectedList ? "Tasks in " + esc(title) : "Tasks"}</h2><span>To-dos</span></div>${groups}` : ""}
    </section>
  </div>`;
}

/** Opens a page (or a new one in a section). */
function openNote(id, section = null, title = "") {
  noteID = id;
  noteSection = id ? (notes().find((n) => n.id === id)?.listID ?? null) : section;
  noteDraftTitle = title;
  page = "note";
  render();
  const field = $(id ? "#note-body" : "#note-title");
  if (field) {
    field.focus();
    field.setSelectionRange(field.value.length, field.value.length);
  }
}
let noteDraftTitle = "";
function renderNoteEditor() {
  const note = notes().find((n) => n.id === noteID);
  const section = note ? note.listID || "" : noteSection || "";
  const options = [`<option value="">No section</option>`]
    .concat(orderedLists().map((l) => `<option value="${esc(l.id)}">${esc(l.name)}</option>`))
    .concat(`<option value="${SOMEDAY}">Someday</option>`)
    .join("")
    .replace(`value="${esc(section)}"`, `value="${esc(section)}" selected`);
  const when = note
    ? new Date(note.updatedAt || Date.now()).toLocaleString([], { dateStyle: "medium", timeStyle: "short" })
    : "Not saved yet";
  const titleValue = note ? (note.title === "Untitled" ? "" : note.title) : noteDraftTitle;
  return `<div class="notes-app">
    ${notesNav()}
    <section class="notes-pane note-pane" aria-label="Note">
      <div class="note-toolbar">
        <nav class="crumbs" aria-label="Location"><button data-back-notes>Notes</button><span>/</span><button data-notes-home="${esc(section)}">${esc(section ? sectionName(section) : "Unsorted")}</button></nav>
        <span id="note-status" class="note-status">${note ? "Saved" : ""}</span>
        <button class="icon-button" data-copy-note aria-label="Copy text" title="Copy text">${icon(ICONS.copy)}</button>
        ${note ? `<button class="icon-button" data-note-to-task aria-label="Make it a Task" title="Make it a Task">${icon(ICONS.task)}</button><button class="icon-button danger" data-delete-note aria-label="Delete note" title="Delete note">${icon(ICONS.trash)}</button>` : ""}
      </div>
      <article class="note-page">
        <div class="note-glyph">${docIcon}</div>
        <textarea id="note-title" class="note-title-input" rows="1" maxlength="500" placeholder="Untitled" aria-label="Note title" spellcheck="true">${esc(titleValue)}</textarea>
        <dl class="note-props">
          <div><dt>${icon("M3 7h18M3 12h18M3 17h12")}Section</dt><dd><select id="note-section" aria-label="Section">${options}</select></dd></div>
          <div><dt>${icon("M12 7v5l3 2M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0")}Edited</dt><dd id="note-edited">${esc(when)}</dd></div>
        </dl>
        <textarea id="note-body" class="note-body" placeholder="Start writing, or press Esc to go back…" aria-label="Note text" spellcheck="true">${esc(note?.notes || "")}</textarea>
      </article>
    </section>
  </div>`;
}

let noteSaveTimer = null;
/** Saves without a forced re-render, so typing keeps its place; the first words create the page. */
async function saveNote() {
  clearTimeout(noteSaveTimer);
  // Leaving a page re-renders, and the field's blur arrives after the page has closed: never save then,
  // or the closed page would be written again as a new note.
  if (page !== "note") return;
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
  if ($("#note-status")) $("#note-status").textContent = "Saving…";
  try {
    await saveTasks([{ ...record, title: finalTitle, notes: text, listID: section, updatedAt: Date.now() }]);
    if ($("#note-status")) $("#note-status").textContent = "Saved";
    if ($("#note-edited")) $("#note-edited").textContent = "Just now";
  } catch (e) {
    showNotice(e.message);
  }
}
function leaveNote(section) {
  page = "lists";
  selectedList = section === undefined ? null : section;
  noteID = null;
  render();
}
function bindNoteEditor() {
  if (!$("#note-title")) return;
  const later = () => {
    clearTimeout(noteSaveTimer);
    if ($("#note-status")) $("#note-status").textContent = "Editing";
    noteSaveTimer = setTimeout(() => void saveNote(), 600);
  };
  $("#note-title").oninput = later;
  $("#note-body").oninput = later;
  $("#note-title").onkeydown = (e) => {
    if (
      e.key === "Enter" ||
      (e.key === "ArrowDown" && $("#note-title").selectionStart === $("#note-title").value.length)
    ) {
      e.preventDefault();
      $("#note-body").focus();
    }
  };
  $("#note-body").onkeydown = (e) => {
    if (e.key === "Backspace" && !$("#note-body").value) {
      e.preventDefault();
      $("#note-title").focus();
    }
  };
  for (const field of [$("#note-title"), $("#note-body")])
    field.addEventListener("keydown", async (e) => {
      if (e.key !== "Escape") return;
      e.preventDefault();
      await saveNote();
      leaveNote($("#note-section")?.value ?? null);
    });
  $("#note-section").onchange = () => void saveNote();
  $("#note-title").onblur = () => void saveNote();
  $("#note-body").onblur = () => void saveNote();
  // Leaving through the breadcrumbs saves first.
  document.querySelectorAll(".note-toolbar [data-back-notes], .note-toolbar [data-notes-home]").forEach(
    (b) =>
      (b.onclick = async () => {
        await saveNote();
        leaveNote(b.dataset.backNotes !== undefined ? null : b.dataset.notesHome);
      }),
  );
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
        noteID = null;
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
