// Task, habit, password and review dialogs. Their markup lives in index.html.
let afterCaptureSave = () => {};
let taskDraft = null,
  habitDraft = null;
/** Opens the task editor for an existing task, or a new one prefilled from `draft`. */
function openTask(id, date, draft = null, { expanded = false } = {}) {
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
    taskCategories()
      .map((l) => `<option value="${esc(l.id)}">${esc(l.name)}</option>`)
      .join("");
  f.elements.listID.value = source?.listID || selectedList || "";
  const text = editing ? OrbitNotes.withoutRepeat(source.title, source.notes) : source || {};
  f.elements.title.value = text.title || "";
  requestAnimationFrame(() => fitTitleField(f.elements.title));
  f.elements.notes.value = text.notes || "";
  f.elements.date.value = editing ? taskDate(editing) || "" : (date ?? (page === "today" ? today() : ""));
  f.elements.time.value = source?.hasTime && source.dueDate ? new Date(source.dueDate).toTimeString().slice(0, 5) : "";
  f.elements.progressTracking.checked = source?.progressTracking === true;
  f.elements.duration.value = (editing ?? source)?.durationMinutes || 60;
  f.elements.priority.value = editing?.priority || 0;
  $("#editor-title").textContent = editing ? "Edit Task" : "New Task";
  $("#delete-task").hidden = !editing;
  $("#move-task").hidden = !editing;
  $("#task-to-calendar").hidden = !editing || !(editing.localDate || (editing.hasTime && editing.dueDate));
  f.querySelectorAll("details.capture-options").forEach((section, index) => {
    section.open = expanded || (index === 0 && !editing && page === "calendar");
  });
  openDialog($("#editor"));
}

function updateTargetLabel() {
  const weekly = $("#habit-form").elements.frequency.value === "WEEKLY";
  $("#habit-target-label").textContent = weekly ? "Times a week" : "Times a day";
}
$("#habit-form").elements.frequency.onchange = updateTargetLabel;

/** A habit repeats towards a target; a counter just adds up, so it has no schedule or target to set. */
function updateHabitKind() {
  const form = $("#habit-form");
  const counter = form.elements.kind.value === "counter";
  $("#habit-schedule-fields").hidden = counter;
  form.elements.target.disabled = counter;
  $("#habit-kind-hint").hidden = !counter;
  $("#habit-editor-title").textContent = `${editingHabit ? "Edit" : "New"} ${counter ? "Counter" : "Habit"}`;
  $("#move-habit").hidden = !editingHabit || counter;
}
function habitPickers() {
  const form = $("#habit-form");
  $("#habit-kind-picker").innerHTML = macPicker(
    "habit-kind",
    "Type",
    [
      ["habit", "Habit"],
      ["counter", "Counter"],
    ],
    form.elements.kind.value,
  );
  $("#habit-frequency-picker").innerHTML = macPicker(
    "habit-frequency",
    "Repeats",
    [
      ["DAILY", "Daily"],
      ["WEEKDAYS", "Weekdays"],
      ["WEEKENDS", "Weekends"],
      ["WEEKLY", "Weekly"],
    ],
    form.elements.frequency.value,
  );
  $("#habit-colour-picker").innerHTML = macPicker(
    "habit-colour",
    "Colour",
    [
      ["sage", "Sage"],
      ["lavender", "Lavender"],
      ["clay", "Coral"],
      ["honey", "Honey"],
    ],
    form.elements.color.value,
    { swatches: true },
  );
  bindPickers(
    {
      "habit-kind": (value) => {
        form.elements.kind.value = value;
        updateHabitKind();
        habitPickers();
      },
      "habit-frequency": (value) => {
        form.elements.frequency.value = value;
        updateTargetLabel();
        habitPickers();
      },
      "habit-colour": (value) => {
        form.elements.color.value = value;
        habitPickers();
      },
    },
    form,
  );
}

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
  f.elements.kind.value = source && OrbitHabits.isCounter(source) ? "counter" : "habit";
  f.elements.color.value = editingHabit?.color || draft?.color || nextHabitColor();
  // Keep the iPhone's icon choice when editing; Windows uses text-only rows.
  f.elements.icon.value = source?.icon || "automatic";
  updateTargetLabel();
  habitPickers();
  $("#delete-habit").hidden = !editingHabit;
  updateHabitKind();
  openDialog($("#habit-editor"));
}

async function moveItem(entity, source) {
  await api.batch(OrbitConversions.convert(entity, source, rows("habit_logs"), today()));
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
// The saved task goes to the calendar; save first to send changed dates.
$("#task-to-calendar").onclick = (event) => {
  event.stopPropagation();
  const box = event.currentTarget.getBoundingClientRect();
  showMenu(calendarEntry(editing)[2], box.left, box.bottom + 6);
};
$("#move-task").onclick = () => action(() => moveItem("tasks", editing));

$("#habit-form").onsubmit = (e) => {
  e.preventDefault();
  const f = e.target;
  if (!f.elements.title.value.trim()) return;
  const counter = f.elements.kind.value === "counter";
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
      target: counter ? 1 : Number(f.elements.target.value),
      frequencyRule: counter ? OrbitHabits.COUNTER : f.elements.frequency.value,
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

/**
 * The task editor's title is a one-line field that grows to show a long title in full (a note made into
 * a task keeps all its words). Enter still saves; pasted line breaks become spaces.
 */
function fitTitleField(field) {
  field.style.height = "auto";
  field.style.height = field.scrollHeight + 2 + "px";
}
document.querySelectorAll("textarea.title-field").forEach((field) => {
  field.addEventListener("input", () => {
    if (/[\r\n]/.test(field.value)) field.value = field.value.replace(/\s*[\r\n]+\s*/g, " ");
    fitTitleField(field);
  });
  field.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
      event.preventDefault();
      field.form.requestSubmit();
    }
  });
});

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
/** The permanent Undo and Redo buttons at the top of the window, with what each would do as a tooltip. */
function updateHistoryButtons(history = {}) {
  const set = (button, enabled, label, keys) => {
    button.disabled = !enabled;
    button.title = `${label} (${keys})`;
    button.setAttribute("aria-label", label);
  };
  set($("#undo-button"), history.canUndo, history.undoLabel || "Undo", "Ctrl+Z");
  set($("#redo-button"), history.canRedo, history.redoLabel || "Redo", "Ctrl+Y");
}
$("#undo-button").onclick = () => action(() => api.undo());
$("#redo-button").onclick = () => action(() => api.redo());
function updateUndo(next) {
  updateHistoryButtons(next.history);
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

// Only a press and release on the backdrop dismisses; dragging text out of a field does not.
document.querySelectorAll("dialog").forEach((dialog) => {
  let outside = false;
  const onBackdrop = (event) => {
    const box = dialog.getBoundingClientRect();
    return (
      event.target === dialog &&
      (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom)
    );
  };
  dialog.addEventListener("pointerdown", (event) => {
    outside = onBackdrop(event);
  });
  dialog.addEventListener("pointerup", (event) => {
    if (outside && onBackdrop(event) && dialog.id !== "onboarding") dialog.close();
    outside = false;
  });
});
