/** Days for a 12-week grid: whole weeks in the locale's order, ending with the current week. Future days are null. */
function gridDays(weeks = 12) {
  const first = OrbitHabits.addDays(OrbitHabits.weekStartKey(today(), weekStart), -7 * (weeks - 1));
  return Array.from({ length: weeks * 7 }, (_, i) => OrbitHabits.addDays(first, i));
}
/** Share of the day's habits checked, for each day of the grid. */
function consistencyLevels(habits, days = gridDays()) {
  const logs = habitLogs();
  const entries = habits.map((h) => ({ ...h, createdDay: h.createdAt ? plannerDay(h.createdAt) : null }));
  return days.map((key) => (key > today() ? -1 : OrbitHabits.consistency(entries, logs, key)));
}

const checklist = (items, row = taskRow) => `<div class="check-list">${items.map((i) => row(i)).join("")}</div>`;

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

let editingTodayLayout = false;
const todayPanelNames = {
  tasks: "Your day",
  upcoming: "Coming up",
  recent: "Recent progress",
  plan: "Your plan",
  habits: "Habits",
  heatmap: "Overall progress",
};
function todayPanel(id, content, defaultColumn = "side") {
  const stored = JSON.parse(localStorage.getItem("todayPanelLayout") || "null") || {};
  const column = stored[id]?.column || defaultColumn;
  const visibility = { heatmap: false, ...JSON.parse(localStorage.getItem("todayPanelVisibility") || "{}") };
  const visible = id === "tasks" || visibility[id] !== false;
  return `<section class="today-panel" data-today-panel="${id}" data-panel-column="${column}" ${!visible ? "hidden" : ""} ${editingTodayLayout ? 'draggable="true"' : ""}>${editingTodayLayout ? `<div class="panel-tools"><button class="panel-grip" data-move-panel="${id}" aria-label="Move ${todayPanelNames[id]}" title="Drag to move; arrow keys also move panels">⠿ <span>${todayPanelNames[id]}</span></button></div>` : ""}${content}</section>`;
}
/** Edit layout: which panels show, with Overall progress's range beside its own toggle. */
function todayLayoutOptions() {
  const visibility = { heatmap: false, ...JSON.parse(localStorage.getItem("todayPanelVisibility") || "{}") };
  const range = localStorage.getItem("overallProgressRange") === "7" ? "7" : "30";
  const toggle = (id) => {
    const on = visibility[id] !== false;
    return `<label class="layout-toggle ${on ? "on" : ""}"><input type="checkbox" data-panel-visible="${id}" ${on ? "checked" : ""} /><span class="layout-check" aria-hidden="true"></span>${todayPanelNames[id]}</label>`;
  };
  const rangeControl =
    visibility.heatmap !== false
      ? `<span class="scope-tabs layout-range" role="group" aria-label="Overall progress covers">${[
          ["7", "Week"],
          ["30", "Month"],
        ]
          .map(
            ([value, label]) =>
              `<button type="button" data-overall-range="${value}" class="${range === value ? "selected" : ""}" aria-pressed="${range === value}">${label}</button>`,
          )
          .join("")}</span>`
      : "";
  return `<div class="today-layout-options" role="group" aria-label="Visible panels">
    <span class="layout-heading">Show on Today</span>
    ${["upcoming", "recent", "plan", "habits"].map(toggle).join("")}
    <span class="layout-group">${toggle("heatmap")}${rangeControl}</span>
    <span class="layout-hint">Drag panels to move them</span>
  </div>`;
}
/** The next seven days from Calendar: scheduled tasks by day, so what's ahead shows on Today. */
function upcomingCard(tasks) {
  const t = today();
  const tomorrowKey = OrbitHabits.addDays(t, 1),
    end = OrbitHabits.addDays(t, 7);
  const items = tasks
    .filter((task) => !task.isNote && !task.completedAt && taskDate(task) > t && taskDate(task) <= end)
    .sort(
      (a, b) =>
        taskDate(a).localeCompare(taskDate(b)) ||
        (a.hasTime ? a.dueDate : Infinity) - (b.hasTime ? b.dueDate : Infinity),
    );
  const shown = items.slice(0, 8);
  let lastDay = "";
  const rows = shown
    .map((task) => {
      const key = taskDate(task);
      const label =
        key === tomorrowKey
          ? "Tomorrow"
          : localDay(key).toLocaleDateString([], { weekday: "long", month: "short", day: "numeric" });
      const head = key !== lastDay ? `<div class="upcoming-day">${esc(label)}</div>` : "";
      lastDay = key;
      return `${head}<button class="upcoming-row" data-edit="${esc(task.id)}" aria-label="Edit ${esc(task.title)}"><span class="upcoming-time">${task.hasTime ? esc(calendarTime(task.dueDate)) : ""}</span><span class="upcoming-title">${esc(task.title)}</span></button>`;
    })
    .join("");
  const more = items.length - shown.length;
  return `<section class="card upcoming-card"><div class="recent-progress-head"><h2>Coming up</h2><span class="secondary">Next 7 days</span></div>${
    rows || '<p class="upcoming-empty">Nothing scheduled for the next week.</p>'
  }${more > 0 ? `<button class="upcoming-more" data-open-calendar>${more} more in Calendar</button>` : ""}</section>`;
}
function overallProgressCard(tasks, habits) {
  const normalized = tasks.map((task) => ({
    day: taskDate(task),
    completedDay: task.completedAt ? plannerDay(task.completedAt) : null,
    isNote: task.isNote,
  }));
  const entries = habits.map((habit) => ({
    ...habit,
    createdDay: habit.createdAt ? plannerDay(habit.createdAt) : null,
  }));
  const count = localStorage.getItem("overallProgressRange") === "7" ? 7 : 30;
  const days = Array.from({ length: count }, (_, index) => OrbitHabits.addDays(today(), index - count + 1));
  const cells = days
    .map((key) => {
      const result = OrbitRecentProgress.day(
        normalized,
        entries,
        habitLogs(),
        key,
        localStorage.getItem("progressIncludesTasks") !== "false",
      );
      return `<div class="overall-day" data-o="${result.ratio ? (0.25 + result.ratio * 0.75).toFixed(2) : "0"}" role="img" aria-label="${key}: ${Math.round(result.ratio * 100)}% complete" title="${key}: ${Math.round(result.ratio * 100)}% complete"></div>`;
    })
    .join("");
  return `<section class="card overall-progress"><div class="recent-progress-head"><h2>Overall progress</h2><span class="secondary">${count === 7 ? "Past week" : "Past month"}</span></div><div class="overall-days ${count === 7 ? "week" : "month"}" role="group" aria-label="Daily progress, oldest first">${cells}</div></section>`;
}
/**
 * A habit on Today: the whole row logs one check-in (and undoes a completed one), so there are no
 * hover actions to get in the way. Right-click or E edits it.
 */
