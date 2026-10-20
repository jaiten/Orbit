function renderCalendar(tasks) {
  let html = "<h1>Calendar</h1>";
  for (let i = 0; i < 7; i++) {
    const d = new Date();
    d.setDate(d.getDate() + i);
    const key = dayKey(d);
    const items = tasks.filter((t) => taskDate(t) === key);
    const heading = d.toLocaleDateString([], { weekday: "long", month: "short", day: "numeric" });
    html += `<section class="week-day"><div class="section-heading"><h2>${heading}</h2><button data-plan="${key}">+ Add</button></div>${items.map(taskRow).join("") || '<p class="empty">Nothing planned</p>'}</section>`;
  }
  return html;
}

function bindCalendar() {
  document
    .querySelectorAll("[data-plan]")
    .forEach((b) => (b.onclick = () => openQuickAdd({ defaultDate: b.dataset.plan, listID: null })));
}
