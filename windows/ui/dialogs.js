// Task, habit, password and review dialogs. Their markup lives in index.html.
let afterCaptureSave = () => {};
let taskDraft = null,
  habitDraft = null;
/** Opens the task editor for an existing task, or a new one prefilled from `draft`. */
function openTask(id, date, draft = null) {
  afterCaptureSave = () => {};
  $("#overlap-confirm").hidden = true;
  $("#task-form").dataset.allowOverlap = "";
  editing = rows("tasks").find((t) => t.id === id) || null;
  taskDraft = editing ? null : draft;
  const source = editing || draft;
  const f = $("#task-form");
  f.reset();
  f.elements.listID.innerHTML =
    `<option value="">No section</option><option value="${SOMEDAY}">Someday</option>` +
    rows("lists")
      .filter((l) => l.id !== SOMEDAY)
      .map((l) => `<option value="${esc(l.id)}">${esc(l.name)}</option>`)
      .join("");
  f.elements.listID.value = source?.listID || selectedList || "";
  f.elements.title.value = source?.title || "";
  f.elements.notes.value = source?.notes || "";
  f.elements.date.value = editing ? taskDate(editing) || "" : (date ?? (page === "today" ? selected : ""));
  f.elements.time.value = source?.hasTime && source.dueDate ? new Date(source.dueDate).toTimeString().slice(0, 5) : "";
  f.elements.progressTracking.checked = source?.progressTracking === true;
  f.elements.duration.value = editing?.durationMinutes || 30;
  f.elements.priority.value = editing?.priority || 0;
  $("#editor-title").textContent = editing ? "Edit Task" : "New Task";
  $("#delete-task").hidden = !editing;
  $("#move-task").hidden = !editing;
  $("#editor").showModal();
}

function updateTargetLabel() {
  const weekly = $("#habit-form").elements.frequency.value === "WEEKLY";
  $("#habit-target-label").textContent = weekly ? "Times a week" : "Times a day";
}
$("#habit-form").elements.frequency.onchange = updateTargetLabel;

function openHabit(id, draft = null) {
  afterCaptureSave = () => {};
  editingHabit = rows("habits").find((h) => h.id === id) || null;
  habitDraft = editingHabit ? null : draft;
  const source = editingHabit || draft;
  const f = $("#habit-form");
  f.reset();
  f.elements.title.value = source?.title || "";
  f.elements.target.value = source?.target || 1;
  f.elements.frequency.value = OrbitHabits.schedule(source || {});
  f.elements.color.value = editingHabit?.color || draft?.color || nextHabitColor();
  f.elements.icon.innerHTML =
    `<option value="automatic">Automatic</option>` +
    OrbitIcons.all
      .map((icon) => `<option value="${esc(icon.id)}">${esc(icon.glyph)} ${esc(icon.name)}</option>`)
      .join("");
  f.elements.icon.value = source?.icon || "automatic";
  if (!f.elements.icon.value) f.elements.icon.value = "automatic";
  updateTargetLabel();
  $("#habit-editor-title").textContent = editingHabit ? "Edit Habit" : "New Habit";
  $("#delete-habit").hidden = !editingHabit;
  $("#move-habit").hidden = !editingHabit;
  $("#habit-editor").showModal();
}

async function moveItem(entity, source) {
  await api.batch(OrbitConversions.convert(entity, source, rows("habit_logs"), dayKey(new Date())));
  $("#editor").close();
  $("#habit-editor").close();
}

document.querySelectorAll("[data-close]").forEach((b) => (b.onclick = () => b.closest("dialog").close()));

$("#task-form").onsubmit = (e) => {
  e.preventDefault();
  const f = e.target;
  if (!f.elements.title.value.trim()) return;
  action(async () => {
    const t = editing || taskDraft || newTask("", null);
    const due =
      f.elements.listID.value !== SOMEDAY && f.elements.date.value && f.elements.time.value
        ? new Date(`${f.elements.date.value}T${f.elements.time.value}`).getTime()
        : null;
    if (due !== null) {
      const end = due + (Number(f.elements.duration.value) || 30) * 60000;
      const overlaps = rows("tasks").filter(
        (other) =>
          other.id !== t.id &&
          other.hasTime &&
          other.dueDate &&
          !other.completedAt &&
          due < other.dueDate + other.durationMinutes * 60000 &&
          other.dueDate < end,
      );
      if (overlaps.length && f.dataset.allowOverlap !== "yes") {
        $("#overlap-confirm").hidden = false;
        $("#overlap-description").textContent = "Overlaps: " + overlaps.map((t) => t.title).join(", ");
        return;
      }
    }
    f.dataset.allowOverlap = "";
    const saved = {
      ...t,
      title: f.elements.title.value.trim(),
      notes: f.elements.notes.value,
      listID: f.elements.listID.value || null,
      localDate: f.elements.date.value || null,
      hasTime: due !== null,
      dueDate: due,
      progressTracking: f.elements.progressTracking.checked
        ? true
        : t.progressTracking === true
          ? false
          : t.progressTracking,
      startedAt: f.elements.progressTracking.checked ? t.startedAt : null,
      durationMinutes: Number(f.elements.duration.value) || 30,
      priority: Number(f.elements.priority.value),
      updatedAt: Date.now(),
    };
    // Someday items have no date and never remind.
    await saveTasks([saved.listID === SOMEDAY ? OrbitPlanner.moveToSomeday(saved) : saved]);
    afterCaptureSave();
    $("#editor").close();
  });
};
$("#save-overlap").onclick = () => {
  $("#task-form").dataset.allowOverlap = "yes";
  $("#task-form").requestSubmit();
};
$("#delete-task").onclick = () =>
  action(async () => {
    await put("tasks", editing, true);
    $("#editor").close();
  });
