// Month planning and scrollable day/week schedules share the same dated tasks and editor.
let calendarStart = null,
  calendarDay = null,
  calendarCompletedOpen = false,
  calendarScrollTop = 8 * 64;
const chevron = (path) => `<svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="${path}"/></svg>`;
const monthOf = (key) => key.slice(0, 8) + "01";
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
  const days = Array.from({ length: 42 }, (_, index) => OrbitHabits.addDays(start, index));
  const on = (key) =>
    tasks
      .filter((task) => taskDate(task) === key)
      .sort((a, b) => !!a.completedAt - !!b.completedAt || (a.dueDate || 0) - (b.dueDate || 0));
  const month = first.toLocaleDateString([], { month: "long", year: "numeric" });
  const count = tasks.filter((task) => monthOf(taskDate(task) || "") === calendarStart).length;
  const weekday = days
    .slice(0, 7)
    .map((key) => `<span>${localDay(key).toLocaleDateString([], { weekday: "short" })}</span>`)
    .join("");
  const cells = days
    .map((key) => {
      const date = localDay(key),
        items = on(key);
      const lines = items
        .slice(0, 3)
        .map((task) => {
          const time = task.hasTime
            ? new Date(task.dueDate).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })
            : "";
          return `<span class="cal-item ${task.completedAt ? "done" : ""}"><i></i>${
            time
              ? `<b>${time
                  .replace(/:00(?= )/, "")
                  .replace(" ", "")
                  .toLowerCase()}</b>`
              : ""
          }<em>${esc(task.title)}</em></span>`;
        })
        .join("");
      const label = date.toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" });
      return `<button class="day-tile cal-cell ${key === calendarDay ? "selected" : ""} ${key === current ? "today" : ""} ${date.getMonth() !== first.getMonth() ? "outside" : ""}" data-day="${key}" aria-pressed="${key === calendarDay}" aria-label="${label}${items.length ? `, ${items.length} ${items.length === 1 ? "item" : "items"}` : ""}"><span class="cal-date">${date.getDate()}</span>${lines}${items.length > 3 ? `<span class="cal-more">${items.length - 3} more</span>` : ""}</button>`;
    })
    .join("");
  const chosen = localDay(calendarDay),
    heading = calendarDay === current ? "Today" : chosen.toLocaleDateString([], { weekday: "long" });
  const items = on(calendarDay),
    open = items.filter((task) => !task.completedAt),
    completed = items.filter((task) => task.completedAt);
  return `<div class="calendar-page">${calendarHeader(month, count ? `${count} ${count === 1 ? "item" : "items"} this month` : "Nothing planned this month yet")}<div class="cal-layout"><div class="cal-month"><div class="cal-weekdays" aria-hidden="true">${weekday}</div><div class="day-tiles cal-grid" role="group" aria-label="Days">${cells}</div></div><aside class="cal-day card" aria-label="${heading}"><div class="cal-day-head"><h2>${heading}</h2><span>${chosen.toLocaleDateString([], { month: "long", day: "numeric" })}</span></div><div class="check-list">${open.map(taskRow).join("") || '<p class="empty">Nothing planned. Type to add a task.</p>'}</div>${calendarCompleted(completed)}</aside></div><div class="capture-dock">${addField(calendarDay === current ? "Add to today" : "Add to " + heading)}</div></div>`;
}
function renderSchedule(tasks) {
  const dayView = calendarView === "day";
  const start = dayView ? calendarDay : OrbitHabits.weekStartKey(calendarDay, weekStart);
  const days = Array.from({ length: dayView ? 1 : 7 }, (_, index) => OrbitHabits.addDays(start, index));
  const items = tasks.filter((task) => days.includes(taskDate(task)));
  const open = items.filter((task) => !task.completedAt),
    complete = items.filter((task) => task.completedAt);
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
  const untimed = days
    .map(
      (key) =>
        `<div class="schedule-all-day-column"><button class="schedule-all-day-add" data-add-day="${key}" aria-label="Add an untimed task on ${key}">Any time ${chevron("M12 5v14M5 12h14")}</button>${open
          .filter((task) => taskDate(task) === key && !task.hasTime)
          .map(taskRow)
          .join("")}</div>`,
    )
    .join("");
  const axis = Array.from(
    { length: 24 },
    (_, hour) => `<div>${new Date(2000, 0, 1, hour).toLocaleTimeString([], { hour: "numeric" })}</div>`,
  ).join("");
  const columns = days
    .map((key) => {
      const slots = Array.from({ length: 48 }, (_, index) => {
        const time = `${String(Math.floor(index / 2)).padStart(2, "0")}:${index % 2 ? "30" : "00"}`;
        return `<button class="time-slot ${index % 2 ? "half-hour" : ""}" data-time-slot="${key}T${time}" aria-label="Add task on ${key} at ${time}"></button>`;
      }).join("");
      const blocks = OrbitCalendarLayout.place(open.filter((task) => taskDate(task) === key && task.hasTime))
        .map(
          ({ task, start, end, lane, lanes }) =>
            `<div class="schedule-event check-tile" data-event-start="${start}" data-event-end="${end}" data-lane="${lane}" data-lanes="${lanes}" data-row-menu="task:${esc(task.id)}"><button class="schedule-check" role="checkbox" aria-checked="false" aria-label="Complete ${esc(task.title)}" data-toggle="${esc(task.id)}">${tick(false)}</button><button class="schedule-event-body" data-edit="${esc(task.id)}" aria-label="Edit ${esc(task.title)}" title="${esc(task.title)}"><strong>${esc(task.title)}</strong><span>${new Date(task.dueDate).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}</span></button>${rowActions(esc(task.id), esc(task.title))}</div>`,
        )
        .join("");
      return `<div class="schedule-day"><div class="schedule-slots">${slots}</div>${blocks}</div>`;
    })
    .join("");
  return `<div class="calendar-page timeline-page">${calendarHeader(title, subtitle)}<div id="calendar-timeline" class="calendar-timeline"><div class="schedule-header time-grid"><span></span>${headings}</div><div class="schedule-all-day time-grid"><span class="time-axis-label">Any time</span>${untimed}</div><div class="schedule-hours time-grid"><div class="time-axis">${axis}</div>${columns}</div></div>${calendarCompleted(complete)}<div class="capture-dock">${addField("Add a task for " + date.toLocaleDateString([], { month: "short", day: "numeric" }))}</div></div>`;
}
function bindCalendar() {
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
  document.querySelectorAll("[data-day]").forEach((button) => {
    button.onclick = () => {
      calendarDay = button.dataset.day;
      calendarCompletedOpen = false;
      calendarStart = monthOf(calendarDay);
      render();
    };
    button.ondblclick = () => openQuickAdd({ defaultDate: button.dataset.day, listID: null });
  });
  document
    .querySelectorAll("[data-add-day]")
    .forEach((button) => (button.onclick = () => openTask(null, button.dataset.addDay)));
  document.querySelectorAll("[data-time-slot]").forEach(
    (button) =>
      (button.onclick = () => {
        const [key, time] = button.dataset.timeSlot.split("T"),
          stamp = new Date(`${key}T${time}:00`).getTime();
        calendarDay = key;
        openTask(null, key, { ...newTask("", key), hasTime: true, dueDate: stamp, localDate: null });
        $("#task-form input[name=title]").focus();
      }),
  );
  const timeline = $("#calendar-timeline");
  if (timeline) {
    timeline
      .querySelectorAll(".time-grid")
      .forEach((grid) => grid.style.setProperty("--schedule-days", calendarView === "day" ? 1 : 7));
    timeline.querySelectorAll("[data-event-start]").forEach((block) => {
      block.style.top = `${(Number(block.dataset.eventStart) * 64) / 60}px`;
      block.style.height = `${Math.max(20, ((Number(block.dataset.eventEnd) - Number(block.dataset.eventStart)) * 64) / 60 - 2)}px`;
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
