// Compact, keyboard-accessible pickers with the same quiet menu surface as row actions.
function macPicker(id, label, options, value, swatches = false) {
  const selected = options.find(([key]) => key === value)?.[1] || label;
  const swatch = (key) =>
    swatches && ["sage", "lavender", "clay", "honey"].includes(key)
      ? `<i class="colour-swatch swatch-${key}" aria-hidden="true"></i>`
      : "";
  return `<details class="mac-picker" data-picker="${id}"><summary id="${id}" role="combobox" aria-label="${esc(label)}" aria-haspopup="listbox" aria-controls="${id}-options" aria-expanded="false">${swatch(value)}<span>${esc(selected)}</span><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m8 10 4 4 4-4"/></svg></summary><div class="picker-menu" id="${id}-options" role="listbox" aria-label="${esc(label)}">${options.map(([key, name]) => `<button type="button" role="option" aria-label="${esc(name)}" aria-selected="${key === value}" data-value="${esc(key)}">${swatch(key)}${esc(name)}</button>`).join("")}</div></details>`;
}
function bindPickers(handlers, root = document) {
  root.querySelectorAll("[data-picker]").forEach((picker) => {
    const summary = picker.querySelector("summary");
    const buttons = [...picker.querySelectorAll("[role=option]")];
    const syncPicker = () => {
      summary.setAttribute("aria-expanded", String(picker.open));
      if (picker.open) {
        const menu = picker.querySelector(".picker-menu");
        picker.classList.remove("opens-up");
        menu.style.maxHeight = "";
        const box = summary.getBoundingClientRect();
        const below = Math.max(0, innerHeight - box.bottom - 12);
        const above = Math.max(0, box.top - 12);
        const upward = menu.scrollHeight > below && above > below;
        picker.classList.toggle("opens-up", upward);
        menu.style.maxHeight = `${Math.min(280, Math.max(80, upward ? above : below))}px`;
        document.querySelectorAll(".mac-picker[open]").forEach((other) => {
          if (other !== picker) other.open = false;
        });
      }
    };
    picker.ontoggle = syncPicker;
    summary.onclick = (event) => {
      event.preventDefault();
      picker.open = !picker.open;
      syncPicker();
    };
    summary.onkeydown = (event) => {
      if (["ArrowDown", "ArrowUp"].includes(event.key)) {
        event.preventDefault();
        picker.open = true;
        syncPicker();
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
