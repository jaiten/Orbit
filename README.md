# Orbit

**A little space for what matters.** A local-first planner for iPhone and Windows:
capture tasks, choose a manageable day, and keep small daily habits.

## Try it

- Windows: run `windows/dist/Orbit-0.2.0.exe`, or download the `Orbit-Windows`
  artifact from the GitHub Windows workflow. See [Windows setup](windows/README.md).
- iOS: on a Mac, install XcodeGen, run `cd ios && xcodegen generate`, then open
  `Orbit.xcodeproj`. Choose the Orbit scheme and your simulator or signing team.
  The visible app name is Orbit. Existing Orbit bundle/storage identifiers remain
  stable so the update does not rename your local data store.
- Sync: create/confirm an account in Windows **Settings & sync**, then sign in
  on iPhone in **Settings → Across your devices**. Use the same account on both.
  Local items are imported into that account; offline storage remains available.

For a physical iPhone, configure your Apple team, unique bundle IDs and matching
App Group on both targets. Update `ORBIT_APP_GROUP` in `ios/project.yml`. The full
SwiftData app currently requires Xcode; WSL/xtool is not yet supported.

## Implemented

| Area | Current behavior |
| --- | --- |
| iOS | Habit-first Today, week/month calendar, task/list/habit CRUD, notes, tags, subtasks, reminders, recurrence, heatmaps |
| Windows | Today, inbox, next seven days, task/habit editors, priority, time blocks, recurrence, completion, habit history |
| Sync | Separate Supabase backend, email/password accounts, durable outbox, tombstones, revision checks, conflict review, reconnect catch-up |
| Widgets | Home Screen and Lock Screen widgets, shared local store, interactive completion |
| Brand | Vector mark/wordmark, Windows/iOS icons, [brand guide](shared/brand/README.md) |

Desktop preserves iOS-only task fields when editing but does not yet expose all
their editors. Windows reminders, automatic updates, custom recurrence rules,
background sync services, and account recovery UI remain follow-up work. iOS
reminders schedule the nearest 60 requests and refill on app interaction; OS
delivery and widget refresh policies apply. Task/habit counts have no product caps.

## Data

SQLite on Windows and SwiftData on iOS save edits before network activity. When
two devices edit one record concurrently, Settings lets you compare and choose a
version. Sign-out preserves local data and the original account binding.
[Sync details](docs/sync-plan.md). Windows sessions use OS encryption; iOS uses
Keychain. Public client config includes only a publishable key. The database denies
anonymous access and enforces owner-scoped reads and revision-checked writes.

## Validation

GitHub builds the iOS app/widget and runs simulator XCTest. Windows unit tests cover
offline persistence, tombstones, acknowledgment races, conflicts, account isolation,
and network failure. Electron smoke tests cover task create/edit/complete, habit
log/undo, settings, and offline restart. Hosted integration checks exercised two
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
