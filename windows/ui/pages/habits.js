function renderHabits(habits) {
  const html = "<h1>Habits</h1>";
  if (!habits.length) return html + '<p class="empty">No habits yet. Try adding “read every day”.</p>';
  return html + habits.map(habitCard).join("") + '<button id="habit-history" class="history-link">History →</button>';
}

/** Every habit's history on one page, so there is nothing to open one by one. */
function renderHistoryIndex(habits) {
  const today = dayKey(new Date());
  return (
    "<h1>History</h1>" +
    habits
      .map(
        (h) => `<section class="settings-block habit-history">
      <button class="history-link" data-history="${esc(h.id)}">${esc(h.title)} <span>${OrbitHabits.checkedDays(h, habitLogs(), today, 7)} of the last 7 days →</span></button>
      ${habitHistoryCharts(h, today)}
    </section>`,
      )
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
  const recent = habitLogs()
    .filter((l) => l.habitID === h.id && l.count > 0)
    .sort((a, b) => b.dayKey.localeCompare(a.dayKey))
    .slice(0, 90)
    .map((l) => `<li>${esc(l.dayKey)} <span>${l.count} check-in${l.count === 1 ? "" : "s"}</span></li>`)
    .join("");
  return `<h1>${esc(h.title)}</h1>
    <p class="subtitle">${OrbitHabits.label(h)} · ${habitDetail(h, today)}</p>
    <section class="settings-block">
      <h2>${lastSeven} of the last 7 days</h2>
      ${habitHistoryCharts(h, today)}
    </section>
    <section class="settings-block"><h2>Recent days</h2>${recent ? `<ul class="check-ins">${recent}</ul>` : '<p class="secondary">No check-ins yet.</p>'}</section>`;
}

/** The last 7 days and the last 12 weeks for one habit. */
function habitHistoryCharts(h, today) {
  const cells = Array.from({ length: 84 }, (_, i) => {
    const key = OrbitHabits.addDays(today, i - 83),
      n = dailyCount(h, key);
    return `<span class="${n ? "logged" : ""}" title="${key}: ${n}"></span>`;
  }).join("");
  return `<div class="history-charts">${consistencyStrip(h, today)}<div class="heatmap" aria-label="Last 12 weeks">${cells}</div></div>`;
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
