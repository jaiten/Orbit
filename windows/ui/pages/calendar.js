function renderCalendar(tasks) {
  const now = new Date();
  const month = now.toLocaleDateString([], { month: "long", year: "numeric" });
  let html = `<div class="narrow"><header class="page-head"><div><div class="eyebrow">Next seven days</div><h1>Calendar</h1><p class="subtitle">${month}</p></div></header>`;
  for (let i = 0; i < 7; i++) {
    const d = new Date();
    d.setDate(d.getDate() + i);
    const key = dayKey(d);
    const items = tasks.filter((t) => taskDate(t) === key);
    const heading = i === 0 ? "Today" : d.toLocaleDateString([], { weekday: "long" });
    const date = d.toLocaleDateString([], { month: "short", day: "numeric" });
    html += `<section class="week-day"><div class="section-label"><h2>${heading} <span class="day-date">${date}</span></h2><button class="pill" data-plan="${key}" aria-label="Add to ${heading}">+ Add</button></div>
      <div class="check-list">${items.map(taskRow).join("") || '<p class="empty">Nothing planned</p>'}</div></section>`;
  }
  return html + "</div>";
}

function bindCalendar() {
  document
    .querySelectorAll("[data-plan]")
    .forEach((b) => (b.onclick = () => openQuickAdd({ defaultDate: b.dataset.plan, listID: null })));
}
