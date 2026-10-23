# October product direction

Orbit has three jobs: capture a commitment, make a manageable daily plan, and make progress visible. Today is the checklist; Calendar shows available time; Lists stores to-dos that need a home. Habits has deeper history on demand. Ideas is hidden from the product; existing records are preserved.

Today layout and theme preferences are local to each device. Editing the home layout never deletes planner records. Pinned lists show all unfinished items, including future plans. The consistency strip uses current habits that existed on that day; daily targets are fractional and a weekly habit counts a check-in on that day. Deleting a habit removes its history, so this chart is not an immutable historical report.

“Days showing up” counts distinct local dates the app was opened, starting with this update; it is not a fabricated lifetime count or a consecutive streak. Local time suggestions count only the first visit per day, require three visits at a similar daytime hour, and are applied only when the user chooses them. No personal text leaves the device for coaching. Only reminders chosen on individual tasks and habits are sent on iOS.

## Account access

Devices lists real Supabase auth sessions, including sessions from earlier app versions. Multiple sessions can belong to one device. Names come from a client label or a conservative user-agent fallback. No access/refresh tokens or IP addresses are returned.

Removing access stores a revocation for the session ID. Both reads (RLS) and writes (`orbit_put`) check that the JWT session still exists and is not revoked. This blocks sync immediately without changing managed Auth tables. It does not remotely erase local files or prevent a person who knows the password from signing in again. Current-device sign-out calls the Auth local logout endpoint.

`orbit_devices` intentionally has no direct client grants or RLS policies: only the narrowly scoped RPCs may access it. The security-definer functions are intentional, have an empty search path, validate the caller's live session, and check ownership before revoking access. The Supabase advisor reports these callable RPCs; they must stay reviewed. Leaked-password protection remains an existing backend setting, outside this change.

Run `supabase/tests/device_access.sql` to verify account isolation, revoked reads/writes, and revoked session listing. The test rolls back synthetic fixtures.

## Next priorities

1. Reliability and forgiveness: a brief Undo after deletes and conversions, offline indicators only when action is needed, and tested restore/export.
2. Clear daily capture and grouping: explicit dates and lists, compact rows, and readable layouts at larger text sizes.
3. Calendar planning: conflict warnings and optional duration-based suggestions before considering more automation. Current calendar access uses iOS calendars, including configured Google accounts; it is not a Windows Google OAuth integration or two-way task sync.

Keep generated AI out of the critical path. Useful next local signals would be completion-time patterns and opt-in reminders that suppress themselves after the day's commitments are done. Establish enough real usage before adding more dashboards, social features, or customization controls.


## iOS daily flow polish

- Task and habit titles open their editors. A separate check control with at least
  a 44-point touch target completes a task or logs/undoes a habit; habit counts and
  colours remain visible. Both Today and Habits use these rules.
- Long presses show explicit action menus, including Make It a Habit / Make It a
  Task. Dragging between sections no longer converts records. Edit Today still
  arranges and hides sections and pins lists using the existing device preferences.
- Capture stays directly below Today's header regardless of section arrangement.
  Progress is a small count and bar. Today's scheduled tasks precede overdue tasks,
  whose Today / Later / Someday actions remain available. Completed tasks and habits
  live in one initially collapsed section; expand it to edit or undo completion.
- Today has no staggered entrance, sideways transitions, or spring-driven row
  rearrangement. Check feedback and horizontal swipe feedback remain local to the
  action, and respect Reduce Motion.

## Iteration target and acceptance checks

Working interpretation of the owner's feedback: Orbit should be quick to capture
into, calm to open, predictable to touch, and forgiving of mistakes. The current
implementation is a candidate, not evidence that the feel has been resolved.
Visual references and feedback from actual phone use should refine this direction.

Use small passes around one everyday flow at a time:

1. Capture: open from Today, add three items with Return, correct a mistake, and
   close. Check keyboard continuity, contextual dates/lists, clear save feedback,
   and what happens to an unfinished draft when dismissed.
2. Plan: open a realistic busy day with timed tasks, overdue items, habits, and
   long titles. The next task and Add control should be easy to find. Check a
   quiet day and an all-done day too.
3. Act: tap titles to edit, use checks to complete/log, reopen via Completed, and
   undo a delete or conversion. The same controls must behave the same across tabs.
4. Glance: inspect each widget style and size on the phone; verify legibility,
   freshness, empty states, and completion behavior while locked.

For each candidate, record the friction being addressed, the concrete change,
validation performed, and remaining device checks. Use screenshots to compare
hierarchy and a short recording to judge keyboard, gesture, and motion behavior.
Run source checks and Xcode build/tests; syntax validation alone is insufficient.
Compare the result on the same scenarios before expanding scope. Use the app in
ordinary life between candidates and bring back specific moments of hesitation.

Next candidates to evaluate, not yet implemented: preserving an unfinished capture
draft or confirming its discard; multiline paste with a preview before creating
separate tasks; responsive layout repairs identified at accessibility text sizes.
Avoid expanding customization until the daily capture/plan/complete loop feels
comfortable in repeated real use.


## Owner's homepage direction

The owner's reference apps are Apple's Notes and Weather. The homepage should
support checking habits, following through on them, capturing incidental daily
tasks, recording activity, and seeing progress over time. Interpret the references
as clear content, familiar controls and glanceable information; the visual match
still needs feedback from use on the phone.

