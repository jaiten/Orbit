// Calendar: a week of day tiles across the top (as on the website), and the chosen day's plan below.
let calendarStart = null,
  calendarDay = null;
const chevron = (d) => `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${d}"/></svg>`;

function renderCalendar(tasks) {
  const t = today();
  calendarStart ??= t;
  calendarDay ??= t;
  const days = Array.from({ length: 7 }, (_, i) => OrbitHabits.addDays(calendarStart, i));
  const month = localDay(calendarDay).toLocaleDateString([], { month: "long", year: "numeric" });
  const tiles = days
    .map((key) => {
      const d = localDay(key);
      const busy = tasks.some((task) => taskDate(task) === key && !task.completedAt);
      const label = d.toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" });
      return `<button class="day-tile ${key === calendarDay ? "selected" : ""} ${key === t ? "today" : ""}" data-day="${key}" aria-pressed="${key === calendarDay}" aria-label="${label}${busy ? ", has plans" : ""}">
        <span>${d.toLocaleDateString([], { weekday: "short" })}</span><strong>${d.getDate()}</strong><i class="${busy ? "busy" : ""}"></i>
      </button>`;
    })
    .join("");
  const items = tasks
    .filter((task) => taskDate(task) === calendarDay)
    .sort((a, b) => (a.hasTime ? a.dueDate : Infinity) - (b.hasTime ? b.dueDate : Infinity));
  const chosen = localDay(calendarDay);
  const heading = calendarDay === t ? "Today" : chosen.toLocaleDateString([], { weekday: "long" });
  const date = chosen.toLocaleDateString([], { month: "long", day: "numeric" });
  return `<div class="calendar-page">
    <header class="page-head">
      <div><div class="eyebrow">Calendar</div><h1>${month}</h1></div>
      <div class="week-nav">
        <button class="icon-button" data-week="-7" aria-label="Previous week">${chevron("m15 18-6-6 6-6")}</button
        ><button class="pill" data-week="0">Today</button
        ><button class="icon-button" data-week="7" aria-label="Next week">${chevron("m9 18 6-6-6-6")}</button>
      </div>
    </header>
    <div class="day-tiles" role="group" aria-label="Days">${tiles}</div>
    <div class="section-label"><h2>${heading} <span class="day-date">${date}</span></h2><button class="pill" data-plan="${calendarDay}" aria-label="Add to ${heading}">+ Add</button></div>
    <div class="check-list">${items.map(taskRow).join("") || '<p class="empty">Nothing planned.</p>'}</div>
  </div>`;
}

function bindCalendar() {
  document
    .querySelectorAll("[data-plan]")
    .forEach((b) => (b.onclick = () => openQuickAdd({ defaultDate: b.dataset.plan, listID: null })));
  document.querySelectorAll("[data-day]").forEach(
    (b) =>
      (b.onclick = () => {
        calendarDay = b.dataset.day;
        render();
      }),
  );
  document.querySelectorAll("[data-week]").forEach(
    (b) =>
      (b.onclick = () => {
        const step = Number(b.dataset.week);
        calendarStart = step ? OrbitHabits.addDays(calendarStart, step) : today();
        calendarDay = step ? calendarStart : today();
        render();
      }),
  );
}
