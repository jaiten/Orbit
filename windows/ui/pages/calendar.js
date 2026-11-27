// Month planning and scrollable day/week schedules share the same dated tasks and editor.
let calendarStart = null,
  calendarDay = null,
  calendarCompletedOpen = false,
  calendarScrollTop = 8 * 48;
const calendarTime = (stamp) =>
  new Date(stamp).toLocaleTimeString([], {
    hour: "numeric",
    minute: "2-digit",
    hour12: clockHour12(),
  });
/** Compact hour labels for the day and week grids: "8 AM" (or "08:00" with the 24-hour clock). */
const calendarHour = (hour) =>
  localStorage.getItem("calendarClock") === "24"
    ? `${String(hour).padStart(2, "0")}:00`
    : `${hour % 12 || 12} ${hour < 12 ? "AM" : "PM"}`;
const chevron = (path) => `<svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="${path}"/></svg>`;
const monthOf = (key) => key.slice(0, 8) + "01";
/** Events your iPhone shares through sync, with this PC's pending edits applied. */
// Google and Microsoft calendars linked on this PC (read in the main process; hidden ones aren't loaded).
const linked = () => state.linkedCalendars || { accounts: [], calendars: [], events: [] };
const calendarEvents = () => [...OrbitCalendarEvents.visible(rows("events"), rows("calendars")), ...linked().events];
const eventCalendar = (event) =>
  (event.provider ? linked().calendars : rows("calendars")).find((calendar) => calendar.id === event.calendarID);
const calendarColor = (event) => {
  const color = eventCalendar(event)?.color;
  return /^#[0-9a-f]{6}$/i.test(color || "") ? color : "var(--muted)";
};
/** An event's address on one line, for titles, tooltips and rows ("" when it has none). */
const eventPlace = (event) =>
  String(event.location || "")
    .replace(/\s*\n+\s*/g, ", ")
    .trim();
const eventTooltip = (event) => [event.title || "Event", eventPlace(event)].filter(Boolean).join(" · ");
const pinIcon = `<svg class="ui-icon pin" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 21s-6-5.3-6-11a6 6 0 0 1 12 0c0 5.7-6 11-6 11z"/><circle cx="12" cy="10" r="2.2"/></svg>`;
/** A shared event in the Any time row or the month grid: opens the event editor. */
function eventChip(event, withTime = false) {
  const time = withTime ? `<b>${event.allDay ? "All day" : calendarTime(event.start).replace(/:00(?= )/, "")}</b>` : "";
  // In the chosen day's list (withTime) the address shows under the title; elsewhere it is in the tooltip.
  const place =
    withTime && eventPlace(event) ? `<small class="event-place">${pinIcon}${esc(eventPlace(event))}</small>` : "";
  return `<button class="schedule-anytime calendar-event-chip${event.pending ? " pending" : ""}${place ? " has-place" : ""}${OrbitCalendarEvents.ended(event) ? " past" : ""}" data-event-color="${calendarColor(event)}" data-edit-event="${esc(event.id)}" title="${esc(eventTooltip(event))}"><i></i><span class="event-chip-text"><span>${esc(event.title || "Event")}</span>${place}</span>${time}</button>`;
}
/** The most items a month day draws; fitCalendarCells shows as many of them as its height allows. */
const CAL_CELL_MOST = 12;
/**
 * Each month day shows the items that fit its height and "N more" for the rest, so the month always
 * fits the window without a scrollbar: a tall window shows more per day, a short one fewer.
 */
