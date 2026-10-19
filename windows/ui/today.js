function renderToday(tasks, habits) {
  const active = tasks.filter(t => taskDate(t) === selected && !t.completedAt);
  const complete = tasks.filter(t => taskDate(t) === selected && t.completedAt);
  const daily = habits.filter(h => h.frequencyRule === 'DAILY');
  const habitFraction = daily.reduce((s,h) => s + Math.min(progress(h)/h.target,1),0);
  const total = tasks.filter(t => taskDate(t) === selected).length + daily.length;
  const done = complete.length + daily.filter(h => progress(h) >= h.target).length;
  const scheduled = active.filter(t=>t.hasTime).sort((a,b)=>a.dueDate-b.dueDate);
  const flexible = active.filter(t=>!t.hasTime);
  const count = habits.filter(h=>progress(h)>=h.target).length;
  let cells = '';
  for(let i=27;i>=0;i--){
    const d=localDay(selected);d.setDate(d.getDate()-i);const key=dayKey(d);
    const logged=rows('habit_logs').filter(l=>l.dayKey===key&&habits.some(h=>h.id===l.habitID)).reduce((s,l)=>s+l.count,0);
    cells+=`<span class="${logged?'logged':''}" title="${key}: ${logged} check-ins" aria-label="${key}: ${logged} check-ins"></span>`;
  }
  return `<div class="today-layout"><section class="agenda-column">
    <div class="eyebrow">${localDay(selected).toLocaleDateString([],{weekday:'long',month:'long',day:'numeric'}).toUpperCase()}</div>
    <h1>${selected===dayKey(new Date())?'Today':localDay(selected).toLocaleDateString([],{weekday:'long'})}</h1>
    <p class="subtitle">Make room for what matters.</p>
    <form class="quick" id="quick-add"><input name="title" aria-label="Add an intention" placeholder="＋ Add a task · gym tomorrow 6am" required maxlength="500"><button type="submit">Add</button></form>
    <div class="section-heading"><h2>On the agenda</h2><span>TIME BLOCKS</span></div>
    ${scheduled.map(taskRow).join('')||'<p class="empty">A little open space. Add a time when you’re ready.</p>'}
    <div class="section-heading"><h2>At your own pace</h2><span>TO-DOS</span></div>
    ${flexible.map(taskRow).join('')||'<p class="empty">What’s one small thing you’d like to do?</p>'}
    ${active.length>5?'<div class="focus-note">A full day ahead. Moving something to tomorrow can make a little room.</div>':''}
    ${complete.length?`<details><summary>${complete.length} completed</summary>${complete.map(taskRow).join('')}</details>`:''}
    <div class="day-controls"><input type="date" id="selected-day" aria-label="Selected day" value="${selected}"><button id="go-today">Today</button></div>
  </section><section class="rhythm-column" aria-label="Daily rhythm and habits">
    <div class="rhythm-card"><div class="eyebrow">YOUR DAILY RHYTHM</div><div class="rhythm-count" aria-live="polite">${done} of ${total} complete</div>
      <div class="progress-track"><progress max="${Math.max(total,1)}" value="${complete.length+habitFraction}" aria-label="Daily progress"></progress></div>
    </div>
    <div class="section-heading"><h2>Non-negotiables</h2><span>${count}/${habits.length}</span></div>
    <div class="habit-grid">${habits.map(habitCard).join('')||'<p class="empty">A small habit is a good place to start.</p>'}</div>
    <button id="add-habit" class="quiet-add">+ Habit</button>
    <div class="rhythm-card history"><div class="eyebrow">LAST 4 WEEKS</div><div class="heatmap" aria-label="Habit check-ins for the last four weeks">${cells}</div></div>
  </section></div>`;
}
