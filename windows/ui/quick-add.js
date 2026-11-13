// The single Add entry point: header "+ Add", Ctrl+N and the tray.
// One text field; the chip shows what will be created before saving.
let quickContext = { defaultDate: null, listID: null };

function quickAddContext() {
  if (page === "tasks")
    return {
      defaultDate: ["week", "today"].includes(taskScope)
        ? today()
        : taskScope === "future"
          ? OrbitHabits.addDays(today(), 1)
          : "undated",
      listID: taskScope === "someday" ? SOMEDAY : selectedList,
    };
  if (page === "lists") return { defaultDate: "undated", listID: selectedList };
  if (page === "calendar" && calendarDay && calendarDay !== today()) return { defaultDate: calendarDay, listID: null };
  return { defaultDate: null, listID: null };
}

function openQuickAdd(context = quickAddContext()) {
  quickContext = context;
  const f = $("#quick-add-form");
  f.reset();
  f.elements.text.value = inlineDraft;
  updateQuickPreview();
  openDialog($("#quick-add-dialog"));
  if (page === "calendar") f.querySelector("details.capture-options")?.setAttribute("open", "");
  f.elements.text.focus();
}

function parseCapture(text, date) {
  const parsed = OrbitPlanning.parse(text, date, plannerNow());
  if (page === "habits" && parsed.kind !== "habit") return { ...parsed, kind: "habit", schedule: "DAILY" };
  return parsed;
}
function quickParse() {
  return parseCapture($("#quick-add-form").elements.text.value, quickContext.defaultDate);
}

function contextListName() {
  if (quickContext.listID === SOMEDAY) return "Someday";
  return rows("lists").find((l) => l.id === quickContext.listID)?.name ?? null;
}

function updateQuickPreview() {
  // Long text becomes a note here too; the dialog says so in its heading.
  const asNote = OrbitNotes.isNote($("#quick-add-form").elements.text.value);
  const eyebrow = $("#quick-add-form .eyebrow");
  if (eyebrow.textContent !== (asNote ? "New note" : "Quick add")) {
    eyebrow.textContent = asNote ? "New note" : "Quick add";
    if (!reducedMotion()) eyebrow.animate([{ opacity: 0, transform: "translateY(4px)" }, { opacity: 1 }], spring());
  }
  $("#quick-add-form").classList.toggle("note-form", asNote);
  if (asNote) return showChip($("#quick-add-preview"), "Note · Notes");
  const result = quickParse();
  let text = OrbitPlanning.describe(result, plannerNow(), undefined, { hour12: clockHour12() });
  const listName = contextListName();
  if (text && result.kind === "task" && !result.someday && !result.list && listName) text += " · " + listName;
  if (text && quickContext.listID === SOMEDAY && result.kind === "task" && !result.date) text = "Someday";
  const suggestion = text && suggestedCategory(result);
  if (suggestion) text += " · " + suggestion.name;
  showChip($("#quick-add-preview"), text);
}

/**
 * The chip says what will be created ("Task · Tomorrow · 6:00 PM"). Its segments fade in and out as
 * you type and its width springs, like the website. textContent stays the plain phrase for tests and
 * screen readers.
 */
function showChip(chip, text) {
  const before = chip.hidden ? 0 : chip.getBoundingClientRect().width;
  const old = [...chip.querySelectorAll(".part")].map((p) => p.dataset.part);
  chip.hidden = !text;
  chip.setAttribute("aria-label", text);
  chip.replaceChildren(
    ...text
      .split(" · ")
      .filter(Boolean)
      .flatMap((part, i) => {
        const span = document.createElement("span");
        span.className = "part";
        span.dataset.part = part;
        span.textContent = part;
        if (!old.includes(part) && !reducedMotion())
          span.animate(
            [
              { opacity: 0, transform: "translateY(6px)" },
              { opacity: 1, transform: "none" },
            ],
            spring("ui"),
          );
        if (i === 0) return [span];
        const dot = document.createElement("span");
        dot.className = "sep";
        dot.textContent = " · ";
        return [dot, span];
      }),
  );
  const after = chip.hidden ? 0 : chip.getBoundingClientRect().width;
  if (before && after && Math.abs(before - after) > 1 && !reducedMotion())
    chip.animate([{ width: before + "px" }, { width: after + "px" }], spring("ui"));
}

