/** Days for a 12-week grid: whole weeks in the locale's order, ending with the current week. Future days are null. */
function gridDays(weeks = 12) {
  const first = OrbitHabits.addDays(OrbitHabits.weekStartKey(today(), weekStart), -7 * (weeks - 1));
  return Array.from({ length: weeks * 7 }, (_, i) => OrbitHabits.addDays(first, i));
}
/** Share of the day's habits checked, for each day of the grid. */
function consistencyLevels(habits, days = gridDays()) {
  const logs = habitLogs();
  const entries = habits.map((h) => ({ ...h, createdDay: h.createdAt ? dayKey(new Date(h.createdAt)) : null }));
  return days.map((key) => (key > today() ? -1 : OrbitHabits.consistency(entries, logs, key)));
}

const checklist = (items, row = taskRow) => `<div class="check-list">${items.map((i) => row(i)).join("")}</div>`;

function missedYesterdayPrompt(allHabits) {
  if (new Date().getHours() >= 12 || selected !== today()) return "";
  const current = today(),
    yesterday = OrbitHabits.addDays(current, -1);
  const dismissed = localStorage.getItem("dismissedMissedHabitPromptDay");
  if (dismissed === current) return "";
  const last = localStorage.getItem("lastMissedHabitPromptDay");
  if (last && last !== current && current < OrbitHabits.addDays(last, 7)) return "";
  const candidates = allHabits.filter((habit) => {
    if (OrbitHabits.schedule(habit) === "WEEKLY") return false;
    const created = habit.createdAt ? dayKey(new Date(habit.createdAt)) : null;
    if ((created && created > yesterday) || !OrbitHabits.scheduledOn(habit, yesterday) || checked(habit, yesterday))
      return false;
    const prior = Array.from({ length: 13 }, (_, index) => OrbitHabits.addDays(current, -index - 2))
      .filter((key) => (!created || key >= created) && OrbitHabits.scheduledOn(habit, key))
      .slice(0, 5);
    return prior.length === 5 && prior.filter((key) => checked(habit, key)).length >= 3;
  });
  if (!candidates.length) return "";
  localStorage.setItem("lastMissedHabitPromptDay", current);
  return `<section class="card missed-prompt"><div><strong>Missed yesterday?</strong><button id="dismiss-missed" aria-label="Dismiss missed habit reminder">×</button></div><p>Only yesterday can be corrected.</p>${candidates
    .map((habit) => `<button data-backfill-yesterday="${esc(habit.id)}">✓ Mark ${esc(habit.title)} done</button>`)
    .join("")}</section>`;
}

// Calendar's views: the month grid, or every task this week or overall (renderAgenda).
let todayScope = "week",
  calendarView = "month";
const SCOPES = [
  ["day", "Day"],
  ["week", "Week"],
  ["month", "Month"],
];
function scopeTabs() {
  return `<div class="scope-tabs" role="tablist" aria-label="Show">${SCOPES.map(
    ([id, label]) =>
      `<button role="tab" data-scope="${id}" aria-selected="${calendarView === id}" class="${calendarView === id ? "selected" : ""}">${label}</button>`,
  ).join("")}</div>`;
}

