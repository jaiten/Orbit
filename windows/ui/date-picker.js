// One date picker for the whole app. Every <input type="date"> becomes a quiet button showing the
// date ("Fri, Dec 4") that opens a small calendar: quick choices (Today, Tomorrow, Next week, In 2
// weeks), the month with arrows, and Clear for optional fields. The input stays in the form (hidden),
// so forms read and set `.value` as before; setting it updates the button. The calendar is a popover in
// the top layer, so it is never cut off by a dialog. Inputs added later (Settings rules) are picked up too.
const pickerKey = (date) =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
const pickerDate = (key) => new Date(`${key}T12:00:00`);
const pickerAddDays = (key, days) => {
  const date = pickerDate(key);
  date.setDate(date.getDate() + days);
  return pickerKey(date);
};
/** The same day a month away, kept inside that month (January 31 → February 28, not March 3). */
function pickerShiftMonth(key, months) {
  const date = pickerDate(key);
  const last = new Date(date.getFullYear(), date.getMonth() + months + 1, 0).getDate();
  return pickerKey(new Date(date.getFullYear(), date.getMonth() + months, Math.min(date.getDate(), last), 12));
}
const nativeValue = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value");
const pickerIcon =
  '<svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="5" width="16" height="15" rx="3"/><path d="M8 3v4M16 3v4M4 10h16"/></svg>';
const pickerClearIcon =
  '<svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m7 7 10 10M17 7 7 17"/></svg>';
let pickerCount = 0;

