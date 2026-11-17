function renderHabits(habits) {
  // Counters (no target; every click adds one) have their own list under the habits.
  const counters = habits.filter(OrbitHabits.isCounter);
  const regular = habits.filter((h) => !OrbitHabits.isCounter(h));
  const head = `<header class="page-head"><div><h1>Habits</h1></div><div class="head-tools"><button id="new-counter" class="quiet-control" title="A counter goes up by one each time you click it">${plus}New counter</button><button id="habit-history" class="quiet-control" title="Habit history"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>History</button></div></header>`;
  if (!habits.length)
    return `<div class="narrow habits-page">${head}<div class="empty-state"><svg class="doc-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m17 2 4 4-4 4M3 11v-1a4 4 0 0 1 4-4h14M7 22l-4-4 4-4M21 13v1a4 4 0 0 1-4 4H3"/></svg><p><strong>No habits yet</strong><br />Add one, or type “read every day” anywhere.</p></div><div class="capture-dock">${addField("Add a habit")}</div></div>`;
  return `<div class="narrow habits-page">${head}
    ${regular.length ? `<div class="check-list">${habitCards(regular)}</div>` : ""}
    ${counters.length ? sectionLabel("Counters", "Click to add one · right-click to take one off") + `<div class="check-list counter-list">${counters.map((h) => counterCard(h)).join("")}</div>` : ""}
    <div class="capture-dock">${addField("Add a habit")}</div>
  </div>`;
}