/** Finds a list by name (ignoring case) or prepares a new one. */
function listNamed(name) {
  const existing = rows("lists").find(
    (l) => l.id !== SOMEDAY && l.kind !== "notes" && l.name.toLowerCase() === name.toLowerCase(),
  );
  if (existing) return { id: existing.id, change: null };
  const list = {
    id: crypto.randomUUID(),
    name,
    kind: "tasks",
    color: "sage",
    sortOrder: rows("lists").length,
    updatedAt: Date.now(),
  };
  return { id: list.id, change: { key: "lists/" + list.id, payload: list } };
}

/** A category suggested from earlier tasks with similar titles, when nothing else files the task. */
function suggestedCategory(result, listID = quickContext.listID) {
  if (result.kind !== "task" || result.someday || result.list || listID || !result.title) return null;
  const categories = taskCategories();
  const known = new Set(categories.map((c) => c.id));
  const history = rows("tasks")
    .filter((t) => !t.isNote && known.has(t.listID))
    .map((t) => ({ title: t.title, category: t.listID }));
  const id = OrbitPlanner.suggestCategory(result.title, history);
  return categories.find((c) => c.id === id) || null;
}
/** Turns a parse result into records. Returns the created item for "More details…". */
function quickRecords(result) {
  const now = Date.now();
  if (result.kind === "habit") {
    const habit = {
      id: crypto.randomUUID(),
      title: result.title,
      frequencyRule: result.schedule,
      target: 1,
      color: nextHabitColor(),
      icon: "automatic",
      reminderMinutes: result.time,
      nudgeMinutes: null,
      createdAt: now,
      updatedAt: now,
    };
    return { habit, changes: [{ key: "habits/" + habit.id, payload: habit }] };
  }
  const extra = [];
  let listID = quickContext.listID;
  if (result.list) {
    const list = listNamed(result.list);
    listID = list.id;
    if (list.change) extra.push(list.change);
  }
  listID = listID || suggestedCategory(result, listID)?.id || null;
  if (result.someday) listID = SOMEDAY;
  if (listID === SOMEDAY && result.date) listID = null;
  const task = { ...newTask(result.title, result.date), listID };
  if (result.time !== null && result.date) {
    const due = new Date(result.date + "T00:00:00");
    due.setHours(Math.floor(result.time / 60), result.time % 60, 0, 0);
    Object.assign(task, { hasTime: true, dueDate: due.getTime() });
  }
  return { task, extra };
}

$("#quick-add-form").elements.text.oninput = updateQuickPreview;
$("#quick-add-form").onsubmit = (e) => {
  e.preventDefault();
  const text = $("#quick-add-form").elements.text.value;
  if (OrbitNotes.isNote(text)) {
    action(async () => {
      await saveTasks([{ ...newTask("", null), isNote: true, notes: text.trim() }]);
      inlineDraft = "";
      $("#quick-add-dialog").close();
    });
    return;
  }
  const result = quickParse();
  if (!result.title) return;
  action(async () => {
    const records = quickRecords(result);
    if (records.habit) await api.batch(records.changes);
    else await saveTasks([records.task], records.extra);
    inlineDraft = "";
    $("#quick-add-dialog").close();
  });
};
/**
 * The full editor for a capture: a habit, or a task with its date, time and options already open.
 * Used by "More details…" and by the calendar button beside the writing bar.
 */
function openCaptureDetails(text) {
  const result = parseCapture(text, quickContext.defaultDate);
  if (result.kind === "habit") {
    openHabit(null, { title: result.title, frequencyRule: result.schedule, reminderMinutes: result.time });
    afterCaptureSave = () => {
      inlineDraft = "";
    };
    return;
  }
  const { task } = quickRecords(result.title ? result : { ...result, title: "" });
  openTask(null, task.localDate ?? "", task, { expanded: true });
  afterCaptureSave = () => {
    inlineDraft = "";
  };
}
$("#quick-add-details").onclick = () => {
  const text = $("#quick-add-form").elements.text.value;
  $("#quick-add-dialog").close();
  openCaptureDetails(text);
};

