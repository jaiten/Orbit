# iOS acceptance checklist

Automated builds run on GitHub's macOS simulator and Windows runners. Manual
device checks below remain outstanding; simulator success does not verify physical
iPhone notifications, widgets or real-device sync.

- [x] Generate with XcodeGen; build the app and extension without compiler errors.
- [x] Run the XCTest suite, including the shared rule tables, persisted deletion sync and account isolation.
- [ ] First launch shows onboarding once; examples are only added by Try example tasks and Remove Examples deletes only them.
- [ ] Notifications are requested only after adding a timed item or habit, never at launch.
- [ ] Quick-add `gym tomorrow 6am`; find it on tomorrow in Plan and after relaunch.
- [ ] Create/edit/delete a list. Deleting it preserves tasks in Inbox.
- [ ] Create/edit/cancel/delete a task with notes, tags, subtasks and two reminders.
- [ ] Upgrade from a build with repeating tasks; each becomes a habit with its past completions as check-ins.
- [ ] Reorder at least three to-dos; relaunch and verify the order is preserved.
- [ ] Drag a time block to another day; verify its time and reminder offsets.
- [ ] Navigate across month/year boundaries and daylight-saving transitions.
- [ ] Log a multi-count daily habit, reach its target, undo a log, and relaunch.
- [ ] Log a weekly habit across two days; verify the shared weekly target and “X of the last 7 days”.
- [ ] Delete a habit and verify its logs and pending reminders disappear.
- [ ] Enter two ideas; verify rotation and dismissal/restore without generated text.
- [ ] Enable/deny notifications; create near-term reminders and verify on a device.
- [ ] Finish a habit before its nudge; verify the pending nudge is cancelled.
- [ ] Add every widget size; verify the same records as the app and tap-to-complete.
- [ ] Reopen app after a widget edit; verify external store changes are visible.
- [ ] Rapidly log from app/widget; check for duplicate per-day rows or lost counts.
- [ ] Widget completions reschedule notifications; the Checklist style ticks items in place.
- [ ] Share text and a link from Safari; Add to Orbit and Complete Item run from Shortcuts and Siri.
- [ ] Check light/dark, largest accessibility text, VoiceOver, Reduce Motion,
  landscape, iPad multitasking, and long task titles for clipping or lost controls.
- [ ] Try midnight rollover and changing device time zone with the app open.
- [ ] Revoke App Group entitlement or make the store unavailable; verify an error
  rather than data replacement. Do not perform this check on a store with real data.

Known device-validation risks: SwiftData cross-process merge visibility, concurrent
habit count updates, notification permission behavior from an extension, and OS
timeline scheduling. Resolve observed failures before calling the prototype verified.

## Orbit interface pass

- [ ] Confirm the Home Screen name, Settings title and widget gallery say Orbit.
- [ ] Verify the real system status bar remains legible in system/light/dark modes.
- [ ] Check the large title collapses naturally and the tab bar respects the home indicator.
- [ ] Open/dismiss the quick-add keyboard; the field and last task remain reachable.
- [ ] Select a past day, log/undo a habit, and confirm the selected date's history changes.
- [ ] Select a future date; habit completion must be unavailable.
- [ ] A partial multi-count daily habit contributes a fraction to the ring; weekly
      targets must not affect daily completion totals.
- [ ] At midnight or foreground after a date change, Today follows the new date only
      if the selected date was the previous current day.
- [ ] Enable Reduce Motion; date selection, rings and task symbols must not animate.
- [ ] Check timed agenda rows stack their time labels at accessibility text sizes.
- [ ] Verify all theme colors and selected dates retain readable contrast in dark mode.


## iOS capture and Lock Screen polish

- From Today, add two tasks with Return without reopening capture. Each Return saves,
  clears the field, keeps the keyboard ready, and shows the last added title. Empty
  Return does nothing. Done closes; Save adds the current draft and closes.