The default Today order now puts habits before daily tasks. The summary separates
habit and task completion so adding tasks does not obscure habit progress. Recent
habit history is available through Edit Today and the Habits history screen. Empty Habits has a
direct Add a habit action. Only the previous default layout profile is upgraded;
custom orders, pinned lists and visibility choices are preserved.

Evaluate future changes against whether they make starting a habit, adding a daily
task, recording progress or understanding recent activity easier. Keep encouragement
specific to recorded activity. Deeper progress views should distinguish habit
check-ins from task completion and partial habit progress from meeting a target.

## Clearer daily planning and accessibility

The iOS default Today now shows Habits and Your day with completion counts in their
section headings. The separate progress card and history strip are optional in
Edit Today. Existing custom arrangements are preserved. The evening review entry
point and general daily check-in notifications have been removed; individual task
and habit reminders remain. Previously scheduled general check-ins are removed
when Orbit refreshes its pending notifications.

Quick capture has explicit day and list controls, with no unexplained hashtag
examples. Lists has a New list plus button, a separate Add a task action, and
collapsible Today, Overdue, Upcoming, No date, Someday and Completed groups. Edit
Lists supports creation, renaming and deletion; deleting a list keeps its tasks.
The Windows quick-add help hint also no longer advertises the hashtag example.

Compact habits and tasks is a local Appearance preference. It reduces normal row
height and spacing while keeping check controls at least 44 points. Accessibility
text sizes use full wrapping titles, stacked details, and the regular minimum row
height regardless of the compact preference. Page tools move below long headers;
Calendar uses a native date picker in place of the seven-column day grid at those
sizes. Subtle row tint adds colour while text and completion controls communicate
state without relying on colour alone.

Plan this day in Calendar and Plan habits in Calendar in Habits open the optional
scheduler. Choose a day, available hours, writable calendar, selected items and
durations. Suggest times fills gaps around busy events and timed Orbit tasks,
leaving items that do not fit explicitly unscheduled. Busy all-day events block
the window; free events and non-busy all-day entries do not. Saving rechecks
conflicts and existing event links, then commits the reviewed calendar blocks.

This first scheduler creates one one-off block per selected habit/task, rather
than expanding multi-count habits or creating recurring events. It does not
complete items. Task start times and durations are saved in Orbit; habit durations
and calendar event links stay on this iPhone. Calendar events remain after item
completion, and external calendar edits do not update Orbit records. Real-device
permissions, provider behavior, event edits and repeat-save behavior still need
acceptance checks.

### Capture, icons and navigation pass (October 2026)

- Today accepts typed tasks inline. Return adds one and keeps entry ready for the next; options still open date/list capture. Timed drafts keep overlap review.
- A shared catalog provides 35 friendly icon names and whole-word English suggestions for common activities. New habits use Automatic; a manual choice stays selected. Existing chosen icons are preserved. Task icons follow their titles. Every catalog icon is available in the habit picker; decorative row icons do not repeat the title to screen readers.
- Edit Lists supports drag reordering and accessible Move up/down actions on iOS. The Windows list editor has Move list up/down controls. Ordering syncs through the existing sortOrder field; built-in Someday remains pinned.
- All five primary iOS tabs use PageHeader; Windows uses consistent page headings, spacing and wrapped titles. Lists now groups tasks by Today, Overdue, Upcoming, No date, Someday and Completed on both platforms. Windows also has compact rows and a scrollable sidebar for zoomed layouts.
- Windows catches up with the retired evening review, current habit wording, separate check/edit controls and optional progress/history on Today.
- Dictation is an editable draft, never an automatic save. iOS uses Speech/AVAudioSession after permission; leaving capture, backgrounding, stopping, or submitting ends its session. Windows opens OS voice typing (Win+H) in the focused field. Windows speech setup/language support is managed by Windows.

Remaining product gaps from this review: Windows has no equivalent to the iPhone's EventKit calendar connection and reviewed habit time-block planner; task icons are inferred rather than individually chosen; English keyword suggestions do not cover other languages; voice currently captures one item at a time rather than interpreting multi-step commands. These are separate follow-up features, not capabilities claimed by this pass.

### Optional task progress

Laundry, dishwasher cycles, baking, meal prep and similar tasks offer “Track start & finish” or “No thanks.” Suggestions use whole phrases and skip shopping, folding, unloading and other quick follow-ups. They never enable tracking automatically. Task options can enable or disable tracking for any task.

Tracked tasks use the existing row circle to Start, then show In progress with a partial ring, accent tint and an action to Finish in the same space. Starting gives a haptic response on iPhone. Suggestions, Reset progress and turning tracking off live in the row’s compact progress menu. Starting does not affect completed-task totals. Reopening a completed task resets its start state. The choice and start timestamp are saved in task records and included in sync, backup and undo snapshots. Older records default to the existing checkbox behavior with an optional suggestion where relevant. No automatic completion or new notifications are introduced.


### Bottom capture on iPhone

Today keeps task entry docked above the tab bar and above the keyboard during typing. The scroll view reserves space for it so the last item remains reachable. Return saves and keeps entry ready for another task. A down-chevron in the existing add-button position dismisses the keyboard and stops dictation without clearing the draft; scrolling can also dismiss the keyboard interactively. Switching tabs closes the keyboard and preserves the current draft. Save receipts appear briefly above the input, so the input stays in place. Date/list options and voice remain available in the bar.