/** Turns one date input into the custom picker (once). */
function enhanceDateInput(input) {
  if (input.dataset.datePicker === "on") return;
  input.dataset.datePicker = "on";
  const id = `date-picker-${++pickerCount}`;
  const wrap = document.createElement("span");
  wrap.className = "date-picker";
  input.replaceWith(wrap);
  input.classList.add("date-picker-input");
  input.tabIndex = -1;
  input.setAttribute("aria-hidden", "true");
  const button = document.createElement("button");
  button.type = "button";
  button.className = "date-picker-button";
  button.setAttribute("aria-haspopup", "dialog");
  button.setAttribute("aria-expanded", "false");
  button.setAttribute("aria-controls", id);
  button.innerHTML = `${pickerIcon}<span></span>`;
  const clear = document.createElement("button");
  clear.type = "button";
  clear.className = "date-picker-clear";
  clear.innerHTML = pickerClearIcon;
  clear.setAttribute("aria-label", "Clear date");
  clear.title = "Clear";
  const popover = document.createElement("div");
  popover.id = id;
  popover.className = "date-popover";
  popover.setAttribute("popover", "auto");
  popover.setAttribute("role", "dialog");
  wrap.append(input, button, clear, popover);
  // The field's name for screen readers: its label's text, or what the form calls it.
  const labelText = () =>
    (input.closest("label")?.firstChild?.textContent || input.getAttribute("aria-label") || "Date").trim();
  popover.setAttribute("aria-label", `Choose ${labelText().toLowerCase()}`);

  let month = null;
  const refresh = () => {
    const value = nativeValue.get.call(input);
    const label = value
      ? pickerDate(value).toLocaleDateString([], {
          weekday: "short",
          month: "short",
          day: "numeric",
          ...(value.slice(0, 4) === today().slice(0, 4) ? {} : { year: "numeric" }),
        })
      : input.dataset.placeholder || "Choose a date";
    button.querySelector("span").textContent = label;
    button.setAttribute("aria-label", `${labelText()}: ${label}`);
    button.classList.toggle("empty", !value);
    clear.hidden = !value || input.required;
    button.disabled = input.disabled;
  };
  // Code that sets the input's value (an editor filling its form) updates the button too.
  Object.defineProperty(input, "value", {
    configurable: true,
    get: () => nativeValue.get.call(input),
    set: (value) => {
      nativeValue.set.call(input, value);
      refresh();
    },
  });
  input.form?.addEventListener("reset", () => setTimeout(refresh, 0));
  // A click on the field's label (or form validation) focuses the hidden input; hand that to the button.
  input.addEventListener("focus", () => button.focus({ preventScroll: true }));
  const choose = (value) => {
    nativeValue.set.call(input, value || "");
    refresh();
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
    if (popover.matches(":popover-open")) popover.hidePopover();
    button.focus({ preventScroll: true });
  };
  const place = () => {
    const box = button.getBoundingClientRect();
    const height = popover.offsetHeight || 340,
      width = popover.offsetWidth || 300;
    const below = innerHeight - box.bottom - 8;
    const top = below >= height || box.top < height ? box.bottom + 6 : box.top - height - 6;
    popover.style.setProperty("top", `${Math.max(8, Math.min(top, innerHeight - height - 8))}px`);
    popover.style.setProperty("left", `${Math.max(8, Math.min(box.left, innerWidth - width - 8))}px`);
  };
  const draw = (focusKey) => {
    const value = nativeValue.get.call(input),
      now = today();
    const first = pickerDate(month);
    const offset = (first.getDay() - weekStart + 7) % 7;
    const start = pickerAddDays(month, -offset);
    const weeks = Math.ceil((offset + new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate()) / 7);
    const names = Array.from({ length: 7 }, (_, index) =>
      pickerDate(pickerAddDays(start, index)).toLocaleDateString([], { weekday: "narrow" }),
    );
    const days = Array.from({ length: weeks * 7 }, (_, index) => {
      const key = pickerAddDays(start, index),
        date = pickerDate(key);
      const classes = [
        key === value ? "chosen" : "",
        key === now ? "today" : "",
        key < now ? "past" : "",
        key.slice(0, 8) !== month.slice(0, 8) ? "outside" : "",
      ].join(" ");
      const label = date.toLocaleDateString([], { weekday: "long", month: "long", day: "numeric", year: "numeric" });
      return `<button type="button" class="date-day ${classes}" data-pick-day="${key}" aria-label="${label}" aria-pressed="${key === value}" tabindex="${key === focusKey ? 0 : -1}">${date.getDate()}</button>`;
    }).join("");
    // Next week: the start of the coming week, never today.
    const nextWeek = pickerAddDays(now, (weekStart - pickerDate(now).getDay() + 7) % 7 || 7);
    const quick = [
      ["Today", now],
      ["Tomorrow", pickerAddDays(now, 1)],
      ["Next week", nextWeek],
      ["In 2 weeks", pickerAddDays(now, 14)],
    ]
      .map(
        ([name, key]) =>
          `<button type="button" class="date-quick ${key === value ? "chosen" : ""}" data-pick-day="${key}">${name}</button>`,
      )
      .join("");
    const title = first.toLocaleDateString([], { month: "long", year: "numeric" });
    popover.innerHTML = `<div class="date-quick-row">${quick}</div>
      <div class="date-month"><button type="button" class="date-arrow" data-pick-month="-1" aria-label="Previous month"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m15 6-6 6 6 6"/></svg></button><strong aria-live="polite">${title}</strong><button type="button" class="date-arrow" data-pick-month="1" aria-label="Next month"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg></button></div>
      <div class="date-grid" role="grid" aria-label="${title}">${names.map((name) => `<span class="date-weekday" aria-hidden="true">${name}</span>`).join("")}${days}</div>`;
    popover.querySelectorAll("[data-pick-day]").forEach((day) => {
      day.onclick = () => choose(day.dataset.pickDay);
    });
    popover.querySelectorAll("[data-pick-month]").forEach((arrow) => {
      arrow.onclick = () => {
        moveMonth(Number(arrow.dataset.pickMonth));
        popover.querySelector(`[data-pick-month="${arrow.dataset.pickMonth}"]`)?.focus({ preventScroll: true });
      };
    });
    popover.querySelector(`.date-day[data-pick-day="${focusKey}"]`)?.focus({ preventScroll: true });
  };
  const moveMonth = (delta, focusKey = null) => {
    month = pickerShiftMonth(month, delta);
    draw(focusKey);
  };
  // An auto popover closes itself on a click outside; a click on the button while it is open should
  // just close it, not close and reopen.
  let wasOpen = false;
  button.addEventListener("pointerdown", () => (wasOpen = popover.matches(":popover-open")));
  button.onclick = () => {
    if (wasOpen || popover.matches(":popover-open")) {
      wasOpen = false;
      if (popover.matches(":popover-open")) popover.hidePopover();
      return;
    }
    const value = nativeValue.get.call(input);
    month = (value || today()).slice(0, 8) + "01";
    draw(value || today());
    popover.showPopover();
    place();
    popover.querySelector(`.date-day[tabindex="0"]`)?.focus({ preventScroll: true });
  };
  popover.addEventListener("toggle", (event) => {
    button.setAttribute("aria-expanded", String(event.newState === "open"));
  });
  clear.onclick = () => choose("");
  popover.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      // Close the calendar only, not the dialog it sits in.
      event.preventDefault();
      event.stopPropagation();
      popover.hidePopover();
      button.focus({ preventScroll: true });
      return;
    }
    const day = event.target.closest?.(".date-day")?.dataset.pickDay;
    if (!day) return;
    const step = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 }[event.key];
    const months = { PageUp: -1, PageDown: 1 }[event.key];
    if (!step && !months) return;
    event.preventDefault();
    const next = step ? pickerAddDays(day, step) : pickerShiftMonth(day, months);
    if (next.slice(0, 8) !== month.slice(0, 8)) {
      const target = pickerDate(next),
        shown = pickerDate(month);
      moveMonth((target.getFullYear() - shown.getFullYear()) * 12 + target.getMonth() - shown.getMonth(), next);
    } else draw(next);
  });
  addEventListener("resize", () => popover.matches(":popover-open") && place());
  refresh();
}

/** Upgrades every date input under `root`. */
function enhanceDateInputs(root = document) {
  root.querySelectorAll?.('input[type="date"]:not([data-date-picker])').forEach(enhanceDateInput);
}
enhanceDateInputs();
new MutationObserver((mutations) => {
  for (const mutation of mutations)
    for (const node of mutation.addedNodes) {
      if (node.nodeType !== 1) continue;
      if (node.matches?.('input[type="date"]')) enhanceDateInput(node);
      else enhanceDateInputs(node);
    }
}).observe(document.body, { childList: true, subtree: true });
