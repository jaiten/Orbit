function renderHabits(habits) {
  const html = "<h1>Habits</h1>";
  if (!habits.length) return html + '<p class="empty">No habits yet. Try adding “read every day”.</p>';
  return html + habits.map(habitCard).join("") + '<button id="habit-history" class="history-link">History →</button>';
}

function renderHistoryIndex(habits) {
  return (
    "<h1>History</h1>" +
    habits
      .map((h) => `<button class="history-link" data-history="${esc(h.id)}">${esc(h.title)} <span>→</span></button>`)
      .join("")
  );
}

function consistencyStrip(h, end = dayKey(new Date())) {
  const cells = Array.from({ length: 7 }, (_, i) => {
    const key = OrbitHabits.addDays(end, i - 6);
    const done = checked(h, key);
    const scheduled = OrbitHabits.scheduledOn(h, key);
    const name = localDay(key).toLocaleDateString([], { weekday: "narrow" });
    const status = done ? "checked" : scheduled ? "not checked" : "not scheduled";
    return `<span class="strip-day ${done ? "done" : ""} ${scheduled ? "" : "off"}" title="${key}: ${status}"><i></i>${name}</span>`;
  }).join("");
  return `<div class="consistency-strip" aria-label="Last 7 days">${cells}</div>`;
}

function renderHabitHistory(habits) {
  const h = habits.find((h) => h.id === historyHabitID);
  if (!h) return "<h1>Habit deleted</h1>";
  const today = dayKey(new Date());
  const lastSeven = OrbitHabits.checkedDays(h, habitLogs(), today, 7);
  const cells = Array.from({ length: 84 }, (_, i) => {
    const key = OrbitHabits.addDays(today, i - 83),
      n = dailyCount(h, key);
    return `<span class="${n ? "logged" : ""}" title="${key}: ${n}"></span>`;
  }).join("");
  return `<h1>${esc(h.title)}</h1>
    <p class="subtitle">${OrbitHabits.label(h)} · ${habitDetail(h, today)}</p>
    <section class="settings-block">
      <h2>${lastSeven} of the last 7 days</h2>
      ${consistencyStrip(h, today)}
    </section>
    <section class="settings-block"><h2>Last 12 weeks</h2><div class="heatmap">${cells}</div></section>`;
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
}
