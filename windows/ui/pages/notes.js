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
  noteIconDraft = "doc.text",
  notePageToken = 0,
  noteDisplayedEdited = null;
function noteGlyph(value) {
  const choice = OrbitNotes.resolveIcon(value);
  return `<svg class="doc-icon" data-note-icon="${choice.id}" viewBox="0 0 24 24" aria-hidden="true"><path d="${choice.path}"/></svg>`;
}
const docIcon = noteGlyph(null);
const icon = (d) => `<svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="${d}"/></svg>`;
const ICONS = {
  compose: "M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z",
  plus: "M12 5v14M5 12h14",
  copy: "M8 8h11v13H8zM5 16H4V3h11v1",
  task: "M9 11l3 3 8-8M20 12v7a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h9",
  trash: "M3 6h18M8 6V4h8v2M6 6l1 14h10l1-14",
  chevron: "m9 6 6 6-6 6",
  more: "M5 12h.01M12 12h.01M19 12h.01",
  photo: "M3 3h18v18H3zM3 17l6-6 4 4 3-3 5 5M8 7h.01",
};
const HIDDEN_PATH =
  "M3 3l18 18M10.6 6.1A9.9 9.9 0 0 1 12 6c5 0 9 6 9 6a17 17 0 0 1-2.5 3.1M6.6 6.6C4.3 8.1 3 12 3 12s4 6 9 6c1.5 0 2.9-.4 4.1-1M9.9 9.9a3 3 0 0 0 4.2 4.2";
const notes = () => rows("tasks").filter((t) => t.isNote);
/** A note's name in lists. A locked page shows only "Locked note" until the password is entered. */
const noteDisplayTitle = (note) =>
  OrbitLocks.isSealed(note)
    ? "Locked note"
    : OrbitLocks.isHidden(note)
      ? "Hidden note"
      : note.title ||
        (OrbitLocks.isLocked(note) ? "" : OrbitNotes.snippet(note.notes).slice(0, 60)) ||
        (note.photos?.length ? "Photo note" : OrbitLocks.isLocked(note) ? "Locked note" : "Untitled");
/** What a find or search may match: nothing from a hidden page, only the title of a locked one. */
const noteSearchText = (note) =>
  OrbitLocks.isHidden(note) || OrbitLocks.isSealed(note)
    ? ""
    : (OrbitLocks.isLocked(note) ? note.title || "" : [note.title, note.notes].join(" ")).toLowerCase();
/** A page in the notes list: its icon (a lock when locked) and title. */
function noteNavButton(n, openID) {
  const glyph = OrbitLocks.isLocked(n)
    ? `<svg class="doc-icon note-lock-glyph" viewBox="0 0 24 24" aria-hidden="true"><path d="${LOCK_PATH}"/></svg>`
    : noteGlyph(n.noteIcon);
  const hidden = OrbitLocks.isHidden(n);
  // Under the title: when it was edited and the start of the text, as in Apple Notes. Locked and
  // hidden pages show only the time.
  const preview = hidden || OrbitLocks.isLocked(n) ? "" : OrbitNotes.snippet(n.notes);
  return `<button class="notes-nav-page ${n.id === openID ? "selected" : ""} ${hidden ? "hidden-note" : ""}" draggable="true" data-drag-note="${esc(n.id)}" data-open-note="${esc(n.id)}" data-note-menu="${esc(n.id)}" title="${esc(noteDisplayTitle(n))}" data-search="${esc(noteSearchText(n))}">${glyph}<span class="notes-nav-title">${esc(noteDisplayTitle(n))}</span><span class="notes-nav-sub"><b>${esc(edited(n))}</b> ${esc(preview)}</span></button>`;
}
/** Pages under date headings (Today, Yesterday, Previous 7 Days…), as on iOS. `render` draws one page. */
function datedPages(items, render, wrap = (inner) => inner) {
  return OrbitNotes.dateGroups(items, (n) => n.updatedAt || Date.now())
    .map(
      (g) =>
        `<div class="note-date-group" data-note-date-group><h3 class="note-date-heading">${esc(g.title)}</h3>${wrap(g.items.map(render).join(""))}</div>`,
    )
    .join("");
}
/** Hides a date heading once a find or search has hidden every page under it. */
function hideEmptyDateGroups(scope) {
  document.querySelectorAll(`${scope} [data-note-date-group]`).forEach((group) => {
    group.hidden = ![...group.querySelectorAll("[data-search]")].some((row) => !row.hidden);
  });
}
/** Pages that may be listed: a locked section's pages stay out of view until unlocked. */
const listedNotes = (items) => items.filter((n) => !OrbitLocks.sectionSealed(n.listID));

