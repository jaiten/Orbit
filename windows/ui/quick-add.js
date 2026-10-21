// The single Add entry point: header "+ Add", Ctrl+N and the tray.
// One text field; the chip shows what will be created before saving.
let quickContext = { defaultDate: null, listID: null };

function quickAddContext() {
  if (page === "lists") return { defaultDate: "undated", listID: selectedList };
  if (page === "today" && selected !== today()) return { defaultDate: selected, listID: null };
  return { defaultDate: null, listID: null };
}

function openQuickAdd(context = quickAddContext()) {
  quickContext = context;
  const f = $("#quick-add-form");
  f.reset();
  updateQuickPreview();
  $("#quick-add-dialog").showModal();
  f.elements.text.focus();
}

function quickParse() {
  return OrbitPlanning.parse($("#quick-add-form").elements.text.value, quickContext.defaultDate);
}

function contextListName() {
  if (quickContext.listID === SOMEDAY) return "Someday";
  return rows("lists").find((l) => l.id === quickContext.listID)?.name ?? null;
}

function updateQuickPreview() {
  const result = quickParse();
  let text = OrbitPlanning.describe(result);
  const listName = contextListName();
  if (text && result.kind === "task" && !result.someday && !result.list && listName) text += " · " + listName;
  if (text && quickContext.listID === SOMEDAY && result.kind === "task" && !result.date) text = "Someday";
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
  const existing = rows("lists").find((l) => l.id !== SOMEDAY && l.name.toLowerCase() === name.toLowerCase());
  if (existing) return { id: existing.id, change: null };
  const list = { id: crypto.randomUUID(), name, color: "sage", sortOrder: rows("lists").length, updatedAt: Date.now() };
  return { id: list.id, change: { key: "lists/" + list.id, payload: list } };
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
      color: "sage",
      icon: "leaf",
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
  const result = quickParse();
  if (!result.title) return;
  action(async () => {
    const records = quickRecords(result);
    if (records.habit) await api.batch(records.changes);
    else await saveTasks([records.task], records.extra);
    $("#quick-add-dialog").close();
  });
};
$("#quick-add-details").onclick = () => {
  const result = quickParse();
  $("#quick-add-dialog").close();
  if (result.kind === "habit") {
    openHabit(null, { title: result.title, frequencyRule: result.schedule, reminderMinutes: result.time });
    return;
  }
  const { task } = quickRecords(result.title ? result : { ...result, title: "" });
  openTask(null, task.localDate ?? "", task);
};