function fitCalendarCells() {
  const cells = [...document.querySelectorAll(".cal-grid .cal-cell")];
  // Show everything, then read every position in one layout pass, then hide what doesn't fit.
  // (Hiding one item at a time and re-measuring forced a layout per item: slow on a busy month.)
  for (const cell of cells) {
    cell.querySelectorAll(".cal-item").forEach((item) => (item.hidden = false));
    const more = cell.querySelector(".cal-more");
    if (more) more.hidden = true;
  }
  const plans = cells.map((cell) => {
    const more = cell.querySelector(".cal-more");
    const items = [...cell.querySelectorAll(".cal-item")];
    if (!more) return null;
    const box = cell.getBoundingClientRect();
    const limit = box.bottom - (parseFloat(getComputedStyle(cell).paddingBottom) || 0);
    return { more, items, limit, bottoms: items.map((item) => item.getBoundingClientRect().bottom) };
  });
  // "N more" needs a line of its own (about 17px with the gap).
  const MORE_LINE = 17;
  for (const plan of plans) {
    if (!plan) continue;
    const { more, items, limit, bottoms } = plan;
    const total = Number(more.dataset.total) || 0;
    let shown = items.length;
    if (bottoms.length && bottoms[bottoms.length - 1] > limit + 0.5) {
      shown = 0;
      while (shown < items.length && bottoms[shown] + MORE_LINE <= limit + 0.5) shown++;
    }
    items.slice(shown).forEach((item) => (item.hidden = true));
    more.hidden = total <= shown;
    more.textContent = `${total - shown} more`;
  }
  // A narrow day says "+2" instead of cutting "2 more" short (one more read pass).
  const narrow = plans.filter((plan) => plan && !plan.more.hidden && plan.more.scrollWidth > plan.more.clientWidth + 1);
  for (const plan of narrow) plan.more.textContent = plan.more.textContent.replace(/^(\d+) more$/, "+$1");
}
let calendarCellsObserver = null;
function bindCalendarCells() {
  calendarCellsObserver?.disconnect();
  const grid = document.querySelector(".cal-grid");
  if (!grid) return;
  fitCalendarCells();
  calendarCellsObserver = new ResizeObserver(() => fitCalendarCells());
  calendarCellsObserver.observe(grid);
}
function shiftMonth(key, delta) {
  const date = localDay(key);
  return dayKey(new Date(date.getFullYear(), date.getMonth() + delta, 1));
}
function calendarHeader(title, subtitle) {
  const unit = calendarView === "month" ? "month" : calendarView === "week" ? "week" : "day";
  return `<header class="page-head"><div><div class="month-heading"><h1>${title}</h1></div><p class="subtitle">${subtitle}</p></div><div class="head-tools"><div class="month-arrows"><button class="icon-button" data-month="-1" aria-label="Previous ${unit}">${chevron("m15 6-6 6 6 6")}</button><button class="icon-button" data-month="1" aria-label="Next ${unit}">${chevron("m9 6 6 6-6 6")}</button></div><button class="today-button" data-month="0">Today</button>${scopeTabs()}</div></header>`;
}
function calendarCompleted(items) {
  if (!items.length) return "";
  return `<details id="calendar-completed" ${calendarCompletedOpen ? "open" : ""}><summary>Completed (${items.length})</summary><div class="check-list">${items.map(taskRow).join("")}</div></details>`;
}
function renderCalendar(tasks) {
  const current = today();
  calendarDay ??= current;
  calendarStart ??= monthOf(calendarDay);
  if (calendarView !== "month") return renderSchedule(tasks);
  const first = localDay(calendarStart),
    start = OrbitHabits.weekStartKey(calendarStart, weekStart);
  const days = Array.from(
    {
      length:
        Math.ceil(
          (new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate() + ((first.getDay() - weekStart + 7) % 7)) /
            7,
        ) * 7,
    },
    (_, index) => OrbitHabits.addDays(start, index),
  );
  // Someday tasks with an @tag show on the days one of their rules matches.
  const ruled = somedayMatcher(tasks);
  const on = (key) =>
    [...tasks.filter((task) => taskDate(task) === key), ...ruled(key)].sort(
      (a, b) => !!a.completedAt - !!b.completedAt || (a.dueDate || 0) - (b.dueDate || 0),
    );
  const dueOn = (key) =>
    tasks.filter((task) => !task.isNote && !task.completedAt && task.deadline === key && taskDate(task) !== key);
  const shared = calendarEvents();
  const eventsOn = (key) => [
    ...OrbitCalendarEvents.allDayOn(shared, key),
    ...OrbitCalendarEvents.timedOn(shared, key).map((item) => item.event),
  ];
  const month = first.toLocaleDateString([], { month: "long", year: "numeric" });
  const count = tasks.filter((task) => monthOf(taskDate(task) || "") === calendarStart).length;
  const weekday = days
    .slice(0, 7)
    .map((key) => `<span>${localDay(key).toLocaleDateString([], { weekday: "short" })}</span>`)
    .join("");
  const cells = days
    .map((key) => {
      const date = localDay(key),
        items = on(key),
        dayEvents = eventsOn(key);
      // Every item is drawn (up to a dozen); fitCalendarCells then hides the ones that don't fit the
      // day's height and says how many more there are.
      const eventLines = dayEvents
        .slice(0, CAL_CELL_MOST)
        .map((event) => {
          const time = event.allDay
            ? ""
            : calendarTime(event.start)
                .replace(/:00(?= )/, "")
                .replace(" ", "")
                .toLowerCase();
          return `<span class="cal-item cal-event${OrbitCalendarEvents.ended(event) ? " past" : ""}" data-event-color="${calendarColor(event)}" title="${esc(eventTooltip(event))}"><i></i>${time ? `<b>${time}</b>` : ""}<em>${esc(event.title || "Event")}</em></span>`;
        })
        .join("");
      const total = items.length + dayEvents.length + dueOn(key).length;
      const lines =
        eventLines +
        items
          .slice(0, Math.max(0, CAL_CELL_MOST - dayEvents.length))
          .map((task) => {
            const time = task.hasTime ? calendarTime(task.dueDate) : "";
            // Open tasks can be dragged to another day.
            const drag =
              task.completedAt || task.listID === SOMEDAY ? "" : ` draggable="true" data-drag-task="${esc(task.id)}"`;
            return `<span class="cal-item ${task.completedAt ? "done" : ""} ${task.listID === SOMEDAY ? "ruled" : ""}"${drag}><i></i>${
              time
                ? `<b>${time
                    .replace(/:00(?= )/, "")
                    .replace(" ", "")
                    .toLowerCase()}</b>`
                : ""
            }<em>${esc(task.title)}</em></span>`;
          })
          .join("");
      // A flag on the day an open task is due (when it isn't planned that same day).
      const dueLines = dueOn(key)
        .map(
          (task) =>
            `<span class="cal-item cal-due" draggable="true" data-drag-task="${esc(task.id)}" title="${esc(task.title)} is due"><i></i><b>Due</b><em>${esc(task.title)}</em></span>`,
        )
        .join("");
      const label = date.toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" });
      return `<button class="day-tile cal-cell ${key === calendarDay ? "selected" : ""} ${key === current ? "today" : ""} ${date.getMonth() !== first.getMonth() ? "outside" : ""}" data-day="${key}" aria-pressed="${key === calendarDay}" aria-label="${label}${total ? `, ${total} ${total === 1 ? "item" : "items"}` : ""}"><span class="cal-date">${date.getDate()}</span>${dueLines}${lines}<span class="cal-more" data-total="${total}" ${total > CAL_CELL_MOST ? "" : "hidden"}>${Math.max(0, total - CAL_CELL_MOST)} more</span></button>`;
    })
    .join("");
  const chosen = localDay(calendarDay),
    heading = calendarDay === current ? "Today" : chosen.toLocaleDateString([], { weekday: "long" });
  const items = on(calendarDay),
    open = items.filter((task) => !task.completedAt),
    completed = items.filter((task) => task.completedAt);
  return `<div class="calendar-page">${calendarHeader(month, count ? `${count} ${count === 1 ? "item" : "items"} this month` : "Nothing planned this month yet")}<div class="cal-layout"><div class="cal-month"><div class="cal-weekdays" aria-hidden="true">${weekday}</div><div class="day-tiles cal-grid" role="group" aria-label="Days">${cells}</div></div><aside class="cal-day card" aria-label="${heading}"><div class="cal-day-head"><h2>${heading}</h2><span>${chosen.toLocaleDateString([], { month: "long", day: "numeric" })}</span></div>${
    eventsOn(calendarDay).length
      ? `<div class="cal-day-events">${eventsOn(calendarDay)
          .sort((a, b) => !!b.allDay - !!a.allDay || (a.start || 0) - (b.start || 0))
          .map((event) => eventChip(event, true))
          .join("")}</div>`
      : ""
  }<div class="check-list">${open.map(taskRow).join("") || (eventsOn(calendarDay).length ? "" : '<p class="empty">Nothing planned. Type to add a task.</p>')}</div>${calendarCompleted(completed)}</aside></div><div class="capture-dock">${addField(calendarDay === current ? "Add to today" : "Add to " + heading)}</div></div>`;
}
function renderSchedule(tasks) {
  const dayView = calendarView === "day";
  const start = dayView ? calendarDay : OrbitHabits.weekStartKey(calendarDay, weekStart);
  const days = Array.from({ length: dayView ? 1 : 7 }, (_, index) => OrbitHabits.addDays(start, index));
  const items = tasks.filter((task) => days.includes(taskDate(task)));
  // Completed tasks stay out of the week and day views, so the page never scrolls past the grid.
  const open = items.filter((task) => !task.completedAt);
  const date = localDay(calendarDay),
    title = dayView
      ? date.toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" })
      : date.toLocaleDateString([], { month: "long", year: "numeric" });
  const subtitle = dayView
    ? `${items.length} ${items.length === 1 ? "task" : "tasks"}`
    : `${localDay(days[0]).toLocaleDateString([], { month: "short", day: "numeric" })} – ${localDay(days[6]).toLocaleDateString([], { month: "short", day: "numeric" })}`;
  const headings = days
    .map(
      (key) =>
        `<button class="day-tile ${key === calendarDay ? "selected" : ""}" data-day="${key}" aria-label="${localDay(key).toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" })}"><span>${localDay(key).toLocaleDateString([], { weekday: "short" })}</span><strong>${localDay(key).getDate()}</strong></button>`,
    )
    .join("");
  // Any time holds all-day calendar events only; tasks without a time stay on Today and in Tasks.
  // It grows to fit the busiest day (22px labels, 2px apart, 4px padding above and below).
  const shared = calendarEvents();
  const anytimeMost = Math.max(0, ...days.map((key) => OrbitCalendarEvents.allDayOn(shared, key).length));
  const anytimeHeight = Math.max(30, anytimeMost * 24 + 6);
  const untimed = days
    .map(
      (key) =>
        `<div class="schedule-all-day-column" data-anytime-day="${key}"><button class="schedule-all-day-add" data-add-day="${key}" aria-label="Add an untimed task on ${key}">${chevron("M12 5v14M5 12h14")}</button>${OrbitCalendarEvents.allDayOn(
          shared,
          key,
        )
          .map((event) => eventChip(event))
          .join("")}</div>`,
    )
    .join("");
  const axis = Array.from({ length: 24 }, (_, hour) => `<div>${hour ? calendarHour(hour) : ""}</div>`).join("");
  const columns = days
    .map((key) => {
      const slots = Array.from({ length: 96 }, (_, index) => {
        const time = `${String(Math.floor(index / 4)).padStart(2, "0")}:${String((index % 4) * 15).padStart(2, "0")}`;
        return `<button class="time-slot ${index % 4 ? "half-hour" : ""}" data-time-slot="${key}T${time}" aria-label="Add task on ${key} at ${time}"></button>`;
      }).join("");
      const blocks = OrbitCalendarLayout.place([
        ...open.filter((task) => taskDate(task) === key && task.hasTime),
        ...OrbitCalendarEvents.timedOn(shared, key),
      ])
        .map(({ task, start, end, lane, lanes }) =>
          task.event
            ? `<button class="schedule-event calendar-event${task.event.pending ? " pending" : ""}${OrbitCalendarEvents.ended(task.event) ? " past" : ""}" data-event-color="${calendarColor(task.event)}" data-edit-event="${esc(task.event.id)}" data-event-start="${start}" data-event-end="${end}" data-lane="${lane}" data-lanes="${lanes}" title="${esc(eventTooltip(task.event))}"><strong>${esc(task.event.title || "Event")}</strong><span>${calendarTime(task.event.start)}</span>${eventPlace(task.event) ? `<span class="event-place">${pinIcon}${esc(eventPlace(task.event))}</span>` : ""}</button>`
            : `<div draggable="true" data-drag-task="${esc(task.id)}" class="schedule-event check-tile" data-event-start="${start}" data-event-end="${end}" data-lane="${lane}" data-lanes="${lanes}" data-row-menu="task:${esc(task.id)}"><button class="schedule-check" role="checkbox" aria-checked="false" aria-label="Complete ${esc(task.title)}" data-toggle="${esc(task.id)}">${tick(false)}</button><button class="schedule-event-body" data-edit="${esc(task.id)}" aria-label="Edit ${esc(task.title)}" title="${esc(task.title)}"><strong>${esc(task.title)}</strong><span>${calendarTime(task.dueDate)}</span></button><button class="calendar-resize" data-resize-task="${esc(task.id)}" aria-label="Change duration of ${esc(task.title)}" title="Drag to change duration; arrow keys adjust by 15 minutes"></button>${rowActions(esc(task.id), esc(task.title))}</div>`,
        )
        .join("");
      // A line at the current time across today's column, as in Calendar.
      const now = new Date();
      const nowLine =
        key === dayKey(now)
          ? `<div class="now-line" data-now-top="${((now.getHours() * 60 + now.getMinutes()) / 15) * 12}" aria-hidden="true"></div>`
          : "";
      return `<div class="schedule-day ${key === dayKey(now) && !dayView ? "is-today" : ""}"><div class="schedule-slots">${slots}</div>${blocks}${nowLine}</div>`;
    })
    .join("");
  return `<div class="calendar-page timeline-page">${calendarHeader(title, subtitle)}<div id="calendar-timeline" class="calendar-timeline${dayView ? " day-view" : ""}" data-anytime-height="${anytimeHeight}"><div class="schedule-header time-grid"><span></span>${headings}</div><div class="schedule-all-day time-grid"><span class="time-axis-label">Any time</span>${untimed}</div><div class="anytime-resizer" aria-hidden="true"></div><div class="schedule-hours time-grid"><div class="time-axis">${axis}</div>${columns}</div></div><div class="capture-dock">${addField("Add a task for " + date.toLocaleDateString([], { month: "short", day: "numeric" }))}</div></div>`;
}
/**
 * The red line at the current time in today's column: 48px an hour, like the time axis. Its place is set
 * from here (inline styles are blocked) and moves on with the clock while the week or day is open.
 */
