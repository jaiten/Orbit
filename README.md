# Orbit

A calm, local-first daily planner for iPhone and iPad. This repository starts with
the native **iOS 17+ prototype**, as requested. It uses SwiftUI, SwiftData and
WidgetKit, with no account or network dependency. The app display name is Orbit;
existing target names, bundle IDs and storage identifiers remain DayOS to preserve
the original project and data identity.

## Current interface

Orbit uses a compact calendar structure with daily habits first, a soft coral
accent, grouped system surfaces and native navigation. Today includes a selectable
week strip, partial-target progress ring, a separate weekly-habit section, scheduled
tasks, and a keyboard-aware quick-add field with parsed date feedback. Completed
tasks are available in a disclosure section. Habit check-ins can be corrected on
past days; future check-ins are disabled. Daily progress averages each daily habit's
fraction of its target, so a six-glass water target has the same weight as reading.

The calendar supports week/month browsing, all-day tasks, and timed agenda rows.
Native navigation/tab bars retain the real system status bar and safe-area handling.
Date selection, completion and rings use SwiftUI transitions with Reduce Motion
support. Physical-device checks for keyboard, status bar and large text remain in
`docs/validation.md`.

## Run on a Mac

Requirements: Xcode 16 or newer, an iOS simulator, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
cd ios
xcodegen generate
open DayOS.xcodeproj
```

Select the **DayOS** scheme and an iPhone simulator, then Run. For a physical
device, choose your Apple signing team on both targets, change the bundle IDs to
your own, and register the same App Group for the app and widget extension.
Update `DAYOS_APP_GROUP` in `ios/project.yml` before regenerating. The default is
`group.com.dayos.shared`. Both targets must resolve the same group identifier.

The app intentionally shows a recovery message if its shared persistent store
cannot open. It never silently replaces an unreadable database with an empty one.

Start in **You → Explore with sample data** to populate a few tasks and habits,
or use **+** to begin with your own. Sample data is opt-in and only offered when
there are no tasks or habits. Add your own suggestions under **Try something new**.

## Implemented in the iOS source

- Today: scheduled tasks, unscheduled to-dos, overdue work, habit check-in, progress,
  and a daily rotation from your own idea list.
- Task CRUD: lists, notes, priority, tags, editable subtasks, arbitrary reminder
  arrays, time blocks, daily/weekly/monthly recurrence, and completion.
- Quick-add grammar: `gym tomorrow 6am`, `read today 8:30pm`, or plain task text.
  A bare time that has passed schedules tomorrow. Other natural-language date
  expressions are not interpreted.
- Week and month planning. Drag tasks onto date cells to move them while preserving
  reminder offsets. Drag to-dos onto one another in Today to reorder them; scheduled
  tasks stay in chronological order.
- Habit CRUD: daily/weekly count targets, period streaks, 84-day heatmaps, reminders
  and unfinished-habit nudges. Long-press a habit to undo one log on today's date.
- System/light/dark themes, Dynamic Type styles, labeled controls, native haptics,
  warm sage/clay/lavender/honey tokens and reusable SwiftUI cards/rows.
- Shared on-disk SwiftData store and explicit save/rollback error handling.
- Small, medium, large, circular and rectangular widgets. Medium/large widgets
  support task completion and habit logging through App Intents.

## Widget setup

Run the app once, then add **DayOS → Your daily rhythm** from the Home Screen
widget gallery. Lock Screen widgets are available in the Lock Screen editor.
The large widget shows up to seven items, followed by a remaining-item count;
widgets cannot display an unbounded scrollable checklist. Tap the surrounding
widget to open Today. Interactive controls require iOS 17+.

Widgets use the same schema and App Group store, then request timeline refreshes.
Apple controls when timelines refresh; updates are not guaranteed to be immediate.
Validate app/extension concurrent changes and foreground refresh on a real device
before shipping. See [Apple's interactive widget guidance](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities).

## Validation

The development host is Windows with Swift and xtool in WSL. The full app still uses SwiftData, which requires the Xcode build path until the persistence layer is adapted. **An iOS build,
XCTest execution, and simulator/device UI review have not been performed here.**
Source parsing and project structure checks pass; they cannot check SDK types or
SwiftData macro expansion.

On a Mac, use Product → Test or:

```sh
cd ios
xcodebuild test -project DayOS.xcodeproj -scheme DayOS \
  -destination 'platform=iOS Simulator,name=YOUR_INSTALLED_IPHONE_SIMULATOR' \
  CODE_SIGNING_ALLOWED=NO
```

The included GitHub Actions workflow generates the Xcode project, chooses an
available iPhone simulator, builds the app/widget and runs the tests. It will run
when this repository is pushed to GitHub; it has not been run remotely here.
XCTest cases cover parsing, DST, streaks, weekly boundaries, idempotent
recurring generation, habit undo/targets and disk persistence.

For portable syntax checks:

```sh
python -m pip install tree-sitter tree-sitter-swift pyyaml
python scripts/validate_sources.py
```

Use [the device checklist](docs/validation.md) for behavior and visual review.

## Staged work

| Deliverable | Status |
| --- | --- |
| iOS local models, UI, persistence, reminders | Implemented source; awaiting Xcode verification |
| WidgetKit extension | Implemented source; awaiting device verification |
| Shared design tokens | Included; native typography maps per platform |
| Supabase schema and RLS | SQL scaffold; not deployed or database-tested |
| Realtime/offline reconciliation | Contract and implementation plan only; disconnected |
| Windows app | Architecture boundary only; no executable yet |

The schema is in `supabase/migrations/0001_dayos.sql`. The sync contract and
[implementation plan](docs/sync-plan.md) reserve the next phase. The
[Windows plan](windows/README.md) follows UX validation and shared sync work.

Prototype limitations: no custom RRULE expansion, custom weekday habit schedules,
background sync, notification actions, automated background notification refill,
or Windows client yet. Recurrence creates the next occurrence when one is completed;
it does not pre-expand all future dates. Reopening a completed recurring task keeps
its already-created successor and will not create a duplicate on recompletion.
Changing a habit's target/frequency applies to its existing history.

Reminder records are unlimited; the prototype schedules the nearest 60 pending
notifications and refreshes on foreground, edits, and widget actions. Habit requests
cover the next seven days. Without reopening/interacting, this queue eventually
expires. OS permission, delivery policy and background restrictions still apply.
