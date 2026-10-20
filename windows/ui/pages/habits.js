function renderHabits(habits) {
  let html =
    '<div class="section-heading"><h1>Habits</h1><button id="add-habit" class="primary">+ New Habit</button></div>';
  if (!habits.length) return html + '<p class="empty">No habits yet.</p>';
  html += habits.map(habitCard).join("") + '<button id="habit-history" class="history-link">History →</button>';
  return html;
}

function renderHistoryIndex(habits) {
  return (
    "<h1>History</h1>" +
    habits
      .map((h) => `<button class="history-link" data-history="${esc(h.id)}">${esc(h.title)} <span>→</span></button>`)
      .join("")
  );
}

function renderHabitHistory(habits) {
  const h = habits.find((h) => h.id === historyHabitID);
  if (!h) return "<h1>Habit deleted</h1>";
  const cells = Array.from({ length: 84 }, (_, i) => {
    const d = new Date();
    d.setDate(d.getDate() - 83 + i);
    const key = dayKey(d),
      n = dailyCount(h, key);
    return `<span class="${n ? "logged" : ""}" title="${key}: ${n}"></span>`;
  }).join("");
  const period = h.frequencyRule === "WEEKLY" ? "this week" : "today";
  return `<h1>${esc(h.title)}</h1><p class="subtitle">Last 12 weeks · ${progress(h)} / ${h.target} ${period}</p><div class="heatmap">${cells}</div>`;
}

function bindHabits() {
  if ($("#habit-history"))
    $("#habit-history").onclick = () => {
      page = "history";
      render();
    };
  document.querySelectorAll("[data-history]").forEach(
    (b) =>
      (b.onclick = () => {
        historyHabitID = b.dataset.history;
        page = "habit-history";
        render();
      }),
  );
  if ($("#add-habit"))
    $("#add-habit").onclick = () => {
      if ($(".floating-add")) $(".floating-add").open = false;
      openHabit();
    };
}