// Preserve the current inline draft across sync renders and page changes.
let inlineDraft = "";
let inlineNoteTitle = "";
/** Outside Notes, a long capture becomes a note (Notes' own bar always writes one). */
const captureBecomesNote = (text) =>
  page !== "lists" && (OrbitNotes.isNote(text) || (!!inlineNoteTitle && !!String(text).trim()));
/** The header a capture grows when it becomes a note: where it goes, and an optional title. */
function captureNoteHead(visible) {
  const section = quickAddContext().listID;
  const name =
    section && rows("lists").some((l) => l.id === section && l.kind === "notes") ? sectionName(section) : "Notes";
  return `<div class="capture-note-head" ${visible ? "" : "hidden"}><span class="capture-note-where">${icon(ICONS.compose)}New note · ${esc(name)}</span><input id="inline-note-title" class="capture-note-title" placeholder="Title" aria-label="Note title" maxlength="500" value="${esc(inlineNoteTitle)}" tabindex="${visible ? 0 : -1}" /><span class="capture-note-hint">Ctrl+Enter to save</span></div>`;
}
/**
 * Switches the capture between a one-line task bar and a note card. The text field is never replaced,
 * so focus, the caret and typing carry straight on; the card unfolds around it with a spring, as if the
 * note page had been waiting underneath.
 */
