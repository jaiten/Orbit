// Notes, laid out like Notion: a notes sidebar (sections and their pages) beside one page that is the
// whole writing surface. A note is a task record with isNote: true, so it syncs, backs up and undoes
// like everything else. With no page open, the right side is the section's overview: its pages and
// the tasks filed in it.
const collapsedTaskGroups = new Set(["Completed"]);
const collapsedNoteSections = new Set(JSON.parse(localStorage.getItem("collapsedNoteSections") || "[]"));
let searchQuery = "",
  noteFilter = "",
  noteID = null,
  noteSection = null,
  notePhotoDraft = [],
  notePageToken = 0,
  noteDisplayedEdited = null;
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
const noteDisplayTitle = (note) =>
  note.title || OrbitNotes.snippet(note.notes).slice(0, 60) || (note.photos?.length ? "Photo note" : "Untitled");

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
  document
    .querySelectorAll("[data-new-note]")
    .forEach((b) => (b.onclick = () => void createNote(b.dataset.newNote || null)));
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
      (b.onclick = async () => {
        if (page === "note") await saveNote();
        const id = b.dataset.noteSection;
        if (collapsedNoteSections.has(id)) collapsedNoteSections.delete(id);
        else collapsedNoteSections.add(id);
        localStorage.setItem("collapsedNoteSections", JSON.stringify([...collapsedNoteSections]));
        render();
      }),
  );
  document.querySelectorAll("[data-new-list]").forEach((button) => (button.onclick = () => openList()));
  if ($("#note-filter")) {
    $("#note-filter").oninput = async (e) => {
      const wasEmpty = !noteFilter;
      noteFilter = e.target.value;
      if (wasEmpty !== !noteFilter) {
        if (page === "note") await saveNote();
        render();
        const field = $("#note-filter");
        field?.focus();
        field?.setSelectionRange(field.value.length, field.value.length);
      }
      applyNoteFilter();
    };
    applyNoteFilter();
  }
  document.querySelectorAll("[data-drag-section]").forEach((group) => {
    group.ondragstart = (event) => event.dataTransfer.setData("text/orbit-section", group.dataset.dragSection);
    group.ondragover = (event) => {
      event.preventDefault();
      event.dataTransfer.dropEffect = "move";
    };
    group.ondrop = (event) => {
      event.preventDefault();
      const source = event.dataTransfer.getData("text/orbit-section");
      const ordered = orderedLists("notes");
      const from = ordered.findIndex((list) => list.id === source);
      const to = ordered.findIndex((list) => list.id === group.dataset.dragSection);
      if (from < 0 || from === to) return;
      ordered.splice(to, 0, ordered.splice(from, 1)[0]);
      void action(() =>
        api.batch(
          ordered.map((list, sortOrder) => ({
            key: list._key,
            payload: { ...clean(list), sortOrder, updatedAt: Date.now() },
          })),
        ),
      );
    };
  });
  document.querySelectorAll("[data-section-menu]").forEach((row) => {
    row.oncontextmenu = (event) => {
      event.preventDefault();
      event.stopPropagation();
      const id = row.dataset.sectionMenu;
      let menu = $("#row-menu");
      if (!menu) {
        menu = document.createElement("div");
        menu.id = "row-menu";
        menu.className = "row-menu";
        menu.setAttribute("role", "menu");
        document.body.append(menu);
      }
      menu.innerHTML =
        '<button role="menuitem" data-section-rename>Rename section</button><button role="menuitem" class="danger" data-section-delete>Delete section</button>';
      menu.hidden = false;
      menu.style.left = `${Math.min(event.clientX, innerWidth - 200)}px`;
      menu.style.top = `${Math.min(event.clientY, innerHeight - 90)}px`;
      menu.querySelector("[data-section-rename]").onclick = () => {
        closeRowMenu();
        openList(id, "notes");
      };
      menu.querySelector("[data-section-delete]").onclick = () => {
        closeRowMenu();
        beginSectionDeletion(id);
      };
      menu.querySelector("button").focus();
    };
  });
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
  const own = orderedLists("notes").map((l) => ({ id: l.id, name: l.name, color: colorName(l.color), own: true }));
  return own;
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
      const open = !collapsedNoteSections.has(key) || !!noteFilter;
      const selected = page === "lists" && (selectedList || "") === s.id && selectedList !== null;
      return `<div class="notes-nav-group" ${s.own ? `draggable="true" data-drag-section="${esc(s.id)}"` : ""}>
        <div class="notes-nav-row ${selected ? "selected" : ""}" data-section-menu="${esc(s.id)}">
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
                      `<button class="notes-nav-page ${n.id === openID ? "selected" : ""}" data-open-note="${esc(n.id)}" data-note-menu="${esc(n.id)}" data-search="${esc([n.title, n.notes].join(" ").toLowerCase())}">${docIcon}<span>${esc(noteDisplayTitle(n))}</span></button>`,
                  )
                  .join("") || `<p class="notes-nav-empty">No pages</p>`
              }</div>`
            : ""
        }
      </div>`;
    })
    .join("");
  return `<aside class="notes-nav" aria-label="Notes"><div id="notes-pane-grip" class="pane-grip" role="separator" aria-label="Note list width" aria-orientation="vertical" aria-valuemin="180" aria-valuemax="400" tabindex="0"></div>
    <div class="notes-nav-head">
      <span>Notes</span>
      <button class="icon-button" data-new-note="${esc(selectedList || "")}" aria-label="New note" title="New note (Ctrl+N)">${icon(ICONS.compose)}</button>
    </div>
    <input id="note-filter" type="search" placeholder="Find a page" aria-label="Find a page" value="${esc(noteFilter)}" />
    <div class="notes-nav-row ${page === "lists" && selectedList === null ? "selected" : ""}">
      <button class="notes-nav-toggle" data-note-section="all" aria-expanded="${!collapsedNoteSections.has("all") || !!noteFilter}" aria-label="${collapsedNoteSections.has("all") && !noteFilter ? "Expand" : "Collapse"} All notes"><span class="chevron ${collapsedNoteSections.has("all") && !noteFilter ? "" : "open"}">${icon(ICONS.chevron)}</span></button>
      <button class="notes-nav-name notes-nav-all" data-notes-home="all">All<span class="note-count">${notes().length}</span></button>
    </div>
    ${
      !collapsedNoteSections.has("all") || !!noteFilter
        ? `<div class="notes-nav-pages">${notes()
            .sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0))
            .map(
              (n) =>
                `<button class="notes-nav-page ${n.id === openID ? "selected" : ""}" data-open-note="${esc(n.id)}" data-note-menu="${esc(n.id)}" data-search="${esc([n.title, n.notes].join(" ").toLowerCase())}">${docIcon}<span>${esc(noteDisplayTitle(n))}</span></button>`,
            )
            .join("")}</div>`
        : ""
    }
    <div class="notes-nav-sections">${sections}</div>
    <button class="notes-nav-add" data-new-list>${icon(ICONS.plus)}New section</button>
  </aside>`;
}

function noteCard(n) {
  const snippet = OrbitNotes.snippet(n.notes);
  const search = [n.title, n.notes].join(" ").toLowerCase();
  return `<button class="note-card" data-open-note="${esc(n.id)}" data-note-menu="${esc(n.id)}" data-search="${esc(search)}">
    <span class="note-card-title">${docIcon}<span>${esc(noteDisplayTitle(n))}</span></span>
    <span class="note-card-text">${esc(snippet) || '<span class="muted">Empty page</span>'}</span>
    <span class="note-card-meta">${esc(n.listID ? sectionName(n.listID) : "All")} · ${esc(edited(n))}</span>
  </button>`;
}

/** The overview: a section's (or every) page as cards, and the tasks filed there. */
function renderNotes() {
  const heading = selectedList !== null && selectedList !== undefined ? sectionName(selectedList) || "All" : "Notes";
  const pages =
    selectedList === null || selectedList === undefined
      ? notes().sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0))
      : notesIn(selectedList);
  const title = selectedList === "" ? "All" : heading;
  return `<div class="notes-app">
    ${notesNav()}
    <section class="notes-pane notes-overview">
      <header class="page-head">
        <div><h1>${esc(title)}</h1><p class="subtitle">${pages.length} ${pages.length === 1 ? "page" : "pages"}</p></div>
        <div class="head-tools"><button class="icon-button" data-toggle-notes aria-label="Hide note list"></button>
          <input id="search" type="search" placeholder="Search" aria-label="Search notes" value="${esc(searchQuery)}" />

        </div>
      </header>
      ${
        pages.length
          ? `<div class="note-grid">${pages.map(noteCard).join("")}</div>`
          : `<div class="empty-state">${docIcon}<p><strong>No pages yet</strong><br />Start typing anywhere to begin a new page.</p></div>`
      }

      <div class="capture-dock">${addField(selectedList ? `Write a note in ${title}` : "Write a note")}</div>
    </section>
  </div>`;
}

/** Opens a page (or a new one in a section). */
function openNote(id, section = null, title = "") {
  notePageToken++;
  noteDisplayedEdited = notes().find((n) => n.id === id)?.updatedAt || null;
  notePhotoDraft = [...(notes().find((n) => n.id === id)?.photos || pendingNotes.get(id)?.photos || [])];
  noteID = id;
  if (id) {
    lastNoteID = id;
    localStorage.setItem("lastNoteID", id);
  }
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
async function createNote(section = null) {
  if (page === "note") await saveNote();
  openNote(null, section);
}
let noteDraftTitle = "";
let lastNoteID = localStorage.getItem("lastNoteID") || null;
const pendingNotes = new Map();
let noteSaveQueue = Promise.resolve();
function resumeNote() {
  const id = notes().some((note) => note.id === lastNoteID) || pendingNotes.has(lastNoteID) ? lastNoteID : null;
  openNote(id);
}
function resizeNoteFields() {
  for (const field of document.querySelectorAll("#note-title")) {
    field.style.height = "auto";
    field.style.height = Math.max(field.id === "note-title" ? 48 : 260, field.scrollHeight) + "px";
  }
}
function renderNoteEditor() {
  const note = notes().find((n) => n.id === noteID) || pendingNotes.get(noteID);
  const section = note ? note.listID || "" : noteSection || "";
  const options = [`<option value="">All</option>`]
    .concat(orderedLists("notes").map((l) => `<option value="${esc(l.id)}">${esc(l.name)}</option>`))
    .concat(`<option value="${SOMEDAY}">Someday</option>`)
    .join("")
    .replace(`value="${esc(section)}"`, `value="${esc(section)}" selected`);
  noteDisplayedEdited ??= note?.updatedAt || null;
  const when = noteDisplayedEdited
    ? new Date(noteDisplayedEdited).toLocaleString([], { dateStyle: "medium", timeStyle: "short" })
    : "Not saved yet";
  const titleValue = note ? (note.title === "Untitled" ? "" : note.title) : noteDraftTitle;
  return `<div class="notes-app">
    ${notesNav()}
    <section class="notes-pane note-pane" aria-label="Note">
      <div class="note-toolbar"><button class="icon-button" data-toggle-notes aria-label="Hide note list"></button>
        <nav class="crumbs" aria-label="Location"><button data-back-notes>Back to notes</button><span>/</span><button data-notes-home="${esc(section)}">${esc(section ? sectionName(section) : "All")}</button></nav>
        <span id="note-status" class="note-status"></span>
        <button class="icon-button" id="add-note-photo" aria-label="Add photo" title="Add photo">${icon("M3 3h18v18H3zM3 17l6-6 4 4 3-3 5 5M8 7h.01")}</button><input id="note-photo-file" type="file" accept="image/*" multiple hidden />
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
        <div id="note-body" class="note-body note-document" contenteditable="true" role="textbox" aria-multiline="true" data-placeholder="Start writing…" aria-label="Note text" spellcheck="true">${OrbitNoteDocument.markup(note?.notes || "", notePhotoDraft)}</div>
      </article>
    </section>
  </div>`;
}

let noteSaveTimer = null;
/** Saves without a forced re-render, so typing keeps its place; the first words create the page. */
function saveNote(rethrow = false) {
  clearTimeout(noteSaveTimer);
  if (page !== "note" || !$("#note-title") || !$("#note-body")) return noteSaveQueue;
  const title = $("#note-title").value.trim(),
    text = $("#note-body").value;
  if (!noteID && !title && !text.trim() && !notePhotoDraft.length) return noteSaveQueue;
  const existing = notes().find((note) => note.id === noteID) || pendingNotes.get(noteID);
  const record = existing || { ...newTask("", null), isNote: true };
  noteID = record.id;
  lastNoteID = noteID;
  localStorage.setItem("lastNoteID", noteID);
  const snapshot = {
    ...record,
    title,
    notes: text,
    photos: [...notePhotoDraft],
    listID: $("#note-section").value || null,
    updatedAt: Date.now(),
  };
  pendingNotes.set(snapshot.id, snapshot);
  noteSaveQueue = noteSaveQueue
    .catch(() => {})
    .then(async () => {
      const current = notes().find((note) => note.id === snapshot.id);
      if (
        current &&
        current.title === snapshot.title &&
        current.notes === snapshot.notes &&
        JSON.stringify(current.photos || []) === JSON.stringify(snapshot.photos || []) &&
        (current.listID || null) === snapshot.listID
      )
        return;

      await saveTasks([snapshot]);
    })
    .catch((error) => {
      showNotice(error.message);
      if (rethrow) throw error;
    });
  return noteSaveQueue;
}
function leaveNote(section) {
  page = "lists";
  selectedList = section === undefined ? null : section;
  noteID = null;
  render();
}
function bindNoteEditor() {
  if (!$("#note-title")) return;
  OrbitNoteDocument.bind($("#note-body"));
  resizeNoteFields();
  bindNotePhotos();
  const later = () => {
    resizeNoteFields();
    clearTimeout(noteSaveTimer);

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
    if (!e.defaultPrevented && e.key === "Backspace" && !$("#note-body").value && !notePhotoDraft.length) {
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
    void api.copy([title, text].filter(Boolean).join("\n\n"));
  };
  if ($("[data-note-to-task]"))
    $("[data-note-to-task]").onclick = () =>
      action(async () => {
        await saveNote();
        const n = notes().find((item) => item.id === noteID) || rows("tasks").find((item) => item.id === noteID);
        if (!n) return;
        await put("tasks", {
          ...n,
          title: n.title || OrbitNotes.split(n.notes).title || "Photo note",
          isNote: false,
          updatedAt: Date.now(),
        });
        pendingNotes.delete(n.id);
        lastNoteID = null;
        localStorage.removeItem("lastNoteID");
        page = "tasks";
        selectedList = null;
        noteID = null;
      });
  if ($("[data-delete-note]"))
    $("[data-delete-note]").onclick = () =>
      action(async () => {
        const n = notes().find((item) => item.id === noteID);
        if (n) {
          await put("tasks", n, true);
          pendingNotes.delete(n.id);
        }
        lastNoteID = null;
        localStorage.removeItem("lastNoteID");
        noteID = null;
        page = "lists";
      });
}

function renderLists() {
  // Someday is built in: always last, never renamed or deleted.
  const someday = `<div class="sidebar-list"><button data-list="${SOMEDAY}" class="${selectedList === SOMEDAY ? "selected" : ""}"><span class="list-dot lavender"></span>Someday</button></div>`;
  const own = orderedLists("notes");
  $("#sidebar-lists").innerHTML =
    `<div class="list-heading">Note sections</div>` +
    own
      .map(
        (l) =>
          `<div class="sidebar-list" data-section-menu="${esc(l.id)}"><button data-notes-section-link="${esc(l.id)}"><span class="list-dot ${colorName(l.color)}"></span>${esc(l.name)}</button><button data-edit-list="${esc(l.id)}" data-list-kind="notes" aria-label="Edit ${esc(l.name)} note section">⋯</button></div>`,
      )
      .join("") +
    `<div class="list-heading">Task categories</div>` +
    orderedLists("tasks")
      .map(
        (l) =>
          `<div class="sidebar-list"><button data-list="${esc(l.id)}" class="${page === "tasks" && selectedList === l.id ? "selected" : ""}"><span class="list-dot ${colorName(l.color)}"></span>${esc(l.name)}</button><button data-edit-list="${esc(l.id)}" aria-label="Edit ${esc(l.name)} section">⋯</button></div>`,
      )
      .join("") +
    someday;
  document.querySelectorAll("[data-notes-section-link]").forEach((button) => {
    button.onclick = async () => {
      if (page === "note") await saveNote();
      selectedList = button.dataset.notesSectionLink;
      page = "lists";
      render();
    };
  });
  document.querySelectorAll("[data-list]").forEach(
    (b) =>
      (b.onclick = () => {
        selectedList = b.dataset.list === SOMEDAY ? null : b.dataset.list;
        taskScope = b.dataset.list === SOMEDAY ? "someday" : "all";
        page = "tasks";
        render();
      }),
  );
  document
    .querySelectorAll("[data-edit-list]")
    .forEach((b) => (b.onclick = () => openList(b.dataset.editList, b.dataset.listKind || "tasks")));
}

let listEditingKind = "notes";
function openList(id, kind = page === "tasks" ? "tasks" : "notes") {
  listEditingKind = kind;
  $("#list-delete-confirm").hidden = true;
  editingList = rows("lists").find((l) => l.id === id) || null;
  const f = $("#list-form");
  f.elements.name.value = editingList?.name || "";
  f.elements.color.value = editingList?.color || "sage";
  $("#delete-list").hidden = !editingList;
  $("#list-order-controls").hidden = !editingList;
  const ordered = orderedLists(listEditingKind);
  const index = ordered.findIndex((list) => list.id === id);
  $("#list-move-up").disabled = index <= 0;
  $("#list-move-down").disabled = index < 0 || index === ordered.length - 1;
  $("#list-editor-title").textContent =
    listEditingKind === "notes"
      ? editingList
        ? "Edit Section"
        : "New Section"
      : editingList
        ? "Edit Category"
        : "New Category";
  openDialog($("#list-editor"));
  f.elements.name.focus();
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
        kind: listEditingKind,
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
    await deleteScopedGroup(editingList, listEditingKind, false);
    selectedList = null;
    $("#list-editor").close();
    $("#list-delete-confirm").hidden = true;
  });
let deletingNoteSection = null;
async function beginSectionDeletion(id) {
  if (page === "note") await saveNote();
  clearTimeout(noteSaveTimer);
  deletingNoteSection = rows("lists").find((list) => list.id === id);
  if (!deletingNoteSection) return;
  const count = notes().filter((note) => note.listID === id).length;
  if (!count) {
    void action(() => deleteScopedGroup(deletingNoteSection, "notes", false));
    return;
  }
  $("#section-delete-description").textContent =
    `${count} ${count === 1 ? "note is" : "notes are"} in this section. Move them to All, or delete them with the section.`;
  openDialog($("#section-delete"));
}
async function deleteScopedGroup(list, kind, deleteContents) {
  const changes = rows("tasks")
    .filter((task) => task.listID === list.id && !!task.isNote === (kind === "notes"))
    .map((task) => ({
      key: task._key,
      payload: { ...clean(task), listID: null, updatedAt: Date.now() },
      deleted: deleteContents,
    }));
  const opposite = kind === "notes" ? "tasks" : "notes";
  if (!list.kind) changes.push({ key: list._key, payload: { ...clean(list), kind: opposite, updatedAt: Date.now() } });
  else changes.push({ key: list._key, payload: clean(list), deleted: true });
  if (deleteContents)
    for (const change of changes) {
      if (!change.key.startsWith("tasks/")) continue;
      pendingNotes.delete(change.payload.id);
      if (lastNoteID === change.payload.id) {
        lastNoteID = null;
        localStorage.removeItem("lastNoteID");
      }
      if (noteID === change.payload.id) {
        noteID = null;
        page = "lists";
        notePageToken++;
      }
    }
  await api.batch(changes);
}
for (const [selector, remove] of [
  ["#release-section-notes", false],
  ["#delete-section-notes", true],
])
  $(selector).onclick = () =>
    action(async () => {
      if (deletingNoteSection) await deleteScopedGroup(deletingNoteSection, "notes", remove);
      if (noteID && !notes().some((note) => note.id === noteID)) {
        noteID = null;
        page = "lists";
      }
      selectedList = null;
      $("#section-delete").close();
      deletingNoteSection = null;
    });

function orderedLists(kind = "tasks") {
  return rows("lists")
    .filter((list) => list.id !== SOMEDAY && (!list.kind || list.kind === kind))
    .sort((a, b) => (a.sortOrder || 0) - (b.sortOrder || 0));
}
function moveList(delta) {
  void action(async () => {
    const ordered = orderedLists(listEditingKind);
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

function bindNotePhotos() {
  let lastRange = null;
  const body = $("#note-body");
  const remember = () => {
    const selection = getSelection();
    if (selection.rangeCount && body.contains(selection.anchorNode)) lastRange = selection.getRangeAt(0).cloneRange();
  };
  body.addEventListener("keyup", remember);
  body.addEventListener("mouseup", remember);
  const attach = async (files, insertion) => {
    const token = notePageToken;
    try {
      for (const file of files) {
        if (!file.type.startsWith("image/")) continue;
        if (notePhotoDraft.length >= 12) throw Error("A note can hold up to 12 photos.");
        if (file.size > 25000000) throw Error("Choose a photo smaller than 25 MB.");
        const photo = await api.addNotePhoto(new Uint8Array(await file.arrayBuffer()));
        if (token !== notePageToken || page !== "note" || !body.isConnected) return;
        body.focus();
        const selection = getSelection();
        if (insertion && body.contains(insertion.startContainer)) {
          selection.removeAllRanges();
          selection.addRange(insertion);
        } else body.setSelectionRange(body.value.length, body.value.length);
        document.execCommand("insertHTML", false, OrbitNoteDocument.figure(photo));
        notePhotoDraft = OrbitNoteDocument.read(body).photos;
        insertion = selection.rangeCount ? selection.getRangeAt(0).cloneRange() : null;
        await saveNote(true);
      }
    } catch (error) {
      showNotice(error.message);
    }
  };
  $("#add-note-photo").onmousedown = remember;
  $("#add-note-photo").onclick = () => $("#note-photo-file").click();
  $("#note-photo-file").onchange = (event) => void attach([...event.target.files], lastRange);
  body.ondrop = (event) => {
    event.preventDefault();
    const range = document.caretRangeFromPoint?.(event.clientX, event.clientY);
    const insertion = range && body.contains(range.startContainer) ? range : lastRange;
    const files = [...(event.dataTransfer?.files || [])].filter((file) => file.type.startsWith("image/"));
    if (files.length) {
      void attach(files, insertion);
      return;
    }
    body.focus();
    if (insertion) {
      const selection = getSelection();
      selection.removeAllRanges();
      selection.addRange(insertion);
    }
    document.execCommand("insertText", false, event.dataTransfer?.getData("text/plain") || "");
  };
  for (const field of [$("#note-title"), body])
    field.onpaste = (event) => {
      const photos = [...(event.clipboardData?.files || [])].filter((file) => file.type.startsWith("image/"));
      if (photos.length) {
        event.preventDefault();
        remember();
        void attach(photos, lastRange);
      } else if (field === body) {
        // Paste text only: external HTML must never introduce scripts, remote images or controls.
        event.preventDefault();
        document.execCommand("insertText", false, event.clipboardData?.getData("text/plain") || "");
      }
    };
}
