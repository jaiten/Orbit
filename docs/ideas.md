# Ideas

A running list of features and polish to consider, with notes on how each would be built.
Items move to the README once they ship. Last updated 27 November 2026.

## Shipped (27 November 2026)

- **Recurring tasks** — "Pay rent, monthly, due the 1st". Ticking one off creates the next one with its
  planned day and due date moved forward, so missed ones don't pile up. Stored as a `repeat` rule on
  the task (separate from the old `recurrenceRule`, which older versions turned into habits).
- **Due dates**: due and overdue tasks show on Today even when planned for another day; `due fri` in
  quick add; a due flag on Calendar days; an optional reminder the day before.
- **Calendar (Windows)**: drag tasks between days in Month; click "N more" to open that day; the main
  sidebar collapses to icons instead of disappearing.
- **One date picker on Windows**: the custom calendar replaces every native date field (task editor,
  event editor, quick add rules).
- **Incremental reads on Windows**: each record carries a change number; after a save the window asks
  only for records changed since its last read, and the main process no longer re-reads the whole
  table for undo, sync, reminders or migrations.

## Habits — planned

- **A note with a check-in or a slip** ("slipped at a party", "ran 5k"), shown in History.
  *How:* habit logs gain an optional `note` (synced like any field; both apps keep unknown fields only if
  they know them, so both must add it at once). After a tick, a small "Add a note" link sits under the row
  for a few seconds (Windows: a popover; iPhone: a sheet with one text field). History lists notes by day.
- **"Done this week" for weekly and monthly habits** once their goal is met, instead of a struck-through
  row. *How:* the `finished` state already exists on both apps; when it is true for a period habit, the
  row's detail reads "Done this week ✓" in the accent colour and the row moves under a quiet "Done"
  caption in its card.
- **Avoid habits on iPhone stand apart** like the Windows split (their own Avoiding section on Today, which
  can be hidden or moved), with "kept 12 days" in the row. *How:* TodayView groups avoid habits into a
  separate section with its own visibility toggle in Edit Today.
- **Pause a habit** (holiday, illness) so streaks don't break and reminders stop. *How:* a `pausedUntil`
  day on the habit; while paused it isn't due, isn't counted in progress, and streaks skip those days
  (HabitRules.streak / habits.js `streak` treat paused days like unscheduled ones). Shared cases in
  `shared/test-cases/streaks.json`.

## More ideas

### Planning

- **Weekly review**: a screen each Sunday (or chosen day) with what got done, what kept getting moved
  (Do on… moves are already recorded as date changes), how habits went, and room to plan next week.
- **Time estimates that add up**: Today shows the total of task lengths against the free hours left
  between calendar events ("4 h planned, 3 h free").
- **Snooze to "this evening" / "this weekend"** in the Do on… menu.
- **Task templates**: save a set of tasks ("Trip packing") and drop it onto a day.
- **Subtasks on Windows** (iPhone has them): edit steps in the task editor and tick them in the row.
- **Tags on Windows**: edit tags in the editor and filter Tasks by tag.

### Calendar

- **Two-way calendar edits on Windows** for Google and Outlook accounts linked on the PC (today they are
  read-only besides small edits).
- **Agenda view**: a scrolling list of the next 14 days, tasks and events together.
- **Week numbers** and a mini month in the sidebar for quick jumps.

### Habits

- **Habit reminders that adapt**: nudge at the time you usually check it off, learned from the last
  few weeks.
- **Year view** for a habit: a GitHub-style grid of the whole year.

### Notes

- **Checklists inside notes** that can be turned into tasks one line at a time.
- **Links between notes** (`[[Note title]]`) with a backlinks list.
- **Search inside note bodies** with highlights in the editor.

### Sync and reliability

- **Incremental reads on iPhone** like Windows now has: track a change counter per record so sync and
  widgets only look at what changed. (Sync already downloads only newer records.)
- **Due flags on iPhone's Calendar** and drag between days in its month view, as on Windows.
- **More repeat choices**: every 3 months, specific weekdays ("Mon and Thu"), the last day of the month.
- **Render only visible rows** in Tasks when there are thousands (Windows), keeping the row animations.
- **Encrypted locked notes** end to end, not only hidden on the device.
- **Leaked-password protection** in Supabase Auth (a setting in the Supabase dashboard).

### Widgets and system

- **Interactive due-date widget** (iPhone): what's due this week, tick from the Home Screen.
- **Windows jump list** entries: New task, Today, Calendar.
- **Apple Watch** complication for today's habits.