let nowLineTimer = null;
function placeNowLine(root = document) {
  const now = new Date();
  root.querySelectorAll(".now-line").forEach((line) => {
    line.style.top = `${((now.getHours() * 60 + now.getMinutes()) * 48) / 60}px`;
  });
  clearTimeout(nowLineTimer);
  if (root.querySelector?.(".now-line"))
    nowLineTimer = setTimeout(
      () => $("#calendar-timeline") && placeNowLine($("#calendar-timeline")),
      60000 - (now.getSeconds() * 1000 + now.getMilliseconds()),
    );
}
/** Inline styles are blocked by the page's security policy, so colours and sizes are set from here. */
function applyCalendarStyles(root = document) {
  root
    .querySelectorAll("[data-event-color]")
    .forEach((item) => item.style.setProperty("--event-color", item.dataset.eventColor));
  root
    .querySelectorAll("[data-anytime-height]")
    .forEach((item) => item.style.setProperty("--anytime-height", `${item.dataset.anytimeHeight}px`));
}
// The task being dragged in Calendar (a drag's own data cannot be read until it is dropped).
let draggedTask = null;
function bindCalendar() {
  applyCalendarStyles();
  bindCalendarCells();
  if ($("#calendar-completed"))
    $("#calendar-completed").ontoggle = (event) => {
      calendarCompletedOpen = event.target.open;
    };
  document.querySelectorAll("[data-scope]").forEach(
    (button) =>
      (button.onclick = () => {
        calendarView = button.dataset.scope;
        render();
        $(`[data-scope="${calendarView}"]`)?.focus();
      }),
  );
  document.querySelectorAll("[data-edit-event]").forEach((button) => {
    button.onclick = (event) => {
      event.stopPropagation();
      openEvent(button.dataset.editEvent);
    };
  });
  document.querySelectorAll("[data-day]").forEach((button) => {
    button.onclick = (event) => {
      calendarDay = button.dataset.day;
      // "3 more" opens that day on its own, with everything in it.
      if (event.target.closest?.(".cal-more")) {
        calendarView = "day";
      }
      calendarCompletedOpen = false;
      calendarStart = monthOf(calendarDay);
      render();
    };
    button.ondblclick = () => openQuickAdd({ defaultDate: button.dataset.day, listID: null });
  });
  // Clicking an empty spot in Any time (or its +) starts typing a task for that day; Return adds it,
  // Escape or clicking away cancels.
  const typeAnytime = (column) => {
    if (column.querySelector(".anytime-input")) return column.querySelector(".anytime-input").focus();
    const input = document.createElement("input");
    input.className = "anytime-input";
    input.placeholder = "New task";
    input.setAttribute("aria-label", "New task on " + column.dataset.anytimeDay);
    input.maxLength = 500;
    column.append(input);
    input.focus();
    // Leaving the field lets any queued render (including the new task) through.
    const finish = () => input.remove();
    input.onkeydown = (event) => {
      if (event.key === "Escape") finish();
      if (event.key !== "Enter" || event.isComposing) return;
      event.preventDefault();
      const result = parseCapture(input.value, column.dataset.anytimeDay);
      if (!result.title) return finish();
      quickContext = { defaultDate: column.dataset.anytimeDay, listID: null };
      const records = quickRecords(result);
      finish();
      void action(() => (records.habit ? api.batch(records.changes) : saveTasks([records.task], records.extra))).then(
        () => {
          // Any time lists all-day events only, so say where the new task went.
          if (!records.habit && !records.task.hasTime)
            showNotice(
              `Added for ${localDay(column.dataset.anytimeDay).toLocaleDateString([], { weekday: "long", month: "short", day: "numeric" })}. It's on Today and in Tasks.`,
              { dismissAfter: 3500 },
            );
        },
      );
    };
    input.onblur = () => setTimeout(finish, 0);
  };
  document.querySelectorAll("[data-anytime-day]").forEach((column) => {
    column.onclick = (event) => {
      if (event.target.closest(".schedule-anytime, .anytime-input")) return;
      event.preventDefault();
      typeAnytime(column);
    };
  });
  // A new task at a time, as in Google Calendar: hovering an empty slot shows an hour from there;
  // click to start it, or drag to choose how long it runs (15-minute steps).
  const slotDate = (key, slot) =>
    new Date(`${key}T${String(Math.floor(slot / 4)).padStart(2, "0")}:${String((slot % 4) * 15).padStart(2, "0")}:00`);
  const createAt = (key, slot, slots = 4) => {
    calendarDay = key;
    openTask(null, key, {
      ...newTask("", key),
      hasTime: true,
      dueDate: slotDate(key, slot).getTime(),
      localDate: null,
      durationMinutes: slots * 15,
    });
    $("#task-form [name=title]").focus();
  };
  document.querySelectorAll("[data-time-slot]").forEach((button) => {
    // Keyboard only (Enter/Space on a focused slot); the pointer goes through the column below.
    button.onclick = (event) => {
      if (event.detail !== 0) return;
      const [key, time] = button.dataset.timeSlot.split("T");
      const [hours, minutes] = time.split(":").map(Number);
      createAt(key, hours * 4 + minutes / 15);
    };
  });
  document.querySelectorAll(".schedule-day").forEach((column) => {
    const first = column.querySelector("[data-time-slot]");
    if (!first) return;
    const key = first.dataset.timeSlot.split("T")[0];
    const ghost = document.createElement("div");
    ghost.className = "slot-ghost";
    ghost.hidden = true;
    ghost.setAttribute("aria-hidden", "true");
    column.append(ghost);
    const slotAt = (y) => Math.max(0, Math.min(95, Math.floor((y - column.getBoundingClientRect().top) / 12)));
    const time = (slot) =>
      slot >= 96 ? calendarTime(slotDate(key, 95).getTime() + 15 * 60000) : calendarTime(slotDate(key, slot));
    const show = (start, end) => {
      ghost.hidden = false;
      ghost.style.top = `${start * 12}px`;
      ghost.style.height = `${(end - start) * 12 - 2}px`;
      ghost.textContent = `${time(start)} – ${time(end)}`;
    };
    let drag = null;
    column.onpointermove = (event) => {
      if (drag) {
        drag.end = Math.max(drag.start + 1, Math.min(96, slotAt(event.clientY) + 1));
        drag.moved = true;
        return show(drag.start, drag.end);
      }
      if (!event.target.closest("[data-time-slot]")) return void (ghost.hidden = true);
      const start = slotAt(event.clientY);
      show(start, Math.min(96, start + 4));
    };
    column.onpointerleave = () => {
      if (!drag) ghost.hidden = true;
    };
    column.onpointerdown = (event) => {
      if (event.button !== 0 || !event.target.closest("[data-time-slot]")) return;
      event.preventDefault();
      const start = slotAt(event.clientY);
      drag = { start, end: Math.min(96, start + 4), moved: false };
      column.setPointerCapture(event.pointerId);
      show(drag.start, drag.end);
    };
    column.onpointerup = () => {
      if (!drag) return;
      const { start, end, moved } = drag;
      drag = null;
      ghost.hidden = true;
      createAt(key, start, moved ? end - start : 4);
    };
    column.onpointercancel = () => {
      drag = null;
      ghost.hidden = true;
    };
    // A task dragged over the day outlines the time it would take there, for as long as it runs.
    column.addEventListener("dragover", (event) => {
      if (!draggedTask) return;
      const start = slotAt(event.clientY);
      show(start, Math.min(96, start + Math.max(1, Math.round((draggedTask.durationMinutes || 60) / 15))));
    });
    column.addEventListener("dragleave", (event) => {
      if (!column.contains(event.relatedTarget)) ghost.hidden = true;
    });
    column.addEventListener("drop", () => (ghost.hidden = true));
  });
  const endTaskDrag = () => {
    draggedTask = null;
    document.body.classList.remove("dragging-task");
    document.querySelectorAll(".drag-source").forEach((block) => block.classList.remove("drag-source"));
    document.querySelectorAll(".drop-target").forEach((target) => target.classList.remove("drop-target"));
    document.querySelectorAll(".slot-ghost").forEach((ghost) => (ghost.hidden = true));
  };
  document.querySelectorAll("[data-drag-task]").forEach((block) => {
    block.ondragstart = (event) => {
      event.dataTransfer.setData("text/orbit-task", block.dataset.dragTask);
      event.dataTransfer.effectAllowed = "move";
      draggedTask = rows("tasks").find((item) => item.id === block.dataset.dragTask) || null;
      // Once the picture that follows the pointer has been taken, dim the original and let the grid
      // underneath other blocks receive the drag.
      setTimeout(() => {
        if (!draggedTask) return;
        block.classList.add("drag-source");
        document.body.classList.add("dragging-task");
      }, 0);
    };
    block.ondragend = endTaskDrag;
  });
  document.querySelectorAll("[data-resize-task]").forEach((handle) => {
    const task = rows("tasks").find((item) => item.id === handle.dataset.resizeTask);
    if (!task) return;
    const startDate = new Date(task.dueDate);
    const max = 1440 - startDate.getHours() * 60 - startDate.getMinutes();
    const clamp = (minutes) => Math.max(15, Math.min(max, Math.round(minutes / 15) * 15));
    const saveDuration = (durationMinutes) =>
      action(() => put("tasks", { ...task, durationMinutes, updatedAt: Date.now() }));
    handle.onclick = (event) => event.stopPropagation();
    handle.ondragstart = (event) => {
      event.preventDefault();
      event.stopPropagation();
    };
    handle.onkeydown = (event) => {
      if (!["ArrowUp", "ArrowDown"].includes(event.key)) return;
      event.preventDefault();
      event.stopPropagation();
      void saveDuration(clamp((task.durationMinutes || 30) + (event.key === "ArrowDown" ? 15 : -15)));
    };
    handle.onpointerdown = (event) => {
      event.preventDefault();
      event.stopPropagation();
      const block = handle.closest(".schedule-event");
      const origin = event.clientY,
        initial = task.durationMinutes || 30;
      let duration = initial;
      handle.setPointerCapture(event.pointerId);
      handle.onpointermove = (move) => {
        duration = clamp(initial + ((move.clientY - origin) * 60) / 48);
        block.style.height = `${Math.max(20, (duration * 48) / 60 - 2)}px`;
      };
      const finish = () => {
        handle.onpointermove = null;
        handle.onpointerup = null;
        handle.onpointercancel = null;
      };
      handle.onpointerup = () => {
        finish();
        if (duration !== initial) void saveDuration(duration);
      };
      handle.onpointercancel = () => {
        finish();
        block.style.height = `${Math.max(20, (initial * 48) / 60 - 2)}px`;
      };
    };
  });
  const reschedule = async (event, key, time = null) => {
    event.preventDefault();
    const id = event.dataTransfer.getData("text/orbit-task");
    const task = rows("tasks").find((item) => item.id === id && !item.isNote);
    if (!task) return;
    await action(async () => {
      const stamp = time ? new Date(`${key}T${time}:00`).getTime() : null;
      const delta = task.hasTime && stamp ? stamp - task.dueDate : 0;
      await put("tasks", {
        ...task,
        hasTime: !!time,
        dueDate: stamp,
        localDate: time ? null : key,
        reminders: time ? (task.reminders || []).map((value) => value + delta) : [],
        updatedAt: Date.now(),
      });
      calendarDay = key;
    });
  };
  // Month: drop a task on another day to move it there (a timed task keeps its time).
  document.querySelectorAll(".cal-grid .cal-cell").forEach((cell) => {
    cell.ondragover = (event) => {
      if (!event.dataTransfer.types.includes("text/orbit-task")) return;
      event.preventDefault();
      event.dataTransfer.dropEffect = "move";
      cell.classList.add("drop-target");
    };
    cell.ondragleave = (event) => {
      if (!cell.contains(event.relatedTarget)) cell.classList.remove("drop-target");
    };
    cell.ondrop = (event) => {
      const task = rows("tasks").find((item) => item.id === event.dataTransfer.getData("text/orbit-task"));
      endTaskDrag();
      if (!task) return;
      const time = task.hasTime && task.dueDate ? new Date(task.dueDate).toTimeString().slice(0, 5) : null;
      void reschedule(event, cell.dataset.day, time);
    };
  });
  document.querySelectorAll("[data-time-slot], .schedule-all-day-column").forEach((target) => {
    target.ondragover = (event) => {
      if (!event.dataTransfer.types.includes("text/orbit-task")) return;
      event.preventDefault();
      event.dataTransfer.dropEffect = "move";
      if (target.classList.contains("schedule-all-day-column")) target.classList.add("drop-target");
    };
    target.ondragleave = (event) => {
      if (!target.contains(event.relatedTarget)) target.classList.remove("drop-target");
    };
    target.ondrop = (event) => {
      endTaskDrag();
      const [key, time] = target.dataset.timeSlot?.split("T") || [
        target.querySelector("[data-add-day]").dataset.addDay,
      ];
      void reschedule(event, key, time);
    };
  });
  const timeline = $("#calendar-timeline");

  if (timeline) {
    timeline
      .querySelectorAll(".time-grid")
      .forEach((grid) => grid.style.setProperty("--schedule-days", calendarView === "day" ? 1 : 7));
    placeNowLine(timeline);
    timeline.querySelectorAll("[data-event-start]").forEach((block) => {
      block.style.top = `${(Number(block.dataset.eventStart) * 48) / 60}px`;
      block.style.height = `${Math.max(20, ((Number(block.dataset.eventEnd) - Number(block.dataset.eventStart)) * 48) / 60 - 2)}px`;
      block.style.left = `calc(${(Number(block.dataset.lane) / Number(block.dataset.lanes)) * 100}% + 2px)`;
      block.style.width = `calc(${100 / Number(block.dataset.lanes)}% - 4px)`;
    });
    timeline.scrollTop = calendarScrollTop;
    timeline.onscroll = () => {
      calendarScrollTop = timeline.scrollTop;
    };
  }
  document.querySelectorAll("[data-month]").forEach(
    (button) =>
      (button.onclick = () => {
        const step = Number(button.dataset.month);
        calendarCompletedOpen = false;
        if (!step) {
          calendarDay = today();
          calendarStart = monthOf(calendarDay);
        } else if (calendarView === "month") {
          calendarStart = shiftMonth(calendarStart, step);
          calendarDay = calendarStart;
        } else {
          calendarDay = OrbitHabits.addDays(calendarDay, step * (calendarView === "week" ? 7 : 1));
          calendarStart = monthOf(calendarDay);
        }
        render();
        if (step && !reducedMotion())
          $(".cal-grid, .calendar-timeline")?.animate(
            [
              { opacity: 0.6, transform: `translateX(${step * 4}px)` },
              { opacity: 1, transform: "none" },
            ],
            { duration: 140, easing: "ease-out" },
          );
      }),
  );
}

