function renderHabits(habits) {
  const head = `<header class="page-head"><div><h1>Habits</h1></div><button id="habit-history" class="quiet-control" title="Habit history"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>History</button></header>`;
  if (!habits.length)
    return `<div class="narrow habits-page">${head}<div class="empty-state"><svg class="doc-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m17 2 4 4-4 4M3 11v-1a4 4 0 0 1 4-4h14M7 22l-4-4 4-4M21 13v1a4 4 0 0 1-4 4H3"/></svg><p><strong>No habits yet</strong><br />Add one, or type “read every day” anywhere.</p></div><div class="capture-dock">${addField("Add a habit")}</div></div>`;
  return `<div class="narrow habits-page">${head}
    <div class="check-list">${habitCards(habits, true)}</div>
    <div class="capture-dock">${addField("Add a habit")}</div>
  </div>`;
}

/** "5 of the last 7 days" as seven rounded segments with weekday letters. Unscheduled days are outlined. */
function weekSegments(h, end = dayKey(new Date())) {
  const cells = Array.from({ length: 7 }, (_, i) => {
    const key = OrbitHabits.addDays(end, i - 6);
    const done = checked(h, key);
    const scheduled = OrbitHabits.scheduledOn(h, key);
    const name = localDay(key).toLocaleDateString([], { weekday: "narrow" });
    const available = !h.createdAt || dayKey(new Date(h.createdAt)) <= key;
    const status = done
      ? "checked"
      : !available
        ? "before this habit was added"
        : scheduled
          ? "not checked"
          : "not scheduled";
    const label =
      localDay(key).toLocaleDateString([], { weekday: "long", year: "numeric", month: "long", day: "numeric" }) +
      ": " +
      status;
    const classes = `segment ${done ? "done" : ""} ${scheduled && available ? "" : "off"}`;
    if (!available || key > today() || key < OrbitHabits.addDays(today(), -6))
      return `<span class="${classes}" role="img" aria-label="${esc(label)}" title="${esc(label)}"><i aria-hidden="true"></i><span aria-hidden="true">${name}</span></span>`;
    return `<button class="${classes}" data-history-toggle="${esc(h.id)}" data-day="${key}" data-done="${done}" aria-label="${esc(label)}. ${done ? "Remove one check-in" : "Add a check-in"}" title="${esc(label)}"><i aria-hidden="true"></i><span aria-hidden="true">${name}</span></button>`;
  }).join("");
  return `<div class="week-segments fill-${colorName(h.color)}" role="group" aria-label="Last 7 days">${cells}</div>`;
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
    <header class="page-head"><button class="icon-button" data-history-back="habits" aria-label="Back to Habits"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m15 6-6 6 6 6"/></svg></button><div><div class="eyebrow">Habits</div><h1>History</h1><p class="subtitle">Select any of the last seven days to correct a check-in.</p></div></header>
    <div class="history-list">${habits
      .map(
        (h) => `<section class="card habit-history" data-flip="history-${esc(h.id)}">
      <button class="history-head" data-history="${esc(h.id)}"><span class="dot ${colorName(h.color)}" aria-hidden="true"></span><strong>${esc(h.title)}</strong><span>${OrbitHabits.checkedDays(h, habitLogs(), t, 7)} of the last 7 days <svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg></span></button>
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
    <header class="page-head"><button class="icon-button" data-history-back="history" aria-label="Back to History"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m15 6-6 6 6 6"/></svg></button><div><div class="eyebrow">History</div><h1>${esc(h.title)}</h1><p class="subtitle">${OrbitHabits.label(h)} · ${habitDetail(h, t)}. Select any of the last seven days to add or remove a check-in.</p></div></header>
    <section class="card habit-history">
      <div class="history-head static"><span class="dot ${colorName(h.color)}" aria-hidden="true"></span><strong>${lastSeven} of the last 7 days</strong></div>
      ${habitHistoryCharts(h)}
    </section>
    ${sectionLabel("Recent days")}
    ${recent ? `<ul class="check-ins card">${recent}</ul>` : '<p class="empty">No check-ins yet.</p>'}
  </div>`;
}

function bindHabits() {
  document.querySelectorAll("[data-history-back]").forEach(
    (button) =>
      (button.onclick = () => {
        page = button.dataset.historyBack;
        render();
      }),
  );
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
  document
    .querySelectorAll("[data-history-toggle]")
    .forEach(
      (button) =>
        (button.onclick = () =>
          action(() => log(button.dataset.historyToggle, button.dataset.done === "true", button.dataset.day))),
    );
}
