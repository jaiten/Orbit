# Orbit

A local-first planner for iPhone and Windows:
capture tasks, choose a manageable day, and keep small daily habits.

## Try it

- Windows: run `windows/dist/Orbit-0.2.0.exe`, or download the `Orbit-Windows`
  artifact from the GitHub Windows workflow. See [Windows setup](windows/README.md).
- iOS: on a Mac, install XcodeGen, run `cd ios && xcodegen generate`, then open
  `Orbit.xcodeproj`. Choose the Orbit scheme and your simulator or signing team.
  The targets, bundle identifiers and shared store now use Orbit. Importing data
  from an older DayOS installation is not implemented; preserve that installation
  if it contains records you need.
- Sync: create/confirm an account in Windows **Settings → Account**, then sign in
  on iPhone in **Settings → Account**. Use the same account on both.
  Local items are imported into that account; offline storage remains available. Realtime changes are received while both apps are open, with periodic catch-up after reconnect.

For a physical iPhone, configure your Apple team, unique bundle IDs and matching
App Group on both targets. Update `ORBIT_APP_GROUP` in `ios/project.yml`. The full
SwiftData app currently requires Xcode; WSL/xtool is not yet supported.

## Implemented

| Area | Current behavior |
| --- | --- |
| iOS | Adaptive checklist tiles, large completion targets, separate edit controls, swipe delete/move, week/month calendar, task/list/habit CRUD, notes, tags, subtasks, reminders, recurrence, heatmaps |
| Windows | Adaptive checklist tiles, one-off/routine sections, quiet sync status, to-do/habit conversion, lists, next seven days, task/habit editors, natural-language quick-add, priority, time blocks, recurrence, completion, habit history |
| Sync | Separate Supabase backend, email/password accounts, durable outbox, tombstones, revision checks, conflict review, reconnect catch-up |
| Widgets | Home Screen and Lock Screen widgets, interactive completion, focus Live Activity for Lock Screen and Dynamic Island |
| Brand | Vector mark/wordmark, Windows/iOS icons, [brand guide](shared/brand/README.md) |

Desktop preserves iOS-only task fields when editing but does not yet expose all
their editors. Windows reminders, automatic updates, custom recurrence rules,
background sync services, and account recovery UI remain follow-up work. iOS
reminders schedule the nearest 60 requests and refill on app interaction; OS
delivery and widget refresh policies apply. Task/habit counts have no product caps.

## Calendars and focus

On iPhone, **Settings → Calendars → Connect calendars** shows today's events from
accounts in Apple Calendar, including configured Google accounts. Touch and hold a
to-do for **Send to calendar**; the native editor lets you choose a writable calendar
and confirm saving. Repeat sends reopen the same event where its identifier is still
valid. Edits to calendar events do not update the original task. Calendar event
access currently runs on iPhone; Windows does not connect directly to calendar providers.

Touch and hold a to-do for **Start focus timer**. The timer uses the task duration
(5–240 minutes) and appears in Today and as a Lock Screen Live Activity; compatible
phones also show Dynamic Island. Stop it from Today. Live Activities must be enabled
in iPhone Settings. A completed timer becomes stale; reopening Orbit clears it.

Email setup and recovery: [confirmation guide](docs/email-confirmation.md).
TestFlight uploads follow successful iOS checks on main: [release guide](docs/testflight.md).

## Planning a day

**For today** holds one-off tasks, such as cleaning the car on a chosen date.
**Your routine** holds daily/weekly habits and recurring tasks. Completed items move
below the active sections. The tile's main area completes it; the pencil edits it.
Short titles share a row where there is room. Larger text uses the available width.

Lists are optional folders such as Personal or Work. Tasks can stay in Inbox.

## Data

SQLite on Windows and SwiftData on iOS save edits before network activity. When
two devices edit one record concurrently, Settings lets you compare and choose a
version. Metadata-only differences resolve without prompting, and independent
field changes merge using the last synced baseline. A real conflicting edit shows
both readable versions before either is discarded. Sign-out preserves local data and the original account binding.
[Sync details](docs/sync-plan.md). Windows sessions use OS encryption; iOS uses
Keychain. Public client config includes only a publishable key. The database denies
anonymous access and enforces owner-scoped reads and revision-checked writes.

## Validation

GitHub builds the iOS app/widget and runs simulator XCTest. Windows unit tests cover
offline persistence, tombstones, acknowledgment races, conflicts, account isolation,
and network failure. Electron smoke tests cover list assignment, task create/edit/complete,
habit log/undo, conversion round trips, compact dark layout, settings, and offline restart. iOS UI tests exercise swipe conversion and deletion. Hosted integration checks exercised two
clients and a second isolated account.

```powershell
cd windows
npm ci
npm test
npm run test:desktop
npm run pack
```

Physical-device UI, signing, real email confirmation, migration from an older iOS
installation, widget concurrency and iPhone-to-PC acceptance still need checking.
See [device checklist](docs/validation.md). Simulator success does not establish
those device-specific results.
