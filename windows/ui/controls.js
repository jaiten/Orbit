// Compact, keyboard-accessible pickers with the same quiet menu surface as row actions.
function macPicker(id, label, options, value) {
  const selected = options.find(([key]) => key === value)?.[1] || label;
  return `<details class="mac-picker" data-picker="${id}"><summary id="${id}" role="combobox" aria-label="${esc(label)}" aria-haspopup="listbox" aria-controls="${id}-options" aria-expanded="false"><span>${esc(selected)}</span><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m8 10 4 4 4-4"/></svg></summary><div class="picker-menu" id="${id}-options" role="listbox" aria-label="${esc(label)}">${options.map(([key, name]) => `<button type="button" role="option" aria-selected="${key === value}" data-value="${esc(key)}"><span>${key === value ? "✓" : ""}</span>${esc(name)}</button>`).join("")}</div></details>`;
}
function bindPickers(handlers) {
  document.querySelectorAll("[data-picker]").forEach((picker) => {
    const summary = picker.querySelector("summary");
    const buttons = [...picker.querySelectorAll("[role=option]")];
    picker.ontoggle = () => {
      summary.setAttribute("aria-expanded", String(picker.open));
      if (picker.open)
        document.querySelectorAll(".mac-picker[open]").forEach((other) => {
          if (other !== picker) other.open = false;
        });
    };
    summary.onkeydown = (event) => {
      if (["ArrowDown", "ArrowUp"].includes(event.key)) {
        event.preventDefault();
        picker.open = true;
        (buttons.find((button) => button.getAttribute("aria-selected") === "true") || buttons[0])?.focus();
      }
    };
    buttons.forEach((button, index) => {
      button.onclick = () => {
        picker.open = false;
        handlers[picker.dataset.picker]?.(button.dataset.value);
        $("#" + summary.id)?.focus();
      };
      button.onkeydown = (event) => {
        if (event.key === "Escape") {
          event.preventDefault();
          event.stopPropagation();
          picker.open = false;
          summary.focus();
        }
        if (["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) {
          event.preventDefault();
          event.stopPropagation();
          const next =
            event.key === "Home"
              ? 0
              : event.key === "End"
                ? buttons.length - 1
                : (index + (event.key === "ArrowDown" ? 1 : -1) + buttons.length) % buttons.length;
          buttons[next].focus();
        }
      };
    });
  });
}
document.addEventListener("pointerdown", (event) => {
  document.querySelectorAll(".mac-picker[open]").forEach((picker) => {
    if (!picker.contains(event.target)) picker.open = false;
  });
});
let shortcutHintTimer;
function showShortcutHint() {
  const context = page === "note" || page === "lists" ? "notes" : page;
  const hints = {
    notes: ["Ctrl+N", "New note"],
    calendar: ["Ctrl+Shift+V", "Week / Month"],
    tasks: ["Ctrl+N", "Add a task"],
    habits: ["Ctrl+N", "Add a habit"],
  };
  const hint = hints[context],
    box = $("#shortcut-hint");
  clearTimeout(shortcutHintTimer);
  box.hidden = true;
  if (!hint) return;
  const key = "shortcutHintSeen:" + context,
    count = Number(localStorage.getItem(key) || 0);
  if (count >= 2) return;
  localStorage.setItem(key, String(count + 1));
  box.innerHTML = `<kbd>${hint[0]}</kbd><span>${hint[1]}</span>`;
  box.hidden = false;
  shortcutHintTimer = setTimeout(() => {
    box.hidden = true;
  }, 6000);
}

document.addEventListener("keydown", (event) => {
  if (event.key !== "Escape") return;
  const picker = document.querySelector(".mac-picker[open]");
  if (picker) {
    event.preventDefault();
    picker.open = false;
    picker.querySelector("summary").focus();
  }
});
