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

function renderToday(tasks, allHabits) {
  // Today: dated today or earlier and still open, or finished today. Undated and Someday items stay in Lists.
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
        <div><div class="eyebrow">${eyebrow}</div><h1>${heading}</h1>${isToday ? '<p class="subtitle">Make room for what matters.</p>' : ""}</div>

      </header>
    <section class="today-main">
      ${addField()}
      ${conflictBanner()}
      ${habits.length ? sectionLabel("Habits", `${habitsDone} of ${habits.length}`) + checklist(habits, habitCard) : ""}
      ${overdue.length ? sectionLabel("Overdue") + checklist(overdue) : ""}
      ${timed.length ? sectionLabel("Scheduled", "Time blocks") + checklist(timed) : ""}
      ${untimed.length ? sectionLabel(isToday ? "Today" : heading, "Tasks") + checklist(untimed) : ""}
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
    <aside class="today-side" aria-label="Progress">
      <details class="progress-details"><summary>Progress and history</summary>
      ${planCard(done, total)}
      ${
        allHabits.length
          ? `<div class="card grid-card"><div class="eyebrow">Habits · last 12 weeks</div>${boxGrid(consistencyLevels(allHabits), "accent", "Habits")}</div>`
          : ""
      }
      </details>
    </aside>
  </div>`;
}

function bindToday() {
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