function compactHabit(h) {
  const done = checked(h),
    id = esc(h.id),
    title = esc(h.title);
  return `<div class="row habit-row habit-${colorName(h.color)} check-tile ${done ? "complete" : ""}" data-flip="habit-${id}" data-row-menu="habit:${id}">
    <button class="row-line habit-log" role="checkbox" aria-label="${done ? "Undo" : "Log"} ${title}" aria-checked="${done}" data-habit-toggle="${id}" data-habit-day="${today()}" data-habit-menu="${id}">${tick(done, poppedID === h.id)}<span class="row-title">${title}</span><span class="row-detail ${done ? "met" : ""}">${progress(h)} of ${h.target}</span></button>
  </div>`;
}
function renderToday(tasks, allHabits) {
  // Today: dated today or earlier and still open, or finished today. Undated and Someday items stay in Notes.
  // Today is always the current day; past days are reviewed in Calendar.
  const day = today();
  const relevant = tasks.filter((t) => OrbitPlanner.onDay(planItem(t), day, day));
  const habits = allHabits.filter((h) => (!h.createdAt || plannerDay(h.createdAt) <= day) && dueOn(h));
  const open = relevant.filter((t) => !t.completedAt),
    complete = relevant.filter((t) => t.completedAt);
  // Timed tasks first, in time order; then the rest as arranged.
  open.sort((a, b) => (a.hasTime ? a.dueDate : Infinity) - (b.hasTime ? b.dueDate : Infinity));
  // Tasks from earlier days simply stay on Today with the rest; the user moves them when they like.
  const timed = open.filter((t) => t.hasTime),
    untimed = open.filter((t) => !t.hasTime);
  const habitsDone = habits.filter((h) => checked(h)).length;
  const includeTasks = localStorage.getItem("progressIncludesTasks") !== "false";
  const done = (includeTasks ? complete.length : 0) + habitsDone,
    total = (includeTasks ? relevant.length : 0) + habits.length;
  const eyebrow = longDate(day);
  const agenda = `      ${focusBanner()}
      ${conflictBanner()}
      ${timed.length ? sectionLabel("On the agenda", "Time blocks") + checklist(timed) : ""}
      ${untimed.length ? sectionLabel("At your own pace", "To-dos") + checklist(untimed) : ""}
      ${
        open.length
          ? ""
          : complete.length
            ? `<div class="empty-state today-empty done"><span class="today-empty-mark" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="m6 12.5 4 4 8-9"/></svg></span><p><strong>All done for today</strong><br />${complete.length} ${complete.length === 1 ? "task" : "tasks"} finished. Enjoy the rest of your day.</p></div>`
            : `<div class="empty-state today-empty"><span class="today-empty-mark" aria-hidden="true"><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.9 4.9l1.4 1.4m11.4 11.4 1.4 1.4M2 12h2m16 0h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg></span><p><strong>Nothing planned yet</strong><br />Start typing to add a task, or press Ctrl+N.</p></div>`
      }
      ${
        complete.length
          ? `<details class="completed-items" ${completedOpen ? "open" : ""}>
              <summary class="section-label" aria-label="${complete.length} completed"><h2>${complete.length} completed</h2><svg class="ui-icon completed-arrow" viewBox="0 0 24 24" aria-hidden="true"><path d="m8 10 4 4 4-4"/></svg></summary>
              ${checklist(complete)}
            </details>`
          : ""
      }
`;
  return `<div class="today-layout">
    <header class="page-head"><div><div class="eyebrow">${eyebrow}</div><h1>Today</h1></div><div class="head-tools">
      <button id="home-update" class="icon-button home-update" hidden aria-label="Update available" title="Update available"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v12m-5-5 5 5 5-5M4 17v4h16v-4"/></svg><i aria-hidden="true"></i></button>
      <button id="edit-today-layout" class="icon-button" aria-label="${editingTodayLayout ? "Finish editing layout" : "Edit layout"}" title="${editingTodayLayout ? "Finish editing layout" : "Edit layout"}" aria-pressed="${editingTodayLayout}"><svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="${editingTodayLayout ? "m5 12 4 4L19 6" : "M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z"}"/></svg></button>
    </div></header>
    ${editingTodayLayout ? todayLayoutOptions() : ""}
    <div class="today-board ${editingTodayLayout ? "editing" : ""}">
      ${editingTodayLayout ? `<div id="today-column-resizer" role="separator" tabindex="0" aria-label="Today column widths" aria-orientation="vertical" aria-valuemin="35" aria-valuemax="75" title="Drag to resize columns; arrow keys also adjust"></div>` : ""}
      <section class="today-main today-panel-column" data-panel-drop="main">${todayPanel("tasks", agenda, "main")}</section>
      <aside class="today-side today-panel-column" data-panel-drop="side" aria-label="Plan and progress">
        ${todayPanel("upcoming", upcomingCard(tasks))}
        ${todayPanel("recent", recentProgressCard(tasks, allHabits))}
        ${todayPanel("plan", planCard(done, total))}
        ${todayPanel("habits", `<section class="card habits-compact-card">${sectionLabel("Habits", `${habitsDone} of ${habits.length}`)}<div class="check-list compact-habits">${habits.map(compactHabit).join("")}</div></section>`, habits.length > 6 ? "main" : "side")}
        ${todayPanel("heatmap", overallProgressCard(tasks, allHabits))}
      </aside>
    </div>
    <div class="capture-dock">${addField()}</div>
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
  const created = h.createdAt ? plannerDay(h.createdAt) : null;
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
    body = ["Today", "Upcoming", "Someday", "Completed"]
      .map((group) => {
        const items = tasks.filter((task) => OrbitPlanner.dateGroup(planItem(task), t) === group).sort(order);
        if (!items.length) return "";
        return group === "Completed"
          ? `<details class="completed-items"><summary class="section-label"><h2>${items.length} completed</h2><span>Done</span></summary>${checklist(items)}</details>`
          : sectionLabel(group, String(items.length)) + checklist(items);
      })
      .join("");
  } else {
    // Open tasks from earlier days are shown on today, like Today does.
    const earlier = (task) => !task.completedAt && taskDate(task) && taskDate(task) < t && task.listID !== SOMEDAY;
    body = days
      .map((key) => {
        const items = tasks.filter((task) => (earlier(task) ? key === t : taskDate(task) === key)).sort(order);
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
  document.querySelectorAll("[data-panel-visible]").forEach((toggle) => {
    toggle.onchange = () => {
      const visibility = { heatmap: false, ...JSON.parse(localStorage.getItem("todayPanelVisibility") || "{}") };
      visibility[toggle.dataset.panelVisible] = toggle.checked;
      localStorage.setItem("todayPanelVisibility", JSON.stringify(visibility));
      render();
    };
  });
  if ($("#edit-today-layout"))
    $("#edit-today-layout").onclick = () => {
      editingTodayLayout = !editingTodayLayout;
      render();
      $("#edit-today-layout")?.focus();
    };
  bindTodayBoard();
  document.querySelectorAll(".overall-day[data-o]").forEach((cell) => cell.style.setProperty("--o", cell.dataset.o));
  document.querySelectorAll("[data-overall-range]").forEach(
    (button) =>
      (button.onclick = () => {
        localStorage.setItem("overallProgressRange", button.dataset.overallRange);
        render();
      }),
  );
  document.querySelectorAll("[data-open-calendar]").forEach((button) => (button.onclick = () => goTo("calendar")));
  if ($(".completed-items"))
    $(".completed-items").ontoggle = (e) => {
      completedOpen = e.target.open;
      localStorage.setItem("todayCompletedExpanded", String(completedOpen));
    };
}

const progressRange = 7;
function recentProgressCard(tasks, habits) {
  const normalized = tasks.map((task) => ({
    day: taskDate(task),
    completedDay: task.completedAt ? plannerDay(task.completedAt) : null,
    isNote: task.isNote,
  }));
  const entries = habits.map((habit) => ({
    ...habit,
    createdDay: habit.createdAt ? plannerDay(habit.createdAt) : null,
  }));
  const days = Array.from({ length: progressRange }, (_, index) =>
    OrbitHabits.addDays(today(), index - progressRange + 1),
  );
  return `<section class="card recent-progress"><div class="recent-progress-head"><h2>Recent progress</h2><span class="secondary">Past week</span></div><div class="progress-days week">${days
    .map((key) => {
      const progress = OrbitRecentProgress.day(
        normalized,
        entries,
        habitLogs(),
        key,
        localStorage.getItem("progressIncludesTasks") !== "false",
      );
      const date = localDay(key),
        ratio = key > today() ? 0 : progress.ratio;
      const label = `${date.toLocaleDateString([], { month: "short", day: "numeric" })}: ${progress.total ? `${Math.round(ratio * 100)}% complete, ${progress.taskCount} tasks and ${progress.habitCount} habits` : "No scheduled items"}`;
      return `<div class="progress-day" data-progress-day="${key}" role="img" aria-label="${esc(label)}" title="${esc(label)}"><svg viewBox="0 0 32 32" aria-hidden="true"><circle cx="16" cy="16" r="12" class="progress-track"/><circle cx="16" cy="16" r="12" pathLength="100" stroke-dasharray="${ratio >= 1 ? "none" : `${ratio * 100} 100`}" class="progress-value"/></svg><small>${progressRange === 7 ? date.toLocaleDateString([], { weekday: "narrow" }) : date.getDate()}</small></div>`;
    })
    .join("")}</div></section>`;
}
