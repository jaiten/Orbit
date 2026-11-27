// The task editor's due date: a quiet button that opens a small calendar with quick choices
// (Today, Tomorrow, Next week, In 2 weeks), a month grid and Clear. The chosen day lives in the hidden
// `deadline` input, so saving reads it like any other field.
let duePickerMonth = null;
const dueKeyOf = (date) =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
const dueDateOf = (key) => new Date(`${key}T12:00:00`);
const dueAddDays = (key, days) => {
  const date = dueDateOf(key);
  date.setDate(date.getDate() + days);
  return dueKeyOf(date);
};

/** Shows the field's current value on the button (call after the editor fills or resets the form). */
function refreshDuePicker() {
  const input = $("#task-form").elements.deadline,
    button = $("#due-picker-button");
  const value = input.value;
  const label = value
    ? dueDateOf(value).toLocaleDateString([], {
        weekday: "short",
        month: "short",
        day: "numeric",
        ...(value.slice(0, 4) === today().slice(0, 4) ? {} : { year: "numeric" }),
      })
    : "No due date";
  button.querySelector("span").textContent = label;
  button.classList.toggle("empty", !value);
  $("#due-clear").hidden = !value;
  closeDuePicker();
}

function setDueDate(value) {
  $("#task-form").elements.deadline.value = value || "";
  refreshDuePicker();
  $("#due-picker-button").focus({ preventScroll: true });
}

function closeDuePicker() {
  const popover = $("#due-popover");
  if (popover.hidden) return;
  popover.hidden = true;
  $("#due-picker-button").setAttribute("aria-expanded", "false");
}

function openDuePicker() {
  const value = $("#task-form").elements.deadline.value;
  duePickerMonth = (value || today()).slice(0, 8) + "01";
  $("#due-popover").hidden = false;
  $("#due-picker-button").setAttribute("aria-expanded", "true");
  drawDuePicker(value || today());
  $("#due-popover").scrollIntoView({ block: "nearest", behavior: reducedMotion() ? "auto" : "smooth" });
}

/** The popover's contents: quick choices, the month with arrows, and the days (focus lands on `focusKey`). */
function drawDuePicker(focusKey) {
  const popover = $("#due-popover"),
    value = $("#task-form").elements.deadline.value,
    now = today();
  const first = dueDateOf(duePickerMonth);
  const offset = (first.getDay() - weekStart + 7) % 7;
  const start = dueAddDays(duePickerMonth, -offset);
  const weeks = Math.ceil((offset + new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate()) / 7);
  const names = Array.from({ length: 7 }, (_, index) =>
    dueDateOf(dueAddDays(start, index)).toLocaleDateString([], { weekday: "narrow" }),
  );
  const days = Array.from({ length: weeks * 7 }, (_, index) => {
    const key = dueAddDays(start, index),
      date = dueDateOf(key);
    const classes = [
      key === value ? "chosen" : "",
      key === now ? "today" : "",
      key < now ? "past" : "",
      key.slice(0, 8) !== duePickerMonth.slice(0, 8) ? "outside" : "",
    ].join(" ");
    const label = date.toLocaleDateString([], { weekday: "long", month: "long", day: "numeric", year: "numeric" });
    return `<button type="button" class="due-day ${classes}" data-due-day="${key}" aria-label="${label}" aria-pressed="${key === value}" tabindex="${key === focusKey ? 0 : -1}">${date.getDate()}</button>`;
  }).join("");
  // Next week: the coming Monday (or the week's first day), never today.
  const nextWeek = dueAddDays(now, (weekStart - dueDateOf(now).getDay() + 7) % 7 || 7);
  const quick = [
    ["Today", now],
    ["Tomorrow", dueAddDays(now, 1)],
    ["Next week", nextWeek],
    ["In 2 weeks", dueAddDays(now, 14)],
  ]
    .map(
      ([name, key]) =>
        `<button type="button" class="due-quick ${key === value ? "chosen" : ""}" data-due-day="${key}">${name}</button>`,
    )
    .join("");
  const month = first.toLocaleDateString([], { month: "long", year: "numeric" });
  popover.innerHTML = `<div class="due-quick-row">${quick}</div>
    <div class="due-month"><button type="button" class="due-arrow" data-due-month="-1" aria-label="Previous month"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m15 6-6 6 6 6"/></svg></button><strong aria-live="polite">${month}</strong><button type="button" class="due-arrow" data-due-month="1" aria-label="Next month"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg></button></div>
    <div class="due-grid" role="grid" aria-label="${month}">${names.map((name) => `<span class="due-weekday" aria-hidden="true">${name}</span>`).join("")}${days}</div>`;
  popover.querySelectorAll("[data-due-day]").forEach((button) => {
    button.onclick = () => setDueDate(button.dataset.dueDay);
  });
  popover.querySelectorAll("[data-due-month]").forEach((button) => {
    button.onclick = () => moveDueMonth(Number(button.dataset.dueMonth), null, button.dataset.dueMonth);
  });
  popover.querySelector(`.due-day[data-due-day="${focusKey}"]`)?.focus({ preventScroll: true });
}

function moveDueMonth(delta, focusKey = null, arrow = null) {
  const date = dueDateOf(duePickerMonth);
  duePickerMonth = dueKeyOf(new Date(date.getFullYear(), date.getMonth() + delta, 1));
  drawDuePicker(focusKey);
  if (arrow) $(`#due-popover [data-due-month="${arrow}"]`)?.focus({ preventScroll: true });
}

$("#due-picker-button").onclick = () => ($("#due-popover").hidden ? openDuePicker() : closeDuePicker());
$("#due-picker-button").onkeydown = (event) => {
  if (event.key !== "Escape" || $("#due-popover").hidden) return;
  event.preventDefault();
  event.stopPropagation();
  closeDuePicker();
};
$("#due-clear").onclick = () => setDueDate("");
// Arrow keys move through the days, Page Up/Down through months; Escape closes the calendar only.
$("#due-popover").addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    event.preventDefault();
    event.stopPropagation();
    closeDuePicker();
    $("#due-picker-button").focus({ preventScroll: true });
    return;
  }
  const day = event.target.closest?.(".due-day")?.dataset.dueDay;
  if (!day) return;
  const step = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 }[event.key];
  const months = { PageUp: -1, PageDown: 1 }[event.key];
  if (!step && !months) return;
  event.preventDefault();
  const next = step
    ? dueAddDays(day, step)
    : dueKeyOf(new Date(dueDateOf(day).setMonth(dueDateOf(day).getMonth() + months)));
  if (next.slice(0, 8) !== duePickerMonth.slice(0, 8)) {
    const target = dueDateOf(next),
      shown = dueDateOf(duePickerMonth);
    moveDueMonth((target.getFullYear() - shown.getFullYear()) * 12 + target.getMonth() - shown.getMonth(), next);
  } else drawDuePicker(next);
});
document.addEventListener("pointerdown", (event) => {
  if (!event.target.closest?.(".due-picker")) closeDuePicker();
});
