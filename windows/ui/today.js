function renderToday(tasks, habits) {
  const relevant=tasks.filter(t=>(!taskDate(t)||taskDate(t)<=selected)&&(!t.completedAt||dayKey(new Date(t.completedAt))===selected));
  const active=relevant.filter(t=>!t.completedAt), complete=relevant.filter(t=>t.completedAt),pendingHabits=habits.filter(h=>!checked(h)),doneHabits=habits.filter(h=>checked(h));
  const done=complete.length+habits.filter(h=>checked(h)).length,total=relevant.length+habits.length;
  return `<div class="checklist-page">
    <div class="eyebrow">${localDay(selected).toLocaleDateString([],{weekday:'long',month:'long',day:'numeric'}).toUpperCase()}</div>
    <h1>${selected===dayKey(new Date())?'Today':localDay(selected).toLocaleDateString([],{weekday:'long'})}</h1>
    <div class="compact-progress"><span>${done} of ${total} complete</span><progress max="${Math.max(total,1)}" value="${done}" aria-label="Daily progress"></progress></div>
    <div class="section-heading"><h2>For today</h2><span>ONE-OFF PLANS</span></div>
    <div class="check-grid">${active.filter(t=>!t.recurrenceRule).map(taskRow).join('')||'<p class="empty">Your one-off plans go here.</p>'}</div>
    <div class="section-heading"><h2>Your routine</h2><span>DAILY & WEEKLY</span></div>
    <div class="check-grid">${active.filter(t=>t.recurrenceRule).map(taskRow).join('')+pendingHabits.map(habitCard).join('')||'<p class="empty">Daily habits and weekly commitments.</p>'}</div>
    ${complete.length+doneHabits.length?`<details class="completed-items" ${completedOpen?'open':''}><summary>${complete.length+doneHabits.length} completed</summary><div class="check-grid">${complete.map(taskRow).join('')+doneHabits.map(habitCard).join('')}</div></details>`:''}
    <form class="quick" id="quick-add"><input name="title" aria-label="Add an intention" placeholder="Add a to-do · gym tomorrow 6am" required maxlength="500"><button type="submit">Add</button></form>
    <div class="day-controls"><input type="date" id="selected-day" aria-label="Selected day" value="${selected}"><button id="go-today">Today</button></div>
    <details class="floating-add"><summary aria-label="Add to-do or non-negotiable"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg></summary><div><button id="add-todo">To-do</button><button id="add-habit">+ Habit</button></div></details>
  </div>`;
}