// Editing a shared calendar event. This PC can't reach the calendar itself, so a change is saved as a
// request on the event's record; Orbit on iPhone makes the change in the calendar when it next syncs.
let editingEvent = null,
  editingEventPlace = "";
const timeOf = (stamp) => {
  const date = new Date(stamp);
  return `${String(date.getHours()).padStart(2, "0")}:${String(date.getMinutes()).padStart(2, "0")}`;
};
function openEvent(id) {
  const record = rows("events").find((event) => event.id === id) || linked().events.find((event) => event.id === id);
  const event = record && (record.provider ? record : OrbitCalendarEvents.effective(record));
  if (!event) return;
  editingEvent = record;
  const calendar = eventCalendar(event);
  const service = { google: "Google Calendar", microsoft: "Outlook" }[event.provider];
  const writable = calendar?.writable !== false;
  const form = $("#event-form");
  form.title.value = event.title || "";
  // Apple addresses often span two lines ("Place\nStreet, City"); the field shows them on one, and an
  // untouched field saves the original back unchanged.
  editingEventPlace = event.location || "";
  form.elements.location.value = eventPlace(event);
  syncMapButton();
  form.allDay.checked = !!event.allDay;
  form.day.value = event.allDay ? event.startDay : dayKey(new Date(event.start));
  form.endDay.value = event.allDay
    ? OrbitCalendarEvents.addDays(event.endDay || OrbitCalendarEvents.addDays(event.startDay, 1), -1)
    : "";
  form.startTime.value = event.allDay ? "09:00" : timeOf(event.start);
  form.endTime.value = event.allDay ? "10:00" : timeOf(event.end || event.start + 30 * 60000);
  $("#event-calendar").textContent = [calendar?.title, calendar?.email || calendar?.account]
    .filter(Boolean)
    .join(" · ");
  $("#event-note").textContent = !writable
    ? "This calendar is read-only, so the event can't be changed from Orbit."
    : service
      ? `Saved straight to ${service}${event.recurring ? ", for this occurrence only" : ""}.`
      : event.recurring
        ? "Changes apply to this occurrence only. They reach your calendar the next time Orbit syncs on your iPhone."
        : event.pending
          ? "Waiting for your iPhone to make this change in your calendar."
          : "Changes reach your calendar the next time Orbit syncs on your iPhone.";
  for (const field of form.querySelectorAll("input")) field.disabled = !writable;
  $("#delete-event").hidden = !writable;
  $("#save-event").hidden = !writable;
  syncEventFields();
  openDialog($("#event-editor"));
  focusTitle($("#event-editor"));
}
function syncEventFields() {
  const allDay = $("#event-form").allDay.checked;
  $("#event-end-day-row").hidden = !allDay;
  $("#event-start-row").hidden = allDay;
  $("#event-end-row").hidden = allDay;
}
$("#event-form").allDay.onchange = syncEventFields;
function syncMapButton() {
  $("#event-open-map").disabled = !$("#event-form").elements.location.value.trim();
}
$("#event-form").elements.location.addEventListener("input", syncMapButton);
$("#event-open-map").onclick = () => void action(() => api.openMap($("#event-form").elements.location.value));
$("#event-form").onsubmit = (submit) => {
  submit.preventDefault();
  const form = submit.target;
  const record = editingEvent;
  if (!record) return;
  let changes;
  if (form.allDay.checked) {
    const last = form.endDay.value && form.endDay.value >= form.day.value ? form.endDay.value : form.day.value;
    changes = {
      title: form.title.value.trim(),
      allDay: true,
      startDay: form.day.value,
      endDay: OrbitCalendarEvents.addDays(last, 1),
    };
  } else {
    const start = new Date(`${form.day.value}T${form.startTime.value || "09:00"}:00`).getTime();
    let end = new Date(`${form.day.value}T${form.endTime.value || form.startTime.value || "10:00"}:00`).getTime();
    if (end <= start) end += 86400000;
    changes = { title: form.title.value.trim(), allDay: false, start, end };
  }
  const place = form.elements.location.value.trim();
  changes.location = place === eventPlace({ location: editingEventPlace }) ? editingEventPlace : place;
  // Keep the draft available if the provider or local store rejects the edit.
  void action(async () => {
    if (record.provider) await api.linkedCalendars({ command: "update", event: record.id, changes });
    else await put("events", OrbitCalendarEvents.editRequest(record, changes));
    $("#event-editor").close();
  });
};
function deleteEventRecord(record) {
  return action(() =>
    record.provider
      ? api.linkedCalendars({ command: "delete", event: record.id })
      : put("events", OrbitCalendarEvents.deleteRequest(record)),
  );
}
$("#delete-event").onclick = () => {
  const record = editingEvent;
  if (!record) return;
  $("#event-editor").close();
  void deleteEventRecord(record);
};
/** Right-click on a calendar event (Today's Coming up): edit, copy, make a task from it, or delete it. */
function openEventMenu(e) {
  e.preventDefault();
  const id = e.currentTarget.dataset.editEvent;
  const record = rows("events").find((event) => event.id === id) || linked().events.find((event) => event.id === id);
  const event = record && (record.provider ? record : OrbitCalendarEvents.effective(record));
  if (!event) return;
  const writable = eventCalendar(event)?.writable !== false;
  const day = event.allDay ? event.startDay : dayKey(new Date(event.start));
  const when = event.allDay ? "All day" : `${calendarTime(event.start)}–${calendarTime(event.end || event.start)}`;
  const entries = [
    ["Edit event…", () => openEvent(id)],
    ...(eventPlace(event) ? [["Open address in maps", () => void action(() => api.openMap(event.location))]] : []),
    ["Copy text", () => api.copy([event.title || "Event", when, event.location].filter(Boolean).join("\n"))],
    [
      "Add as a task",
      () => {
        const task = newTask(event.title || "Event", day);
        if (!event.allDay) {
          Object.assign(task, {
            hasTime: true,
            dueDate: event.start,
            durationMinutes: Math.min(
              1440,
              Math.max(5, Math.round(((event.end || event.start) - event.start) / 60000)),
            ),
          });
        }
        return action(() => saveTasks([{ ...task, listID: null }]));
      },
    ],
  ];
  if (writable) entries.push(["Delete event", () => deleteEventRecord(record)]);
  const box = e.currentTarget.getBoundingClientRect();
  showMenu(entries, e.clientX || box.left + 24, e.clientY || box.bottom);
}
