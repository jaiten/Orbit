# iOS acceptance checklist

These checks still need a Mac and iOS simulator/device. No boxes below imply a
completed manual test.

- [ ] Generate with XcodeGen; build the app and extension without compiler errors.
- [ ] Run all nine XCTest cases.
- [ ] First launch is empty; sample data is only created by the explicit button.
- [ ] Quick-add `gym tomorrow 6am`; find it on tomorrow in Plan and after relaunch.
- [ ] Create/edit/delete a list. Deleting it preserves tasks in Inbox.
- [ ] Create/edit/cancel/delete a task with notes, tags, subtasks and two reminders.
- [ ] Complete, reopen and recomplete a recurring task; only one successor exists.
- [ ] Reorder at least three to-dos; relaunch and verify the order is preserved.
- [ ] Drag a time block to another day; verify its time and reminder offsets.
- [ ] Navigate across month/year boundaries and daylight-saving transitions.
- [ ] Log a multi-count daily habit, reach its target, undo a log, and relaunch.
- [ ] Log a weekly habit across two days; verify the shared weekly target and streak.
- [ ] Delete a habit and verify its logs and pending reminders disappear.
- [ ] Enter two ideas; verify rotation and dismissal/restore without generated text.
- [ ] Enable/deny notifications; create near-term reminders and verify on a device.
- [ ] Finish a habit before its nudge; verify the pending nudge is cancelled.
- [ ] Add every widget size; verify the same records as the app and tap-to-complete.
- [ ] Reopen app after a widget edit; verify external store changes are visible.
- [ ] Rapidly log from app/widget; check for duplicate per-day rows or lost counts.
- [ ] Widget completions create recurrence successors and reschedule notifications.
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
