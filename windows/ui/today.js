function renderToday(tasks, habits) {
  const relevant=tasks.filter(t=>(!taskDate(t)||taskDate(t)<=selected)&&(!t.completedAt||dayKey(new Date(t.completedAt))===selected));
  const active=relevant.filter(t=>!t.completedAt), complete=relevant.filter(t=>t.completedAt);
  const done=complete.length+habits.filter(h=>progress(h)>=h.target).length,total=relevant.length+habits.length;
  return `<div class="checklist-page">
    <div class="eyebrow">${localDay(selected).toLocaleDateString([],{weekday:'long',month:'long',day:'numeric'}).toUpperCase()}</div>
    <h1>${selected===dayKey(new Date())?'Today':localDay(selected).toLocaleDateString([],{weekday:'long'})}</h1>
    <div class="compact-progress"><span>${done} of ${total} complete</span><progress max="${Math.max(total,1)}" value="${done}" aria-label="Daily progress"></progress></div>
    <div class="section-heading"><h2>To-dos</h2></div>
    ${active.map(taskRow).join('')||'<p class="empty">A clear checklist. Add something with +.</p>'}
    <div class="section-heading"><h2>Non-negotiables</h2></div>
    <div class="habit-grid">${habits.map(habitCard).join('')||'<p class="empty">Choose one small thing to return to.</p>'}</div>
    ${complete.length?`<details class="completed-items"><summary>${complete.length} completed</summary>${complete.map(taskRow).join('')}</details>`:''}
    <form class="quick" id="quick-add"><input name="title" aria-label="Add an intention" placeholder="Add a to-do · gym tomorrow 6am" required maxlength="500"><button type="submit">Add</button></form>
    <div class="day-controls"><input type="date" id="selected-day" aria-label="Selected day" value="${selected}"><button id="go-today">Today</button></div>
    <details class="floating-add"><summary aria-label="Add to-do or non-negotiable">+</summary><div><button id="add-todo">To-do</button><button id="add-habit">+ Habit</button></div></details>
  </div>`;
}
