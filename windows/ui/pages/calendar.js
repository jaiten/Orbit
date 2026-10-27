// Calendar: the month as a grid (like macOS Calendar), each day showing its first few items, and the
// chosen day's plan beside it with its own add field.
let calendarStart = null,
  calendarDay = null,
  calendarCompletedOpen = false;
const chevron = (d) => `<svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="${d}"/></svg>`;

/** The first day of the month containing `key`. */
const monthOf = (key) => key.slice(0, 8) + "01";
function shiftMonth(key, delta) {
  const d = localDay(key);
  return dayKey(new Date(d.getFullYear(), d.getMonth() + delta, 1));
}

function renderCalendar(tasks) {
  const t = today();
  calendarDay ??= t;
  calendarStart ??= monthOf(calendarDay);
  const first = localDay(calendarStart);
  const weekly = calendarView === "week";
  const gridStart = weekly ? OrbitHabits.addDays(calendarDay, -6) : OrbitHabits.weekStartKey(calendarStart, weekStart);
  const days = Array.from({ length: weekly ? 7 : 42 }, (_, i) => OrbitHabits.addDays(gridStart, i));
  const month = first.toLocaleDateString([], { month: "long", year: "numeric" });
  const order = (a, b) =>
    !!a.completedAt - !!b.completedAt || (a.hasTime ? a.dueDate : Infinity) - (b.hasTime ? b.dueDate : Infinity);
  const on = (key) => tasks.filter((task) => taskDate(task) === key).sort(order);
  const weekdays = days
    .slice(0, 7)
    .map((key) => `<span>${localDay(key).toLocaleDateString([], { weekday: "short" })}</span>`)
    .join("");
  const cells = days
    .map((key) => {
      const d = localDay(key);
      const items = on(key);
      const outside = !weekly && d.getMonth() !== first.getMonth();
      const label = d.toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" });
      const lines = items
        .slice(0, weekly ? 8 : 3)
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
      const more =
        items.length > (weekly ? 8 : 3) ? `<span class="cal-more">${items.length - (weekly ? 8 : 3)} more</span>` : "";
      return `<button class="day-tile cal-cell ${key === calendarDay ? "selected" : ""} ${key === t ? "today" : ""} ${outside ? "outside" : ""}" data-day="${key}" aria-pressed="${key === calendarDay}" aria-label="${label}${items.length ? `, ${items.length} ${items.length === 1 ? "item" : "items"}` : ""}">
        <span class="cal-date">${d.getDate()}</span>${lines}${more}
      </button>`;
    })
    .join("");
  const chosen = localDay(calendarDay);
  const heading = calendarDay === t ? "Today" : chosen.toLocaleDateString([], { weekday: "long" });
  const date = chosen.toLocaleDateString([], { month: "long", day: "numeric" });
  const items = on(calendarDay);
  const openItems = items.filter((task) => !task.completedAt);
  const completed = items.filter((task) => task.completedAt);
  const count = tasks.filter((task) => monthOf(taskDate(task) || "") === calendarStart).length;
  return `<div class="calendar-page">
    <header class="page-head">
      <div><div class="month-heading"><h1>${weekly ? "This week" : month}</h1></div><p class="subtitle">${weekly ? `${localDay(days[0]).toLocaleDateString([], { month: "short", day: "numeric" })} – ${localDay(days[6]).toLocaleDateString([], { month: "short", day: "numeric" })}` : count ? `${count} ${count === 1 ? "item" : "items"} this month` : "Nothing planned this month yet"}</p></div>
      <div class="head-tools"><div class="month-arrows"><button class="icon-button" data-month="-1" aria-label="Previous ${weekly ? "week" : "month"}">${chevron("m15 6-6 6 6 6")}</button><button class="icon-button" data-month="1" aria-label="Next ${weekly ? "week" : "month"}">${chevron("m9 6 6 6-6 6")}</button></div>
      <button class="today-button" data-month="0">Today</button>
      ${scopeTabs()}
      </div>
    </header>
    <div class="cal-layout">
      <div class="cal-month">
        <div class="cal-weekdays" aria-hidden="true">${weekdays}</div>
        <div class="day-tiles cal-grid ${weekly ? "cal-week-grid" : ""}" role="group" aria-label="Days">${cells}</div>
      </div>
      <aside class="cal-day card" aria-label="${heading}">
        <div class="cal-day-head"><h2>${heading}</h2><span>${date}</span></div>

        <div class="check-list">${openItems.map(taskRow).join("") || `<p class="empty">Nothing planned. Type to add something for ${calendarDay === t ? "today" : heading}.</p>`}</div>
        ${completed.length ? `<details id="calendar-completed" ${calendarCompletedOpen ? "open" : ""}><summary>Completed (${completed.length})</summary><div class="check-list">${completed.map(taskRow).join("")}</div></details>` : ""}
      </aside>
    </div>
    <div class="capture-dock">${addField(calendarDay === t ? "Add to today" : "Add to " + heading)}</div>
  </div>`;
}

function bindCalendar() {
  if ($("#calendar-completed"))
    $("#calendar-completed").ontoggle = (event) => {
      calendarCompletedOpen = event.target.open;
    };
  document.querySelectorAll("[data-scope]").forEach(
    (b) =>
      (b.onclick = () => {
        calendarView = b.dataset.scope;
        render();
        $(`[data-scope="${calendarView}"]`)?.focus();
      }),
  );
  document.querySelectorAll("[data-day]").forEach((b) => {
    b.onclick = () => {
      calendarDay = b.dataset.day;
      if (monthOf(calendarDay) !== calendarStart) calendarStart = monthOf(calendarDay);
      render();
    };
    // Double-click a day to add straight to it.
    b.ondblclick = () => openQuickAdd({ defaultDate: b.dataset.day, listID: null });
  });
  document.querySelectorAll("[data-month]").forEach(
    (b) =>
      (b.onclick = () => {
        const step = Number(b.dataset.month);
        calendarCompletedOpen = false;
        if (step) {
          if (calendarView === "week") {
            calendarDay = OrbitHabits.addDays(calendarDay, step * 7);
            calendarStart = monthOf(calendarDay);
          } else {
            calendarStart = shiftMonth(calendarStart, step);
            calendarDay = calendarStart;
          }
        } else {
          calendarDay = today();
          calendarStart = monthOf(calendarDay);
        }
        render();
        if (step && !reducedMotion())
          $(".cal-grid")?.animate(
            [
              { opacity: 0.5, transform: `translateX(${step * 6}px)` },
              { opacity: 1, transform: "none" },
            ],
            { duration: 160, easing: "ease-out" },
          );
      }),
  );
}
