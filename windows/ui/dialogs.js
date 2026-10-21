// Task, habit, password and review dialogs. Their markup lives in index.html.
let taskDraft = null,
  habitDraft = null;
/** Opens the task editor for an existing task, or a new one prefilled from `draft`. */
function openTask(id, date, draft = null) {
  $("#overlap-confirm").hidden = true;
  $("#task-form").dataset.allowOverlap = "";
  editing = rows("tasks").find((t) => t.id === id) || null;
  taskDraft = editing ? null : draft;
  const source = editing || draft;
  const f = $("#task-form");
  f.reset();
  f.elements.listID.innerHTML =
    `<option value="">Inbox</option><option value="${SOMEDAY}">Someday</option>` +
    rows("lists")
      .filter((l) => l.id !== SOMEDAY)
      .map((l) => `<option value="${esc(l.id)}">${esc(l.name)}</option>`)
      .join("");
  f.elements.listID.value = source?.listID || selectedList || "";
  f.elements.title.value = source?.title || "";
  f.elements.notes.value = source?.notes || "";
  f.elements.date.value = editing ? taskDate(editing) || "" : (date ?? (page === "today" ? selected : ""));
  f.elements.time.value = source?.hasTime && source.dueDate ? new Date(source.dueDate).toTimeString().slice(0, 5) : "";
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
  editingHabit = rows("habits").find((h) => h.id === id) || null;
  habitDraft = editingHabit ? null : draft;
  const source = editingHabit || draft;
  const f = $("#habit-form");
  f.reset();
  f.elements.title.value = source?.title || "";
  f.elements.target.value = source?.target || 1;
  f.elements.frequency.value = OrbitHabits.schedule(source || {});
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
      durationMinutes: Number(f.elements.duration.value) || 30,
      priority: Number(f.elements.priority.value),
      updatedAt: Date.now(),
    };
    // Someday items have no date and never remind.
    await saveTasks([saved.listID === SOMEDAY ? OrbitPlanner.moveToSomeday(saved) : saved]);
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
        color: "sage",
        icon: "leaf",
        reminderMinutes: habitDraft?.reminderMinutes ?? null,
        nudgeMinutes: null,
      }),
      title: f.elements.title.value.trim(),
      target: Number(f.elements.target.value),
      frequencyRule: f.elements.frequency.value,
      updatedAt: Date.now(),
    });
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

function openEveningReview() {
  const today = dayKey(new Date());
  const done = rows("tasks").filter((t) => t.completedAt && dayKey(new Date(t.completedAt)) === today).length;
  const habits = rows("habits").filter((h) => checked(h, today)).length;
  $("#review-summary").textContent =
    `${done} ${done === 1 ? "task" : "tasks"} completed · ${habits} ${habits === 1 ? "habit" : "habits"} checked`;
  $("#review-items").innerHTML = rows("tasks")
    .filter((t) => !t.completedAt && t.listID !== SOMEDAY)
    .map(
      (t) =>
        `<label class="review-item"><input type="checkbox" name="items" value="${esc(t.id)}">${esc(t.title)}</label>`,
    )
    .join("");
  $("#review-editor").showModal();
}
$("#review-form").onsubmit = (e) => {
  e.preventDefault();
  const ids = [...e.target.querySelectorAll("input:checked")].map((i) => i.value);
  if (ids.length > 3) {
    showNotice("Choose up to three priorities");
    return;
  }
  void action(async () => {
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    const day = dayKey(tomorrow);
    await api.batch(
      rows("tasks")
        .filter((t) => ids.includes(t.id))
        .map((t) => {
          let due = null;
          if (t.hasTime) {
            const clock = new Date(t.dueDate);
            due = new Date(day + "T12:00:00");
            due.setHours(clock.getHours(), clock.getMinutes(), 0, 0);
            due = due.getTime();
          }
          const reminders = t.reminders.map((r) => (due && t.dueDate ? r + (due - t.dueDate) : r));
          return {
            key: t._key,
            payload: { ...clean(t), localDate: day, dueDate: due, reminders, updatedAt: Date.now() },
          };
        }),
    );
    $("#review-editor").close();
  });
};

let undoTimer, lastUndoCreated;
function updateUndo(next) {
  const box = $("#undo-toast");
  if (!next.undoAvailable) {
    box.hidden = true;
    return;
  }
  if (lastUndoCreated === next.undoCreatedAt) return;
  lastUndoCreated = next.undoCreatedAt;
  box.hidden = false;
  clearTimeout(undoTimer);
  undoTimer = setTimeout(() => (box.hidden = true), 8000);
}
$("#undo-change").onclick = () => action(() => api.undo());
$("#dismiss-undo").onclick = () => ($("#undo-toast").hidden = true);
