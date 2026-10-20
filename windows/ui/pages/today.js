function renderToday(tasks, allHabits) {
  // Today: dated today or earlier and still open, or finished today. Undated and Someday items stay in Lists.
  const relevant = tasks.filter((t) => OrbitPlanner.onDay(planItem(t), selected, today()));
  const habits = allHabits.filter((h) => dueOn(h));
  const active = relevant.filter((t) => !t.completedAt),
    complete = relevant.filter((t) => t.completedAt),
    pendingHabits = habits.filter((h) => !checked(h)),
    doneHabits = habits.filter((h) => checked(h));
  const done = complete.length + doneHabits.length,
    total = relevant.length + habits.length;
  const date = localDay(selected);
  const oneOff = active.map(taskRow).join("");
  const routine = pendingHabits.map(habitCard).join("");
  const completed = complete.length + doneHabits.length;
  const heading = selected === dayKey(new Date()) ? "Today" : date.toLocaleDateString([], { weekday: "long" });
  const eyebrow = date.toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" }).toUpperCase();
  return `<div class="checklist-page">
    <div class="eyebrow">${eyebrow}</div>
    <h1>${heading}</h1>
    <div class="compact-progress">
      <span>${done} of ${total} done</span>
      <progress max="${Math.max(total, 1)}" value="${done}" aria-label="Daily progress"></progress>
    </div>
    <div class="section-heading"><h2>Tasks</h2></div>
    <div class="check-grid">${oneOff || '<p class="empty">Nothing planned for today.</p>'}</div>
    ${routine ? `<div class="section-heading"><h2>Habits</h2></div><div class="check-grid">${routine}</div>` : ""}
    ${
      completed
        ? `<details class="completed-items" ${completedOpen ? "open" : ""}>
            <summary>${completed} completed</summary>
            <div class="check-grid">${complete.map(taskRow).join("") + doneHabits.map(habitCard).join("")}</div>
          </details>`
        : ""
    }
    <div class="day-controls">
      <input type="date" id="selected-day" aria-label="Selected day" value="${selected}" /><button id="go-today">Today</button>
    </div>
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
