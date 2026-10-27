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

let todayScope = "day";
const SCOPES = [
  ["day", "Day"],
  ["week", "Week"],
  ["month", "Month"],
  ["all", "All"],
];
function scopeTabs() {
  return `<div class="scope-tabs" role="tablist" aria-label="Show">${SCOPES.map(
    ([id, label]) =>
      `<button role="tab" data-scope="${id}" aria-selected="${todayScope === id}" class="${todayScope === id ? "selected" : ""}">${label}</button>`,
  ).join("")}</div>`;
}

function renderToday(tasks, allHabits) {
  if (todayScope !== "day") return renderAgenda(tasks, allHabits);
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
  // The history card follows one habit, as on the website: the one with the most recent check-ins.
  const recent = (h) => consistencyLevels([h]).filter((level) => level > 0).length;
  const featured = [...allHabits].sort((a, b) => recent(b) - recent(a))[0];
  return `<div class="today-layout">
    <header class="page-head">
        <div><div class="eyebrow">${eyebrow}</div><h1>${heading}</h1>${isToday ? '<p class="subtitle">Make room for what matters.</p>' : ""}</div>
        ${scopeTabs()}
      </header>
    <section class="today-main">
      ${focusBanner()}
      ${addField()}
      ${conflictBanner()}
      ${missedYesterdayPrompt(allHabits)}
      ${overdue.length ? sectionLabel("Overdue", `${overdue.length} to review`) + checklist(overdue) : ""}
      ${timed.length ? sectionLabel("On the agenda", "Time blocks") + checklist(timed) : ""}
      ${untimed.length ? sectionLabel("At your own pace", "To-dos") + checklist(untimed) : ""}
      ${open.length ? "" : '<p class="empty">Nothing planned for today.</p>'}
      ${
        complete.length
          ? `<details class="completed-items" ${completedOpen ? "open" : ""}>
              <summary class="section-label"><h2>${complete.length} completed</h2><span>Done</span></summary>
              ${checklist(complete)}
            </details>`
          : ""
      }
      <div class="day-controls">
        <input type="date" id="selected-day" aria-label="Selected day" value="${selected}" /><button id="go-today">Today</button>
      </div>
    </section>
    <aside class="today-side" aria-label="Plan and habits">
      ${planCard(done, total)}
      ${habits.length ? sectionLabel("Habits", `${habitsDone} of ${habits.length}`) + checklist(habits, habitCard) : ""}
      ${
        featured
          ? `<div class="card grid-card"><div class="eyebrow">${esc(featured.title)} · Last 12 weeks</div>${boxGrid(consistencyLevels([featured]), colorName(featured.color), featured.title)}</div>`
          : ""
      }
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
    ${itemIcon(h.icon || "automatic", h.title)}<span class="row-title">${esc(h.title)}</span>
    <span class="row-detail">${due ? `${done} of ${due} days` : "Not due yet"}</span>
    <span class="mini-bar fill-${colorName(h.color)}" aria-hidden="true"><i data-fill="${due ? done / due : 0}"></i></span>
  </button>`;
}

/** Week, month and everything: tasks by day (or by when) and how each habit is going. */
function renderAgenda(tasks, allHabits) {
  const t = today();
  const days = todayScope === "all" ? [] : scopeDays();
  const inRange = todayScope === "all" ? tasks : tasks.filter((task) => days.includes(taskDate(task)));
  const order = (a, b) =>
    !!a.completedAt - !!b.completedAt || (a.hasTime ? a.dueDate : Infinity) - (b.hasTime ? b.dueDate : Infinity);
  let body = "";
  if (todayScope === "all") {
    body = ["Today", "Overdue", "Upcoming", "No date", "Someday", "Completed"]
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
    <header class="page-head">
      <div><div class="eyebrow">${localDay(t).toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" })}</div><h1>${title}</h1><p class="subtitle">Every task and habit, at a glance.</p></div>
      ${scopeTabs()}
    </header>
    <section class="today-main">
      ${focusBanner()}
      ${addField()}
      ${body || `<p class="empty">${empty}</p>`}
    </section>
    <aside class="today-side" aria-label="Plan and habits">
      ${planCard(inRange.filter((task) => task.completedAt).length, inRange.length)}
      ${allHabits.length ? sectionLabel("Habits", todayScope === "all" ? "Since added" : title) + `<div class="check-list">${allHabits.map((h) => habitSummaryRow(h, days)).join("")}</div>` : ""}
    </aside>
  </div>`;
}

function bindToday() {
  document.querySelectorAll("[data-scope]").forEach(
    (b) =>
      (b.onclick = () => {
        todayScope = b.dataset.scope;
        render();
        $(`[data-scope="${todayScope}"]`)?.focus();
      }),
  );
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
  if ($("#selected-day"))
    $("#selected-day").onchange = (e) => {
      selected = e.target.value || dayKey(new Date());
      render();
    };
  if ($("#go-today"))
    $("#go-today").onclick = () => {
      selected = dayKey(new Date());
      render();
    };
}