$("#move-task").onclick = () => action(() => moveItem("tasks", editing));

$("#habit-form").onsubmit = (e) => {
  e.preventDefault();
  const f = e.target;
  if (!f.elements.title.value.trim()) return;
  action(async () => {
    await put("habits", {
      ...(editingHabit || {
        id: crypto.randomUUID(),
        createdAt: Date.now(),
        icon: "leaf",
        reminderMinutes: habitDraft?.reminderMinutes ?? null,
        nudgeMinutes: null,
      }),
      title: f.elements.title.value.trim(),
      target: Number(f.elements.target.value),
      frequencyRule: f.elements.frequency.value,
      color: f.elements.color.value,
      icon: f.elements.icon.value,
      updatedAt: Date.now(),
    });
    afterCaptureSave();
    $("#habit-editor").close();
  });
};
$("#delete-habit").onclick = () =>
  action(async () => {
    const logs = rows("habit_logs").filter((l) => l.habitID === editingHabit.id);
    await api.batch([
      { key: editingHabit._key, payload: clean(editingHabit), deleted: true },
      ...logs.map((l) => ({ key: l._key, payload: clean(l), deleted: true })),
    ]);
    $("#habit-editor").close();
  });
$("#move-habit").onclick = () => action(() => moveItem("habits", editingHabit));

$("#password-form").onsubmit = (e) => {
  e.preventDefault();
  const f = e.target;
  if (f.elements.password.value !== f.elements.confirmation.value) {
    showNotice("Passwords do not match");
    return;
  }
  void action(async () => {
    showNotice(await api.auth("password", "", f.elements.password.value));
    f.reset();
    $("#password-editor").close();
  });
};

// The toast only appears for deletions, moves and imports. It springs up and fades in, and slides
// away the same way; Ctrl+Z undoes too.
let undoTimer, lastUndoCreated;
const UNDO_LABEL = { deleted: "Deleted", moved: "Moved", imported: "Imported" };
function showUndo(visible) {
  const box = $("#undo-toast");
  if (visible === !box.hidden && !box.classList.contains("leaving")) return;
  if (visible) {
    box.classList.remove("leaving");
    box.hidden = false;
    const { easing, duration } = spring("ui");
    box.animate(
      reducedMotion()
        ? [{ opacity: 0 }, { opacity: 1 }]
        : [
            { opacity: 0, transform: "translate(-50%, 24px) scale(0.96)" },
            { opacity: 1, transform: "translate(-50%, 0) scale(1)" },
          ],
      { duration: reducedMotion() ? 200 : duration, easing: reducedMotion() ? "ease-out" : easing },
    );
    return;
  }
  box.classList.add("leaving");
  const out = box.animate(
    reducedMotion()
      ? [{ opacity: 1 }, { opacity: 0 }]
      : [
          { opacity: 1, transform: "translate(-50%, 0)" },
          { opacity: 0, transform: "translate(-50%, 16px)" },
        ],
    { duration: 220, easing: "ease-in", fill: "forwards" },
  );
  out.onfinish = () => {
    if (!box.classList.contains("leaving")) return;
    box.classList.remove("leaving");
    box.hidden = true;
    out.cancel();
  };
}
function updateUndo(next) {
  if (!next.undoAvailable) {
    showUndo(false);
    return;
  }
  if (lastUndoCreated === next.undoCreatedAt) return;
  lastUndoCreated = next.undoCreatedAt;
  $("#undo-label").textContent = UNDO_LABEL[next.undoKind] || "Saved";
  showUndo(true);
  clearTimeout(undoTimer);
  undoTimer = setTimeout(() => showUndo(false), 8000);
}
$("#undo-change").onclick = () => action(() => api.undo());
$("#dismiss-undo").onclick = () => showUndo(false);
