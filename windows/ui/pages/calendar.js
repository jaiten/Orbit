function renderCalendar(tasks) {
  let html =
    '<div class="eyebrow">A little perspective</div><h1>This week</h1><p class="subtitle">Make a plan that leaves room to live.</p>';
  for (let i = 0; i < 7; i++) {
    const d = new Date();
    d.setDate(d.getDate() + i);
    const key = dayKey(d);
    const items = tasks.filter((t) => taskDate(t) === key);
    const heading = d.toLocaleDateString([], { weekday: "long", month: "short", day: "numeric" });
    html += `<section class="week-day"><div class="section-heading"><h2>${heading}</h2><button data-plan="${key}">+ Plan</button></div>${items.map(taskRow).join("") || '<p class="empty">Open space</p>'}</section>`;
  }
  return html;
}

function bindCalendar() {
  document.querySelectorAll("[data-plan]").forEach((b) => (b.onclick = () => openTask(null, b.dataset.plan)));
}
