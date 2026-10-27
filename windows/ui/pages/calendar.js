// Calendar: the month as a grid (like macOS Calendar), each day showing its first few items, and the
// chosen day's plan beside it with its own add field.
let calendarStart = null,
  calendarDay = null;
const chevron = (d) => `<svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="${d}"/></svg>`;

/** The first day of the month containing `key`. */
const monthOf = (key) => key.slice(0, 8) + "01";
function shiftMonth(key, delta) {
  const d = localDay(key);
  return dayKey(new Date(d.getFullYear(), d.getMonth() + delta, 1));
}

function renderCalendar(tasks) {
  const t = today();
  if (calendarView !== "month") {
    todayScope = calendarView;
    const title = calendarView === "week" ? "This week" : "Everything";
    const head = `<header class="page-head">
      <div><div class="eyebrow">Plan ahead</div><h1>${title}</h1><p class="subtitle">Every task and habit, at a glance.</p></div>
      <div class="head-tools">${scopeTabs()}</div>
    </header>`;
    return renderAgenda(
      tasks,
      rows("habits").sort((a, b) => (a.createdAt || 0) - (b.createdAt || 0)),
      head,
    );
  }
  calendarDay ??= t;
  calendarStart ??= monthOf(calendarDay);
  const first = localDay(calendarStart);
  const gridStart = OrbitHabits.weekStartKey(calendarStart, weekStart);
  const days = Array.from({ length: 42 }, (_, i) => OrbitHabits.addDays(gridStart, i));
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
      const outside = d.getMonth() !== first.getMonth();
      const label = d.toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" });
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
      const more = items.length > 3 ? `<span class="cal-more">${items.length - 3} more</span>` : "";
      return `<button class="day-tile cal-cell ${key === calendarDay ? "selected" : ""} ${key === t ? "today" : ""} ${outside ? "outside" : ""}" data-day="${key}" aria-pressed="${key === calendarDay}" aria-label="${label}${items.length ? `, ${items.length} ${items.length === 1 ? "item" : "items"}` : ""}">
        <span class="cal-date">${d.getDate()}</span>${lines}${more}
      </button>`;
    })
    .join("");
  const chosen = localDay(calendarDay);
  const heading = calendarDay === t ? "Today" : chosen.toLocaleDateString([], { weekday: "long" });
  const date = chosen.toLocaleDateString([], { month: "long", day: "numeric" });
  const items = on(calendarDay);
  const count = tasks.filter((task) => monthOf(taskDate(task) || "") === calendarStart).length;
  return `<div class="calendar-page">
    <header class="page-head">
      <div><div class="eyebrow">Plan ahead</div><h1>${month}</h1><p class="subtitle">${count ? `${count} ${count === 1 ? "item" : "items"} this month` : "Nothing planned this month yet"}</p></div>
      <div class="head-tools">
      <div class="week-nav day-nav" role="group" aria-label="Month">
        <button class="icon-button" data-month="-1" aria-label="Previous month" title="Previous month">${chevron("m15 18-6-6 6-6")}</button
        ><button class="today-button" data-month="0" ${calendarStart === monthOf(t) && calendarDay === t ? "disabled" : ""}>Today</button
        ><button class="icon-button" data-month="1" aria-label="Next month" title="Next month">${chevron("m9 18 6-6-6-6")}</button>
      </div>
      ${scopeTabs()}
      </div>
    </header>
    <div class="cal-layout">
      <div class="cal-month">
        <div class="cal-weekdays" aria-hidden="true">${weekdays}</div>
        <div class="day-tiles cal-grid" role="group" aria-label="Days">${cells}</div>
      </div>
      <aside class="cal-day card" aria-label="${heading}">
        <div class="cal-day-head"><h2>${heading}</h2><span>${date}</span></div>
        ${addField(calendarDay === t ? "Add to today" : "Add to " + heading)}
        <div class="check-list">${items.map(taskRow).join("") || `<p class="empty">Nothing planned. Type to add something for ${calendarDay === t ? "today" : heading}.</p>`}</div>
      </aside>
    </div>
  </div>`;
}

function bindCalendar() {
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
        if (step) {
          calendarStart = shiftMonth(calendarStart, step);
          calendarDay = calendarStart;
        } else {
          calendarDay = today();
          calendarStart = monthOf(calendarDay);
        }
        render();
      }),
  );
}