function renderToday(tasks, allHabits) {
  // Today: dated today or earlier and still open, or finished today. Undated and Someday items stay in Notes.
  const relevant = tasks.filter((t) => OrbitPlanner.onDay(planItem(t), selected, today()));
  const habits = allHabits.filter((h) => dueOn(h));
  const open = relevant.filter((t) => !t.completedAt),
    complete = relevant.filter((t) => t.completedAt);
  // Timed tasks first, in time order; then the rest as arranged.
  open.sort((a, b) => (a.hasTime ? a.dueDate : Infinity) - (b.hasTime ? b.dueDate : Infinity));
  const overdue = open.filter((t) => OrbitPlanner.isOverdue(planItem(t), today()));
  const timed = open.filter((t) => t.hasTime && !overdue.includes(t)),
    untimed = open.filter((t) => !t.hasTime && !overdue.includes(t));
  const habitsDone = habits.filter((h) => checked(h)).length;
  const done = complete.length + habitsDone,
    total = relevant.length + habits.length;
  const date = localDay(selected);
  const isToday = selected === today();
  const heading = isToday ? "Today" : date.toLocaleDateString([], { weekday: "long" });
  const eyebrow = date.toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" });
  return `<div class="today-layout">
    <header class="page-head">
        <div><div class="eyebrow">${eyebrow}</div><h1>${heading}</h1></div>
        <div class="head-tools">
          <div class="day-nav" role="group" aria-label="Day">
            <button class="icon-button" data-day-step="-1" aria-label="Previous day" title="Previous day"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m15 18-6-6 6-6"/></svg></button
            ><button id="go-today" class="today-button" ${isToday ? "disabled" : ""}>Today</button
            ><button class="icon-button" data-day-step="1" aria-label="Next day" title="Next day"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m9 18 6-6-6-6"/></svg></button>
          </div>
        </div>
      </header>
    <section class="today-main">
      ${focusBanner()}
      ${conflictBanner()}
      ${missedYesterdayPrompt(allHabits)}
      ${overdue.length ? sectionLabel("Overdue", `${overdue.length} to review`) + checklist(overdue) : ""}
      ${timed.length ? sectionLabel("On the agenda", "Time blocks") + checklist(timed) : ""}
      ${untimed.length ? sectionLabel("At your own pace", "To-dos") + checklist(untimed) : ""}
      ${
        open.length
          ? ""
          : `<div class="empty-state"><svg class="doc-icon" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg><p><strong>${complete.length ? "All done" : "Nothing planned"}</strong><br />Start typing to add a task.</p></div>`
      }
      ${
        complete.length
          ? `<details class="completed-items" ${completedOpen ? "open" : ""}>
              <summary class="section-label"><h2>${complete.length} completed</h2><span>Done</span></summary>
              ${checklist(complete)}
            </details>`
          : ""
      }
      ${habits.length ? sectionLabel("Habits", `${habitsDone} of ${habits.length}`) + `<div class="check-list">${habitCards(habits)}</div>` : ""}
      <div class="capture-dock">${addField()}</div>
    </section>
    <aside class="today-side" aria-label="Plan and progress">
      ${recentProgressCard(tasks, allHabits)}
      ${planCard(done, total)}
    </aside>
  </div>`;
}

/** The local days of this week or month, in order. */
function scopeDays() {
  const t = today();
  if (todayScope === "week") {
    const start = OrbitHabits.weekStartKey(t, weekStart);
    return Array.from({ length: 7 }, (_, i) => OrbitHabits.addDays(start, i));
  }
  const d = localDay(t);
  const first = dayKey(new Date(d.getFullYear(), d.getMonth(), 1));
  const length = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
  return Array.from({ length }, (_, i) => OrbitHabits.addDays(first, i));
}
/** Scheduled days so far in the period (not before the habit existed), and how many were checked. */
function habitSummary(h, days) {
  const created = h.createdAt ? dayKey(new Date(h.createdAt)) : null;
  let keys = days;
  if (todayScope === "all") {
    keys = [];
    for (let key = created || today(); key <= today() && keys.length < 3660; key = OrbitHabits.addDays(key, 1))
      keys.push(key);
  }
  const due = keys.filter((key) => key <= today() && (!created || key >= created) && OrbitHabits.scheduledOn(h, key));
  return { done: due.filter((key) => checked(h, key)).length, due: due.length };
}
function habitSummaryRow(h, days) {
  const { done, due } = habitSummary(h, days);
  return `<button class="row habit-summary" data-habit-edit="${esc(h.id)}" aria-label="${esc(h.title)}, ${done} of ${due} scheduled days checked">
    <span class="row-title">${esc(h.title)}</span>
    <span class="row-detail">${due ? `${done} of ${due} days` : "Not due yet"}</span>
    <span class="mini-bar fill-${colorName(h.color)}" aria-hidden="true"><i data-fill="${due ? done / due : 0}"></i></span>
  </button>`;
}