function captureNoteMode(form, on) {
  if (form.classList.contains("note-form") === on) return;
  const field = form.querySelector(".add-field"),
    head = form.querySelector(".capture-note-head");
  const before = field.getBoundingClientRect().height;
  form.classList.toggle("note-form", on);
  head.hidden = !on;
  form.querySelector("#inline-note-title").tabIndex = on ? 0 : -1;
  form.querySelector("#inline-task-input").setAttribute("aria-label", on ? "Note text" : "New task");
  const after = field.getBoundingClientRect().height;
  if (reducedMotion() || Math.abs(after - before) < 2) return;
  field.animate([{ height: before + "px" }, { height: after + "px" }], {
    ...spring("ui"),
    easing: "cubic-bezier(.2,.9,.25,1.12)",
  });
  field.animate(
    on
      ? [{ boxShadow: "0 0 0 0 transparent", transform: "translateY(4px)" }, { transform: "none" }]
      : [{ transform: "translateY(-2px)" }, { transform: "none" }],
    { duration: 260, easing: "ease-out" },
  );
  if (on)
    head.animate(
      [
        { opacity: 0, transform: "translateY(10px)", filter: "blur(3px)" },
        { opacity: 1, transform: "none", filter: "none" },
      ],
      { duration: 300, delay: 40, easing: "cubic-bezier(.2,.8,.2,1)", fill: "backwards" },
    );
}
let inlineFocusGeneration = 0;
document.addEventListener(
  "pointerdown",
  (event) => {
    if (!event.target.closest("#inline-add-form")) inlineFocusGeneration++;
  },
  true,
);
function bindInlineCapture() {
  const form = $("#inline-add-form");
  if (!form) return;
  const input = $("#inline-task-input");
  let allowOverlap = false;
  const preview = () => {
    allowOverlap = false;
    $("#inline-overlap").hidden = true;
    inlineDraft = input.value;
    const parsed = parseCapture(inlineDraft, quickAddContext().defaultDate);
    const section = quickAddContext().listID;
    const asNote = captureBecomesNote(inlineDraft);
    captureNoteMode(form, asNote);
    form.classList.toggle("has-text", !!inlineDraft.trim());
    // On Notes, the bottom bar always writes a note; elsewhere the note card says so itself.
    const text =
      !inlineDraft.trim() || asNote
        ? ""
        : page === "lists"
          ? "Note · " + (section ? sectionName(section) : "Notes")
          : [
              OrbitPlanning.describe(parsed, plannerNow(), undefined, { hour12: clockHour12() }),
              suggestedCategory(parsed, quickAddContext().listID)?.name,
            ]
              .filter(Boolean)
              .join(" · ");
    showChip($("#inline-preview"), text);
    $("#inline-receipt").textContent = "";
  };
  input.oninput = preview;
  OrbitAutocorrect.attach(input);
  const title = $("#inline-note-title");
  OrbitAutocorrect.attach(title);
  title.oninput = () => {
    inlineNoteTitle = title.value;
  };
  title.onkeydown = (event) => {
    if (event.key === "Enter" && !event.isComposing) {
      event.preventDefault();
      if (event.ctrlKey) form.requestSubmit();
      else input.focus();
    } else if (event.key === "ArrowDown") {
      event.preventDefault();
      input.focus();
    }
  };
  // Return adds; Shift+Return starts a new line (which makes a note); Return on an empty field leaves it.
  // Once the capture is a note card, Return is a new line and Ctrl+Return saves.
  input.onkeydown = (event) => {
    if (event.key !== "Enter" || event.isComposing) return;
    if (form.classList.contains("note-form") && !event.ctrlKey) return;
    if (event.shiftKey && !event.ctrlKey) return;
    event.preventDefault();
    inlineFocusGeneration++;
    if (!input.value.trim()) input.blur();
    else form.requestSubmit();
  };
  preview();
  $("#inline-dictate").onclick = async () => {
    input.focus();
    try {
      await api.dictate();
      showNotice("Speak into Windows voice typing, then review your draft and press Enter to add it.");
    } catch (error) {
      showNotice(error.message);
    }
  };
  $("#inline-save-overlap").onclick = () => {
    allowOverlap = true;
    form.requestSubmit();
  };
  form.onsubmit = (event) => {
    event.preventDefault();
    const focusRequest = ++inlineFocusGeneration,
      capturePage = page;
    if (!input.value.trim()) return input.blur();
    if (page === "lists" || captureBecomesNote(input.value)) {
      const captured = input.value;
      const title = inlineNoteTitle.trim(),
        body = captured.trim();
      const note = { ...newTask(title, null), isNote: true, notes: body };
      // A note goes to the open note section, or to General; never into a task category.
      const section = quickAddContext().listID;
      note.listID = section && rows("lists").some((l) => l.id === section && l.kind !== "tasks") ? section : null;
      // Never write into a locked section without its password; the text stays in the field meanwhile.
      if (note.listID && OrbitLocks.sectionSealed(note.listID)) {
        void OrbitLocks.unlock().then((ok) => ok && form.requestSubmit());
        return;
      }
      // Clear immediately, keeping a snapshot until local persistence acknowledges it.
      // A second Return can dismiss capture while the first save is still finishing.
      input.value = "";
      inlineDraft = "";
      inlineNoteTitle = "";
      $("#inline-note-title").value = "";
      preview();
      void (async () => {
        try {
          await saveTasks([note]);
          await load(true);
        } catch (error) {
          const current = $("#inline-task-input");
          inlineNoteTitle ||= title;
          inlineDraft = [captured, current?.value].filter(Boolean).join("\n");
          if (current) {
            current.value = inlineDraft;
            current.dispatchEvent(new Event("input", { bubbles: true }));
          }
          showNotice(error.message);
        } finally {
          if (focusRequest === inlineFocusGeneration && capturePage === page) $("#inline-task-input")?.focus();
        }
      })();
      return;
    }
    const result = parseCapture(input.value, quickAddContext().defaultDate);
    if (!result.title) return;
    quickContext = quickAddContext();
    const records = quickRecords(result);
    if (!allowOverlap && records.task?.hasTime) {
      const start = records.task.dueDate,
        end = start + records.task.durationMinutes * 60000;
      const overlaps = rows("tasks").filter(
        (task) =>
          task.hasTime &&
          task.dueDate &&
          !task.completedAt &&
          start < task.dueDate + task.durationMinutes * 60000 &&
          task.dueDate < end,
      );
      if (overlaps.length) {
        $("#inline-overlap").hidden = false;
        $("#inline-overlap-text").textContent = "Overlaps: " + overlaps.map((task) => task.title).join(", ");
        return;
      }
    }
    form.querySelector('button[type="submit"]').disabled = true;
    void action(async () => {
      if (records.habit) await api.batch(records.changes);
      else await saveTasks([records.task], records.extra);
      inlineDraft = "";
    }).then(() => {
      const current = $("#inline-task-input");
      if (current) {
        if (focusRequest === inlineFocusGeneration && capturePage === page) current.focus();
        // No success message: the cleared field is the confirmation. Only failures are reported.
        $("#inline-receipt").textContent = inlineDraft ? "Could not add this item. Your draft is still here." : "";
      }
      $('#inline-add-form button[type="submit"]')?.removeAttribute("disabled");
    });
  };
}