/** Hides rows that don't match the search; the text includes notes and tags. Searching opens every group. */
function applySearch() {
  const words = searchQuery.toLowerCase().split(/\s+/).filter(Boolean);
  document.querySelectorAll("#content .notes-pane [data-search]").forEach((row) => {
    row.hidden = !words.every((w) => row.dataset.search.includes(w));
  });
  hideEmptyDateGroups("#content .notes-pane");
  if (words.length) document.querySelectorAll("#content details.task-date-group").forEach((d) => (d.open = true));
}
function applyNoteFilter() {
  const words = noteFilter.toLowerCase().split(/\s+/).filter(Boolean);
  document.querySelectorAll("#content .notes-nav [data-search]").forEach((row) => {
    row.hidden = !words.every((w) => row.dataset.search.includes(w));
  });
  hideEmptyDateGroups("#content .notes-nav");
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
        // "" is General: notes without a section.
        selectedList = b.dataset.notesHome || "";
        noteID = null;
        render();
        unlockSelectedSection();
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
  document
    .querySelectorAll("[data-unlock-notes]")
    .forEach((button) => (button.onclick = async () => (await OrbitLocks.unlock()) && render()));
  document.querySelectorAll("[data-lock-now]").forEach((button) => (button.onclick = () => OrbitLocks.lockNow()));
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
    group.addEventListener("dragover", (event) => {
      if (!event.dataTransfer.types.includes("text/orbit-section")) return;
      event.preventDefault();
      event.dataTransfer.dropEffect = "move";
    });
    group.addEventListener("drop", (event) => {
      const source = event.dataTransfer.getData("text/orbit-section");
      if (!source) return;
      event.preventDefault();
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
    });
  });
  bindNoteDrops();
  document.querySelectorAll("[data-section-menu]").forEach((row) => {
    row.oncontextmenu = (event) => {
      event.preventDefault();
      event.stopPropagation();
      const id = row.dataset.sectionMenu;
      showMenu(
        [
          ["Rename section", () => openList(id, "notes")],
          ...sectionLockEntries(id),
          ["Delete section", () => beginSectionDeletion(id)],
        ],
        event.clientX,
        event.clientY,
      );
    };
  });
  bindNoteEditor();
  if (!$("#search")) return;
  $("#search").oninput = (e) => {
    // Searching looks through every section (except locked ones); clearing it shows the section again.
    const wasEmpty = !searchQuery.trim();
    searchQuery = e.target.value;
    if (wasEmpty !== !searchQuery.trim() && page === "lists") {
      render();
      const field = $("#search");
      field?.focus();
      field?.setSelectionRange(field.value.length, field.value.length);
    }
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

/** Notes without a section live in General, the default spot (iPhone uses the same name). */
const GENERAL = "General";
function sectionName(id) {
  if (id === SOMEDAY) return "Someday";
  if (!id) return GENERAL;
  return rows("lists").find((l) => l.id === id)?.name || GENERAL;
}
/** General first, then your sections in order, then Someday when it holds notes. */
function noteSections() {
  const own = orderedLists("notes").map((l) => ({ id: l.id, name: l.name, color: colorName(l.color), own: true }));
  return [
    { id: "", name: GENERAL, color: "accent", own: false },
    ...own,
    // Notes filed in Someday get a group only while there are some.
    { id: SOMEDAY, name: "Someday", color: "lavender", own: false, optional: true },
  ];
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

/** The notes sidebar: General, then each section with its pages, then New section. */
function notesNav() {
  const openID = page === "note" ? noteID : null;
  const sections = noteSections()
    .map((s) => {
      const items = notesIn(s.id);
      const sealed = OrbitLocks.sectionSealed(s.id);
      const section = rows("lists").find((l) => l.id === s.id);
      const marks = `${section?.locked ? `<svg class="ui-icon section-mark" viewBox="0 0 24 24" aria-label="Locked"><path d="${LOCK_PATH}"/></svg>` : ""}${section?.hidden ? `<svg class="ui-icon section-mark" viewBox="0 0 24 24" aria-label="Titles hidden"><path d="${HIDDEN_PATH}"/></svg>` : ""}`;
      if (s.optional && !items.length) return "";
      const key = s.id || "none";
      const open = !collapsedNoteSections.has(key) || !!noteFilter;
      const selected = page === "lists" && (selectedList || "") === s.id;
      return `<div class="notes-nav-group" data-note-drop="${esc(s.id || "")}" ${s.own ? `draggable="true" data-drag-section="${esc(s.id)}"` : ""}>
        <div class="notes-nav-row ${selected ? "selected" : ""}" data-section-menu="${esc(s.id)}">
          <button class="notes-nav-toggle" data-note-section="${esc(key)}" aria-expanded="${open}" aria-label="${open ? "Collapse" : "Expand"} ${esc(s.name)}"><span class="chevron ${open ? "open" : ""}">${icon(ICONS.chevron)}</span></button>
          <button class="notes-nav-name" data-notes-home="${esc(s.id)}" title="${esc(s.name)}"><span class="list-dot ${s.color}"></span>${esc(s.name)}${marks}<span class="note-count">${sealed ? "" : items.length || ""}</span></button>
          <button class="icon-button small" data-new-note="${esc(s.id)}" aria-label="New note in ${esc(s.name)}" title="New note in ${esc(s.name)}">${icon(ICONS.plus)}</button>
        </div>
        ${
          // A locked section lists nothing until unlocked; clicking its name asks for the password.
          open && !sealed
            ? `<div class="notes-nav-pages">${
                datedPages(items, (n) => noteNavButton(n, openID)) || `<p class="notes-nav-empty">No pages</p>`
              }</div>`
            : ""
        }
      </div>`;
    })
    .join("");
  return `<aside class="notes-nav" aria-label="Notes"><div id="notes-pane-grip" class="pane-grip" role="separator" aria-label="Note list width" aria-orientation="vertical" aria-valuemin="180" aria-valuemax="400" tabindex="0"></div>
    <div class="notes-nav-head">
      <span>Notes</span>
      ${
        // Lock appears while notes are unlocked; unlocking happens only by opening a locked page or section.
        OrbitLocks.unlocked && OrbitLocks.anyLocks()
          ? `<button class="notes-lock-toggle" data-lock-now aria-label="Lock now" title="Lock notes again (Ctrl+L)">${icon(LOCK_PATH)}Lock</button>`
          : ""
      }
      <button class="icon-button" data-new-note="${esc(selectedList || "")}" aria-label="New note" title="New note (Ctrl+N)">${icon(ICONS.compose)}</button>
    </div>
    <input id="note-filter" type="search" placeholder="Find a page" aria-label="Find a page" value="${esc(noteFilter)}" />
    <div class="notes-nav-sections">${sections}</div>
    <button class="notes-nav-add" data-new-list>${icon(ICONS.plus)}New section</button>
  </aside>`;
}

function noteCard(n) {
  const masked = OrbitLocks.isHidden(n) || OrbitLocks.isLocked(n);
  const snippet = masked ? "" : OrbitNotes.snippet(n.notes);
  const search = noteSearchText(n);
  return `<button class="note-card" data-open-note="${esc(n.id)}" data-note-menu="${esc(n.id)}" title="${esc(noteDisplayTitle(n))}" data-search="${esc(search)}">
    <span class="note-card-title">${noteGlyph(n.noteIcon)}<span>${esc(noteDisplayTitle(n))}</span></span>
    <span class="note-card-text">${esc(snippet) || `<span class="muted">${OrbitLocks.isLocked(n) ? "Locked" : OrbitLocks.isHidden(n) ? "Hidden" : "Empty page"}</span>`}</span>
    <span class="note-card-meta">${esc(sectionName(n.listID))} · ${esc(edited(n))}</span>
  </button>`;
}

/** The overview: a section's pages as cards (General when none is chosen). A search looks through
    every section that isn't locked. */
/** Opening a locked section asks for the password straight away. */
function unlockSelectedSection() {
  if (selectedList && OrbitLocks.sectionSealed(selectedList)) void OrbitLocks.unlock().then((ok) => ok && render());
}
function renderNotes() {
  const searching = !!searchQuery.trim();
  // A locked section shows only its lock until the password is entered: no pages and no capture bar.
  if (!searching && selectedList && OrbitLocks.sectionSealed(selectedList))
    return `<div class="notes-app">
    ${notesNav()}
    <section class="notes-pane note-pane note-sealed" aria-label="Locked section">
      <div class="locked-page">${icon(LOCK_PATH)}<h1>${esc(sectionName(selectedList))} is locked</h1><p class="secondary">Enter your notes password to see its pages.</p><button class="primary" data-unlock-notes>Unlock</button></div>
    </section>
  </div>`;
  const pages = searching
    ? listedNotes(notes()).sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0))
    : listedNotes(notesIn(selectedList || null));
  const title = searching ? "Search" : sectionName(selectedList || null);
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
          ? `<div class="note-date-groups">${datedPages(pages, noteCard, (cards) => `<div class="note-grid">${cards}</div>`)}</div>`
          : `<div class="empty-state">${docIcon}<p><strong>No pages yet</strong><br />Start typing anywhere to begin a new page.</p></div>`
      }

      <div class="capture-dock">${addField(selectedList ? `Write a note in ${title}` : "Write a note")}</div>
    </section>
  </div>`;
}

/** Opens a page (or a new one in a section). A locked page asks for the password first. */
function openNote(id, section = null, title = "") {
  // A new page in a locked section waits for the password, however it was started.
  if (!id && section && OrbitLocks.sectionSealed(section)) {
    void OrbitLocks.unlock().then((ok) => ok && openNote(id, section, title));
    return;
  }
  const target = id && notes().find((n) => n.id === id);
  if (target && OrbitLocks.isSealed(target)) {
    void OrbitLocks.unlock().then((ok) => ok && openNote(id, section, title));
    return;
  }
  notePageToken++;
  noteDisplayedEdited = notes().find((n) => n.id === id)?.updatedAt || null;
  notePhotoDraft = [...(notes().find((n) => n.id === id)?.photos || pendingNotes.get(id)?.photos || [])];
  const opened = notes().find((n) => n.id === id) || pendingNotes.get(id);
  noteIconDraft = OrbitNotes.resolveIcon(opened?.noteIcon).id;
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
/** Back to the last page; if it is locked now, a blank page to write on instead of the lock screen. */
function resumeNote() {
  const last = notes().find((note) => note.id === lastNoteID) || pendingNotes.get(lastNoteID);
  openNote(last && !OrbitLocks.isSealed(last) ? lastNoteID : null);
}
function resizeNoteFields() {
  for (const field of document.querySelectorAll("#note-title")) {
    field.style.height = "auto";
    field.style.height = Math.max(field.id === "note-title" ? 48 : 260, field.scrollHeight) + "px";
  }
}
function renderNoteEditor() {
  const note = notes().find((n) => n.id === noteID) || pendingNotes.get(noteID);
  if (OrbitLocks.isSealed(note))
    return `<div class="notes-app">
    ${notesNav()}
    <section class="notes-pane note-pane note-sealed" aria-label="Locked note">
      <div class="locked-page">${icon(LOCK_PATH)}<h1>Locked note</h1><p class="secondary">Enter your notes password to read it.</p><button class="primary" data-unlock-notes>Unlock</button></div>
    </section>
  </div>`;
  const section = note ? note.listID || "" : noteSection || "";
  const options = [`<option value="">${GENERAL}</option>`]
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
        <nav class="crumbs" aria-label="Location"><button data-back-notes>Back to notes</button><span>/</span><button data-notes-home="${esc(section)}">${esc(sectionName(section))}</button></nav>
        <span id="note-status" class="note-status"></span>
        ${OrbitLocks.isLocked(note) ? `<span class="note-locked-mark" title="Locked">${icon(LOCK_PATH)}</span>` : ""}
        <input id="note-photo-file" type="file" accept="image/*" multiple hidden />
        <button class="icon-button" id="note-more" aria-label="More note options" aria-haspopup="menu" title="More">${icon(ICONS.more)}</button>
        ${note ? `<button class="icon-button danger" data-delete-note aria-label="Delete note" title="Delete note">${icon(ICONS.trash)}</button>` : ""}
      </div>
      <article class="note-page">
        <button type="button" class="note-glyph" id="change-note-icon" aria-label="Change note icon" aria-haspopup="dialog" title="Change note icon (${esc(OrbitNotes.resolveIcon(noteIconDraft).name)})">${noteGlyph(noteIconDraft)}</button>
        <dialog id="note-icon-picker" aria-labelledby="note-icon-picker-title">
          <header><h2 id="note-icon-picker-title">Note icon</h2><button type="button" class="icon-button" data-close-note-icons aria-label="Close icon picker">${icon("m6 6 12 12M6 18 18 6")}</button></header>
          <div class="note-icon-options">${OrbitNotes.icons
            .map(
              (choice) =>
                `<button type="button" data-pick-note-icon="${choice.id}" aria-label="${esc(choice.name)}" title="${esc(choice.name)}" aria-pressed="${choice.id === noteIconDraft}">${noteGlyph(choice.id)}</button>`,
            )
            .join("")}</div>
        </dialog>
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
    noteIcon: noteIconDraft === "doc.text" ? null : noteIconDraft,
    listID: $("#note-section").value || null,
    updatedAt: Date.now(),
  };
  pendingNotes.set(snapshot.id, snapshot);
  noteSaveQueue = noteSaveQueue
    .catch(() => {})
    .then(async () => {
      const current = notes().find((note) => note.id === snapshot.id);
      // Only the editor's own fields come from the page; anything changed meanwhile (a lock, say) stays.
      const latest = current
        ? {
            ...clean(current),
            title: snapshot.title,
            notes: snapshot.notes,
            photos: snapshot.photos,
            noteIcon: snapshot.noteIcon,
            listID: snapshot.listID,
            updatedAt: snapshot.updatedAt,
          }
        : snapshot;
      if (
        current &&
        current.title === snapshot.title &&
        current.notes === snapshot.notes &&
        (current.noteIcon || null) === snapshot.noteIcon &&
        JSON.stringify(current.photos || []) === JSON.stringify(snapshot.photos || []) &&
        (current.listID || null) === snapshot.listID
      )
        return;

      await saveTasks([latest]);
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
function bindNoteIcons() {
  const trigger = $("#change-note-icon"),
    picker = $("#note-icon-picker");
  const buttons = [...picker.querySelectorAll("[data-pick-note-icon]")];
  trigger.onclick = () => {
    openDialog(picker);
    (buttons.find((button) => button.dataset.pickNoteIcon === noteIconDraft) || buttons[0]).focus();
  };
  picker.querySelector("[data-close-note-icons]").onclick = () => picker.close();
  picker.addEventListener("close", () => $("#change-note-icon")?.focus());
  picker.onclick = (event) => {
    if (event.target === picker) picker.close();
  };
  buttons.forEach((button, index) => {
    button.onclick = () => {
      noteIconDraft = OrbitNotes.resolveIcon(button.dataset.pickNoteIcon).id;
      trigger.innerHTML = noteGlyph(noteIconDraft);
      trigger.title = "Change note icon (" + OrbitNotes.resolveIcon(noteIconDraft).name + ")";
      buttons.forEach((item) => item.setAttribute("aria-pressed", String(item === button)));
      document.querySelectorAll(".notes-nav-page, .note-card").forEach((row) => {
        if (row.dataset.openNote === noteID) row.querySelector(".doc-icon").outerHTML = noteGlyph(noteIconDraft);
      });
      picker.close();
      void saveNote();
    };
    button.onkeydown = (event) => {
      const steps = { ArrowRight: 1, ArrowLeft: -1, ArrowDown: 5, ArrowUp: -5 };
      if (!(event.key in steps) && !["Home", "End"].includes(event.key)) return;
      event.preventDefault();
      event.stopPropagation();
      const next =
        event.key === "Home"
          ? 0
          : event.key === "End"
            ? buttons.length - 1
            : (index + steps[event.key] + buttons.length) % buttons.length;
      buttons[next].focus();
    };
  });
}

/**
 * The chin: the line being typed never sits at the bottom edge of the window. When the caret comes
 * within about a sixth of the window of the bottom, the page scrolls so there is room below it.
 */
function keepCaretAboveChin() {
  const article = $(".note-page"),
    body = $("#note-body");
  if (!article || !body) return;
  const chin = Math.max(96, innerHeight * 0.16);
  // Measure the text itself (the page has a minimum height), in page coordinates.
  const contents = document.createRange();
  contents.selectNodeContents(body);
  const textBottom = (contents.getBoundingClientRect().bottom || body.getBoundingClientRect().top) + scrollY;
  article.classList.toggle("with-chin", textBottom > innerHeight - chin);
  const selection = getSelection();
  if (!selection.rangeCount || !body.contains(selection.anchorNode)) return;
  const range = selection.getRangeAt(0).cloneRange();
  range.collapse(false);
  let rect = range.getClientRects()[0] || range.getBoundingClientRect();
  if (!rect || (!rect.bottom && !rect.top)) {
    const node = selection.anchorNode;
    rect = (node.nodeType === 1 ? node : node.parentElement)?.getBoundingClientRect();
  }
  if (!rect) return;
  const over = rect.bottom - (innerHeight - chin);
  if (over > 0) window.scrollBy({ top: over, behavior: reducedMotion() ? "auto" : "smooth" });
}
function bindNoteEditor() {
  if (!$("#note-title")) return;
  OrbitNoteDocument.bind($("#note-body"));
  OrbitAutocorrect.attach($("#note-title"));
  OrbitAutocorrect.attach($("#note-body"));
  keepCaretAboveChin();
  resizeNoteFields();
  bindNotePhotos();
  bindNoteIcons();
  const later = () => {
    resizeNoteFields();
    clearTimeout(noteSaveTimer);

    noteSaveTimer = setTimeout(() => void saveNote(), 600);
  };
  $("#note-title").oninput = later;
  $("#note-body").oninput = () => {
    later();
    keepCaretAboveChin();
  };
  $("#note-body").addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === "ArrowDown" || event.key === "PageDown")
      requestAnimationFrame(keepCaretAboveChin);
  });
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
  // Photo, copy, make-it-a-task and lock live behind ⋯ so the page stays quiet.
  $("#note-more").onclick = (event) => {
    // The document's click handler closes menus; this click opens one.
    event.stopPropagation();
    if ($("#row-menu") && !$("#row-menu").hidden) return closeRowMenu();
    const box = $("#note-more").getBoundingClientRect();
    const current = notes().find((item) => item.id === noteID);
    const entries = [
      ["Add photo", () => $("#note-photo-file").click()],
      [
        "Copy text",
        () => {
          const title = $("#note-title").value.trim(),
            text = $("#note-body").value.trim();
          return api.copy([title, text].filter(Boolean).join("\n\n"));
        },
      ],
    ];
    if (current)
      entries.push(noteMoveEntry(current), ["Make it a Task", () => noteMenuToTask(current)], ...lockEntries(current));
    showMenu(entries, box.right - 180, box.bottom + 6);
  };
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
    (own.length ? `<div class="list-heading" data-sidebar-note-heading>Note sections</div>` : "") +
    own
      .map(
        (l) =>
          `<div class="sidebar-list" data-section-menu="${esc(l.id)}" data-note-drop="${esc(l.id)}"><button data-notes-section-link="${esc(l.id)}"><span class="list-dot ${colorName(l.color)}"></span>${esc(l.name)}</button><button data-edit-list="${esc(l.id)}" data-list-kind="notes" aria-label="Edit ${esc(l.name)} note section">⋯</button></div>`,
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
      unlockSelectedSection();
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
  bindNoteDrops();
}

/** Drag a page onto a section (in the notes list or the sidebar), or onto General, to move it there. */
function bindNoteDrops() {
  document.querySelectorAll("[data-drag-note]").forEach((page) => {
    page.ondragstart = (event) => {
      // The page, not its section group, is what moves.
      event.stopPropagation();
      event.dataTransfer.setData("text/orbit-note", page.dataset.dragNote);
      event.dataTransfer.effectAllowed = "move";
    };
  });
  document.querySelectorAll("[data-note-drop]").forEach((target) => {
    if (target.dataset.noteDropBound) return;
    target.dataset.noteDropBound = "1";
    target.addEventListener("dragover", (event) => {
      if (!event.dataTransfer.types.includes("text/orbit-note")) return;
      event.preventDefault();
      event.stopPropagation();
      event.dataTransfer.dropEffect = "move";
      target.classList.add("note-drop-target");
    });
    target.addEventListener("dragleave", (event) => {
      if (!target.contains(event.relatedTarget)) target.classList.remove("note-drop-target");
    });
    target.addEventListener("drop", (event) => {
      const id = event.dataTransfer.getData("text/orbit-note");
      target.classList.remove("note-drop-target");
      if (!id) return;
      event.preventDefault();
      event.stopPropagation();
      void moveNoteTo(id, target.dataset.noteDrop || null);
    });
  });
}

let listEditingKind = "notes";
function openList(id, kind = page === "tasks" ? "tasks" : "notes") {
  listEditingKind = kind;
  $("#list-delete-confirm").hidden = true;
  editingList = rows("lists").find((l) => l.id === id) || null;
  const f = $("#list-form");
  f.elements.name.value = editingList?.name || "";
  f.elements.color.value = editingList?.color || "sage";
  // Note sections can be locked from the start; categories hold tasks, which are never locked.
  $("#list-lock-row").hidden = listEditingKind !== "notes";
  f.elements.locked.checked = editingList?.locked === true;
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
  void saveListForm(f);
};
async function saveListForm(f) {
  const lockWanted = listEditingKind === "notes" && f.elements.locked.checked;
  const wasLocked = editingList?.locked === true;
  // Locking needs a password to exist; removing a lock needs it entered.
  if (lockWanted && !wasLocked && !(await OrbitLocks.ensurePassword())) return;
  if (!lockWanted && wasLocked && !(await OrbitLocks.unlock("Enter your password to unlock this section."))) return;
  await action(async () => {
    await put("lists", {
      ...(rows("lists").find((list) => list.id === editingList?.id) || {
        id: crypto.randomUUID(),
        sortOrder: rows("lists").length,
        kind: listEditingKind,
      }),
      name: f.elements.name.value.trim(),
      color: f.elements.color.value,
      ...(listEditingKind === "notes" ? { locked: lockWanted ? true : null } : {}),
      updatedAt: Date.now(),
    });
    $("#list-editor").close();
  });
}
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
    `${count} ${count === 1 ? "note is" : "notes are"} in this section. Move them to General, or delete them with the section.`;
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
  $("#note-more").addEventListener("mousedown", remember);
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
