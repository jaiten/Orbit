function consistencyGrid(habits, days = 28) {
  const logs = habitLogs();
  const entries = habits.map((h) => ({ ...h, createdDay: h.createdAt ? dayKey(new Date(h.createdAt)) : null }));
  const cells = Array.from({ length: days }, (_, i) => {
    const key = OrbitHabits.addDays(today(), i - days + 1);
    const value = OrbitHabits.consistency(entries, logs, key);
    return `<i class="l${Math.round(value * 4)}" title="${key}: ${Math.round(value * 100)}%"></i>`;
  }).join("");
  return `<div class="consistency-grid" aria-label="Habit consistency, last 4 weeks">${cells}</div>`;
}

function renderToday(tasks, allHabits) {
  // Today: dated today or earlier and still open, or finished today. Undated and Someday items stay in Lists.
  const relevant = tasks.filter((t) => OrbitPlanner.onDay(planItem(t), selected, today()));
  const habits = allHabits.filter((h) => dueOn(h));
  const open = relevant.filter((t) => !t.completedAt),
    complete = relevant.filter((t) => t.completedAt);
  // Timed tasks first, in time order; then the rest as arranged.
  open.sort((a, b) => (a.hasTime ? a.dueDate : Infinity) - (b.hasTime ? b.dueDate : Infinity));
  const habitsDone = habits.filter((h) => checked(h)).length;
  const done = complete.length + habitsDone,
    total = relevant.length + habits.length;
  const date = localDay(selected);
  const heading = selected === today() ? "Today" : date.toLocaleDateString([], { weekday: "long" });
  const eyebrow = date.toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" }).toUpperCase();
  return `<div class="today-layout">
    <section class="today-main">
      <div class="eyebrow">${eyebrow}</div>
      <h1>${heading}</h1>
      ${conflictBanner()}
      <div class="section-heading"><h2>Tasks</h2><span>${open.length || ""}</span></div>
      <div class="check-list">${open.map(taskRow).join("") || '<p class="empty">Nothing planned for today.</p>'}</div>
      ${
        complete.length
          ? `<details class="completed-items" ${completedOpen ? "open" : ""}>
              <summary>${complete.length} completed</summary>
              <div class="check-list">${complete.map(taskRow).join("")}</div>
            </details>`
          : ""
      }
      <div class="day-controls">
        <input type="date" id="selected-day" aria-label="Selected day" value="${selected}" /><button id="go-today">Today</button>
      </div>
    </section>
    <aside class="today-side" aria-label="Progress">
      <div class="card progress-card">
        <div class="caption">Today</div>
        <div class="progress-value">${done} of ${total} done</div>
        <progress max="${Math.max(total, 1)}" value="${done}" aria-label="Daily progress"></progress>
      </div>
      ${
        habits.length
          ? `<div class="section-heading"><h2>Habits</h2><span>${habitsDone}/${habits.length}</span></div>
             <div class="check-list">${habits.map(habitCard).join("")}</div>`
          : ""
      }
      ${allHabits.length ? `<div class="card"><div class="caption">Last 4 weeks</div>${consistencyGrid(allHabits)}</div>` : ""}
    </aside>
  </div>`;
}

function bindToday() {
  if ($(".completed-items"))
    $(".completed-items").ontoggle = (e) => {
      completedOpen = e.target.open;
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