/** "5 of the last 7 days" as seven rounded segments with weekday letters. Unscheduled days are outlined. */
function weekSegments(h, end = today()) {
  const cells = Array.from({ length: 7 }, (_, i) => {
    const key = OrbitHabits.addDays(end, i - 6);
    const done = checked(h, key);
    const scheduled = OrbitHabits.scheduledOn(h, key);
    const name = localDay(key).toLocaleDateString([], { weekday: "narrow" });
    const available = !h.createdAt || plannerDay(h.createdAt) <= key;
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
/** The last 7 days and the last 12 weeks for one habit, in its colour, each with a small label. */
function habitHistoryCharts(h) {
  const days = gridDays();
  const levels = days.map((key) => (key > today() ? -1 : Math.min(1, dailyCount(h, key) / OrbitHabits.dailyTarget(h))));
  return `<div class="history-charts"><div class="history-chart"><span class="history-label">Last 7 days</span>${weekSegments(h)}</div><div class="history-chart"><span class="history-label">Last 12 weeks</span>${boxGrid(levels, colorName(h.color), h.title)}</div></div>`;
}
/** A counter's history: today, the last 7 days and its daily average, then each of the last 7 days and 12 weeks. */
function counterHistory(h, t) {
  const logs = habitLogs();
  const week = Array.from({ length: 7 }, (_, i) => OrbitHabits.addDays(t, i - 6));
  const counts = week.map((key) => dailyCount(h, key));
  const total = counts.reduce((sum, n) => sum + n, 0);
  const most = Math.max(1, ...counts);
  const stat = (value, label) => `<div class="history-stat"><b>${value}</b><span>${label}</span></div>`;
  const stats = `<div class="history-stats">${stat(counts[6], "today")}${stat(total, "last 7 days")}${stat(total ? (total / 7).toFixed(1) : 0, "a day")}</div>`;
  const bars = week
    .map((key, i) => {
      const name = localDay(key).toLocaleDateString([], { weekday: "narrow" });
      const label = `${localDay(key).toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" })}: ${counts[i]}`;
      return `<span class="count-day" role="img" aria-label="${esc(label)}" title="${esc(label)}"><b>${counts[i]}</b><i data-bar="${(counts[i] / most).toFixed(2)}" aria-hidden="true"></i><span aria-hidden="true">${name}</span></span>`;
    })
    .join("");
  const days = gridDays();
  const peak = Math.max(1, ...days.map((key) => (key > t ? 0 : OrbitHabits.dayCount(h, logs, key))));
  const levels = days.map((key) => (key > t ? -1 : OrbitHabits.dayCount(h, logs, key) / peak));
  const charts = `<div class="history-charts"><div class="history-chart"><span class="history-label">Last 7 days</span><div class="count-days fill-${colorName(h.color)}" role="group" aria-label="Last 7 days">${bars}</div></div><div class="history-chart"><span class="history-label">Last 12 weeks</span>${boxGrid(levels, colorName(h.color), h.title)}</div></div>`;
  return { stats, charts };
}
/** Streak, the last 7 days and the 12-week rate, as three quiet figures. */
function habitStats(h, t) {
  const weekly = OrbitHabits.schedule(h) === "WEEKLY";
  // A streak still counts until today (or this week) is over: before today's check-in it runs to yesterday.
  const run = Math.max(
    OrbitHabits.streak(h, habitLogs(), t, weekStart),
    OrbitHabits.streak(h, habitLogs(), OrbitHabits.addDays(t, weekly ? -7 : -1), weekStart),
  );
  const past = gridDays().filter((key) => key <= t);
  const rate = past.length
    ? Math.round(
        (past.reduce((sum, key) => sum + Math.min(1, dailyCount(h, key) / OrbitHabits.dailyTarget(h)), 0) /
          past.length) *
          100,
      )
    : 0;
  const stat = (value, label) => `<div class="history-stat"><b>${value}</b><span>${label}</span></div>`;
  return `<div class="history-stats">${stat(run, weekly ? (run === 1 ? "week streak" : "weeks in a row") : run === 1 ? "day streak" : "days in a row")}${stat(`${OrbitHabits.checkedDays(h, habitLogs(), t, 7)}/7`, "last 7 days")}${stat(`${rate}%`, "12 weeks")}</div>`;
}

/** Every habit's history on one page, so there is nothing to open one by one. */
function renderHistoryIndex(habits) {
  const t = today();
  return `<div class="narrow wide">
    <header class="page-head"><button class="icon-button" data-history-back="habits" aria-label="Back to Habits"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m15 6-6 6 6 6"/></svg></button><div><div class="eyebrow">Habits</div><h1>History</h1><p class="subtitle">Select any of the last seven days to correct a check-in.</p></div></header>
    <div class="history-list">${habits
      .map((h) => {
        if (!OrbitHabits.isCounter(h)) return null;
        const { stats, charts } = counterHistory(h, t);
        return `<section class="card habit-history" data-flip="history-${esc(h.id)}">
      <div class="history-top"><div><button class="history-head" data-history="${esc(h.id)}" aria-label="${esc(h.title)}, counter"><span class="dot ${colorName(h.color)}" aria-hidden="true"></span><strong>${esc(h.title)}</strong><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg></button>
      <p class="history-schedule">Counter</p></div>${stats}</div>
      ${charts}
    </section>`;
      })
      .map(
        (card, index) =>
          card ??
          ((h) => `<section class="card habit-history" data-flip="history-${esc(h.id)}">
      <div class="history-top"><div><button class="history-head" data-history="${esc(h.id)}" aria-label="${esc(h.title)} ${OrbitHabits.checkedDays(h, habitLogs(), t, 7)} of the last 7 days"><span class="dot ${colorName(h.color)}" aria-hidden="true"></span><strong>${esc(h.title)}</strong><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg></button>
      <p class="history-schedule">${OrbitHabits.label(h)} · ${habitDetail(h, t)}</p></div>${habitStats(h, t)}</div>
      ${habitHistoryCharts(h)}
    </section>`)(habits[index]),
      )
      .join("")}</div>
  </div>`;
}

function renderHabitHistory(habits) {
  const h = habits.find((h) => h.id === historyHabitID);
  if (!h) return "<h1>Habit deleted</h1>";
  const t = today();
  const counter = OrbitHabits.isCounter(h);
  const lastSeven = OrbitHabits.checkedDays(h, habitLogs(), t, 7);
  const unit = counter ? "time" : "check-in";
  const recent = habitLogs()
    .filter((l) => l.habitID === h.id && l.count > 0)
    .sort((a, b) => b.dayKey.localeCompare(a.dayKey))
    .slice(0, 90)
    .map((l) => `<li>${esc(l.dayKey)} <span>${l.count} ${unit}${l.count === 1 ? "" : "s"}</span></li>`)
    .join("");
  if (counter) {
    const { stats, charts } = counterHistory(h, t);
    return `<div class="narrow wide">
    <header class="page-head"><button class="icon-button" data-history-back="history" aria-label="Back to History"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m15 6-6 6 6 6"/></svg></button><div><div class="eyebrow">History</div><h1>${esc(h.title)}</h1><p class="subtitle">Counter · ${dailyCount(h, t)} today</p></div></header>
    <section class="card habit-history"><div class="history-top"><div class="history-head static"><span class="dot ${colorName(h.color)}" aria-hidden="true"></span><strong>How often</strong></div>${stats}</div>${charts}</section>
    ${sectionLabel("Recent days")}
    ${recent ? `<ul class="check-ins card">${recent}</ul>` : '<p class="empty">Nothing counted yet.</p>'}
  </div>`;
  }
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
  if ($("#new-counter")) $("#new-counter").onclick = () => openHabit(null, { frequencyRule: OrbitHabits.COUNTER });
  document
    .querySelectorAll(".count-day i[data-bar]")
    .forEach((bar) => (bar.style.height = `${Math.round(4 + Number(bar.dataset.bar) * 30)}px`));
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
