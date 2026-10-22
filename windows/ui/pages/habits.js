function renderHabits(habits) {
  const head = `<header class="page-head"><div><div class="eyebrow">Repeats</div><h1>Habits</h1><p class="subtitle">Your routines, reminders and progress.</p></div></header>`;
  if (!habits.length)
    return `<div class="narrow">${head}<p class="empty">No habits yet. Try adding “read every day”.</p></div>`;
  return `<div class="narrow">${head}
    <div class="check-list">${habits.map((h) => habitCard(h, { editable: true })).join("")}</div>
    <button id="habit-history" class="card history-card"><span><span class="eyebrow">History</span><strong>The last 7 days, for every habit</strong></span><span aria-hidden="true">→</span></button>
  </div>`;
}

/** "5 of the last 7 days" as seven rounded segments with weekday letters. Unscheduled days are outlined. */
function weekSegments(h, end = dayKey(new Date())) {
  const cells = Array.from({ length: 7 }, (_, i) => {
    const key = OrbitHabits.addDays(end, i - 6);
    const done = checked(h, key);
    const scheduled = OrbitHabits.scheduledOn(h, key);
    const name = localDay(key).toLocaleDateString([], { weekday: "narrow" });
    const status = done ? "checked" : scheduled ? "not checked" : "not scheduled";
    return `<span class="segment ${done ? "done" : ""} ${scheduled ? "" : "off"}" title="${key}: ${status}"><i></i>${name}</span>`;
  }).join("");
  return `<div class="week-segments fill-${colorName(h.color)}" aria-label="Last 7 days">${cells}</div>`;
}
/** The last 7 days and the last 12 weeks for one habit, in its colour. */
function habitHistoryCharts(h) {
  const days = gridDays();
  const levels = days.map((key) => (key > today() ? -1 : Math.min(1, dailyCount(h, key) / OrbitHabits.dailyTarget(h))));
  return `<div class="history-charts">${weekSegments(h)}${boxGrid(levels, colorName(h.color), h.title)}</div>`;
}

/** Every habit's history on one page, so there is nothing to open one by one. */
function renderHistoryIndex(habits) {
  const t = today();
  return `<div class="narrow wide">
    <header class="page-head"><div><div class="eyebrow">Habits</div><h1>History</h1><p class="subtitle">The last 7 days and 12 weeks, for every habit.</p></div></header>
    <div class="history-list">${habits
      .map(
        (h) => `<section class="card habit-history" data-flip="history-${esc(h.id)}">
      <button class="history-head" data-history="${esc(h.id)}"><span class="dot ${colorName(h.color)}" aria-hidden="true"></span><strong>${esc(h.title)}</strong><span>${OrbitHabits.checkedDays(h, habitLogs(), t, 7)} of the last 7 days →</span></button>
      <p class="history-schedule">${OrbitHabits.label(h)} · ${habitDetail(h, t)}</p>
      ${habitHistoryCharts(h)}
    </section>`,
      )
      .join("")}</div>
  </div>`;
}

function renderHabitHistory(habits) {
  const h = habits.find((h) => h.id === historyHabitID);
  if (!h) return "<h1>Habit deleted</h1>";
  const t = today();
  const lastSeven = OrbitHabits.checkedDays(h, habitLogs(), t, 7);
  const recent = habitLogs()
    .filter((l) => l.habitID === h.id && l.count > 0)
    .sort((a, b) => b.dayKey.localeCompare(a.dayKey))
    .slice(0, 90)
    .map((l) => `<li>${esc(l.dayKey)} <span>${l.count} check-in${l.count === 1 ? "" : "s"}</span></li>`)
    .join("");
  return `<div class="narrow wide">
    <header class="page-head"><div><div class="eyebrow">History</div><h1>${esc(h.title)}</h1><p class="subtitle">${OrbitHabits.label(h)} · ${habitDetail(h, t)}</p></div></header>
    <section class="card habit-history">
      <div class="history-head static"><span class="dot ${colorName(h.color)}" aria-hidden="true"></span><strong>${lastSeven} of the last 7 days</strong></div>
      ${habitHistoryCharts(h)}
    </section>
    ${sectionLabel("Recent days")}
    ${recent ? `<ul class="check-ins card">${recent}</ul>` : '<p class="empty">No check-ins yet.</p>'}
  </div>`;
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