- Repeat from a selected list and a future Calendar day; both items keep that context.
  Check a repeating phrase still creates a habit. Confirm and cancel a time conflict;
  confirming after Return must leave capture ready for another item. On a save error,
  the draft must remain available to retry.
- In the Lock Screen gallery, add Today in circular, rectangular and inline sizes.
  Select Progress, Checklist and Grid in each. Progress counts tasks and habits;
  Checklist shows actionable items (inline opens Orbit); Grid shows a compact week.
- Add Habit consistency in all three Lock Screen sizes and switch Follow Today,
  Past week and Past month. Check empty history, all completed, unavailable storage,
  long titles, tinted rendering, and completion while locked (including any system
  authentication prompt). Confirm existing Home Screen widgets still render normally.


## iOS daily flow polish

- Tap a task title and a habit title on Today, Lists, Calendar and Habits where
  available: each must open details without recording progress. Check controls
  must be at least 44 points and keep task completion and habit logging separate.
- Complete a task and a habit. Expand Completed, reopen the task, and undo the
  habit check. For multi-count habits, verify each check advances the count until
  the target is met. Verify hiding Completed and customizing section order still work.
- Long press tasks and habits on Today. Convert in both directions through their
  menus, then undo. Scrolling or dragging a row must never convert it.
- Verify today's scheduled tasks appear before overdue items; Today / Later /
  Someday still move overdue tasks correctly. Check empty days and all-done days.
- With long titles, accessibility text sizes and Reduce Motion, check row controls,
  scrolling, the compact summary and Completed disclosure. Verify the Add field
  remains near the top when progress is hidden or moved in Edit Today.


## Habit-first homepage

- With the default layout, verify Habits precedes Your day and the summary shows
  separate habit/task counts. Add a habit directly from the empty homepage.
- Complete a habit, add a task, and complete that task; each action must update only
  its corresponding summary count. Recent progress represents habit history.
- Upgrade the old default layout and verify habits/history become visible in their
  new positions. Custom orders, pins and hidden sections must remain as configured.
- Check no-habit, no-task and all-done states, large text, light/dark appearance,
  and a busy day on the phone before accepting the new hierarchy.


## Clearer planning pass

- From a fresh or previous-default layout, Today has no evening review, the
  progress/history cards are optional, and Habits/Your day each show their counts.
- Previously enabled Daily check-in notifications stop after an app refresh;
  explicitly configured task/habit reminders continue to work.
- Quick capture: select another day without a typed date, select a list, save
  several items with Return, and verify the context is retained. Selecting Someday
  removes the default day; an explicit day in the text still takes precedence.
- Lists: + creates a list. Add a task creates a task. Collapse/reopen each date
  group. Edit Lists adds, renames and deletes lists without deleting their tasks.
- Turn Compact habits and tasks on and off. At the largest accessibility text size,
  check long titles, stacked details, menus, onboarding scrolling and all check
  targets. Check the native Calendar day picker and Save controls with the keyboard.
- Calendar: choose a future day and use Add task for that date. Verify it appears
  under Upcoming in Lists and is absent from Today.
- Planning on an iPhone: deny/grant calendar access; choose a writable calendar;
  preview selected habits and tasks with durations around overlapping appointments,
  free events, explicitly busy all-day events, timed tasks and a too-short window.
- Change an appointment after previewing. Saving must require a fresh plan if a
  conflict appears. Saving twice/reopening must not duplicate linked blocks.
- Confirm calendar blocks have the reviewed titles, starts and durations; task
  times update in Orbit and do not appear twice in its calendar. Explicit task
  reminder dates must stay unchanged when a calendar start time is assigned. Completing a habit
  or task keeps the calendar block. Delete a block externally and plan it again.
- Confirm habit calendar durations survive relaunch on the iPhone. Multi-count
  habits get one block, not their full target number. Calendar permission and
  calendar writes are physical-device acceptance checks, not established by CI.