/** Week, month and everything: tasks by day (or by when) and how each habit is going. */
function renderAgenda(tasks, allHabits, head = "") {
  const t = today();
  const days = todayScope === "all" ? [] : scopeDays();
  const inRange = todayScope === "all" ? tasks : tasks.filter((task) => days.includes(taskDate(task)));
  const order = (a, b) =>
    !!a.completedAt - !!b.completedAt || (a.hasTime ? a.dueDate : Infinity) - (b.hasTime ? b.dueDate : Infinity);
  let body = "";
  if (todayScope === "all") {
    body = ["Today", "Overdue", "Upcoming", "Someday", "Completed"]
      .map((group) => {
        const items = tasks.filter((task) => OrbitPlanner.dateGroup(planItem(task), t) === group).sort(order);
        if (!items.length) return "";
        return group === "Completed"
          ? `<details class="completed-items"><summary class="section-label"><h2>${items.length} completed</h2><span>Done</span></summary>${checklist(items)}</details>`
          : sectionLabel(group, String(items.length)) + checklist(items);
      })
      .join("");
  } else {
    const overdue = tasks.filter(
      (task) => !task.completedAt && taskDate(task) && taskDate(task) < days[0] && task.listID !== SOMEDAY,
    );
    body =
      (overdue.length ? sectionLabel("Overdue", `${overdue.length} to review`) + checklist(overdue) : "") +
      days
        .map((key) => {
          const items = inRange.filter((task) => taskDate(task) === key).sort(order);
          if (!items.length) return "";
          const label = localDay(key).toLocaleDateString([], { weekday: "long", month: "short", day: "numeric" });
          const note = key === t ? "Today" : `${items.filter((i) => i.completedAt).length} of ${items.length} done`;
          return sectionLabel(esc(label), note) + checklist(items);
        })
        .join("");
  }
  const title = { week: "This week", month: "This month", all: "Everything" }[todayScope];
  const empty = { week: "Nothing planned this week.", month: "Nothing planned this month.", all: "No tasks yet." }[
    todayScope
  ];
  return `<div class="today-layout agenda">
    ${head}
    <section class="today-main">
      ${body || `<p class="empty">${empty}</p>`}
    </section>
    <aside class="today-side" aria-label="Plan and habits">
      ${planCard(inRange.filter((task) => task.completedAt).length, inRange.length)}
      ${allHabits.length ? sectionLabel("Habits", todayScope === "all" ? "Since added" : title) + `<div class="check-list">${allHabits.map((h) => habitSummaryRow(h, days)).join("")}</div>` : ""}
    </aside>
  </div>`;
}

function bindToday() {
  bindPickers({
    "progress-range": (value) => {
      progressRange = Number(value);
      localStorage.setItem("progressRange", value);
      render();
    },
  });
  if ($("#dismiss-missed"))
    $("#dismiss-missed").onclick = () => {
      localStorage.setItem("dismissedMissedHabitPromptDay", today());
      render();
    };
  document
    .querySelectorAll("[data-backfill-yesterday]")
    .forEach((button) => (button.onclick = () => action(() => backfillYesterday(button.dataset.backfillYesterday))));
  if ($(".completed-items"))
    $(".completed-items").ontoggle = (e) => {
      completedOpen = e.target.open;
      localStorage.setItem("todayCompletedExpanded", String(completedOpen));
    };
  document.querySelectorAll("[data-day-step]").forEach(
    (b) =>
      (b.onclick = () => {
        selected = OrbitHabits.addDays(selected, Number(b.dataset.dayStep));
        render();
      }),
  );
  if ($("#go-today"))
    $("#go-today").onclick = () => {
      selected = dayKey(new Date());
      render();
    };
}

let progressRange = Number(localStorage.getItem("progressRange")) === 30 ? 30 : 7;
function recentProgressCard(tasks, habits) {
  const normalized = tasks.map((task) => ({
    day: taskDate(task),
    completedDay: task.completedAt ? dayKey(new Date(task.completedAt)) : null,
    isNote: task.isNote,
  }));
  const entries = habits.map((habit) => ({
    ...habit,
    createdDay: habit.createdAt ? dayKey(new Date(habit.createdAt)) : null,
  }));
  const days = Array.from({ length: progressRange }, (_, index) =>
    OrbitHabits.addDays(selected, index - progressRange + 1),
  );
  return `<section class="card recent-progress"><div class="recent-progress-head"><h2>Recent progress</h2>${macPicker(
    "progress-range",
    "Progress range",
    [
      ["7", "Past week"],
      ["30", "Past month"],
    ],
    String(progressRange),
  )}</div><div class="progress-days ${progressRange === 30 ? "month" : "week"}">${days
    .map((key) => {
      const progress = OrbitRecentProgress.day(normalized, entries, habitLogs(), key);
      const date = localDay(key),
        ratio = key > today() ? 0 : progress.ratio;
      const label = `${date.toLocaleDateString([], { month: "short", day: "numeric" })}: ${progress.total ? `${Math.round(ratio * 100)}% complete, ${progress.taskCount} tasks and ${progress.habitCount} habits` : "No scheduled items"}`;
      return `<div class="progress-day" role="img" aria-label="${esc(label)}" title="${esc(label)}"><svg viewBox="0 0 32 32" aria-hidden="true"><circle cx="16" cy="16" r="12" class="progress-track"/><circle cx="16" cy="16" r="12" pathLength="100" stroke-dasharray="${ratio * 100} 100" class="progress-value"/></svg><small>${progressRange === 7 ? date.toLocaleDateString([], { weekday: "narrow" }) : date.getDate()}</small></div>`;
    })
    .join("")}</div></section>`;
}
