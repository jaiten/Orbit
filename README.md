# Orbit

A local-first planner for iPhone and Windows:
capture tasks, choose a manageable day, and keep small daily habits.

## Try it

- Windows: run `windows/dist/Orbit-0.3.0.exe`, or download the `Orbit-Windows`
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
| Both apps | Today (today plus overdue) with the writing bar docked at the bottom, Calendar with a Week / Month / All overview, Calendar, Notes in sections with a built-in Someday section, Habits, Settings and Account; one growing quick add field with an opaque preview chip, where long text becomes a note; first-launch onboarding with optional examples; JSON and CSV export, JSON import with a preview |
| iOS | Checklist tiles, swipe actions, week/month calendar, notes, tags, subtasks, reminders, Shortcuts and Siri (Add to Orbit, Complete Item), share sheet extension |
| Windows | Notion-style Notes (notes sidebar beside a full-page editor), a month Calendar with the chosen day beside it, start typing anywhere to add a task (or a page on Notes), a fixed-size onboarding with × to skip, Today with optional progress/history, compact rows, list reordering, Windows voice typing, keyboard shortcuts (Ctrl+N, Ctrl+1–5, Ctrl+F, Ctrl+/), reminders as Windows notifications, tray icon and a global quick add shortcut |
| Sync | Separate Supabase backend, email/password accounts, durable outbox, tombstones, revision checks, conflict review, reconnect catch-up |
| Widgets | Today in Progress, Checklist and Grid styles on Home and Lock Screen; Habit consistency with week/month options on both; interactive completion, focus Live Activity |
| Brand | Vector mark/wordmark, Windows/iOS icons, [brand guide](shared/brand/README.md), colours and spacing from [design tokens](shared/design-tokens.json) |

Only habits repeat. Older repeating tasks were converted to habits (daily, weekdays,
weekends or weekly) with their history kept; monthly and custom repeats became one-off
tasks. Habits reset at midnight and show “X of the last 7 days”, not streaks.
Windows does not yet edit tags, subtasks or reminder offsets, but keeps them when
saving. Automatic updates and background sync services are follow-up work. iOS
reminders schedule the nearest 60 requests and refill on app interaction.

## Calendars and focus

On iPhone, **Settings → Calendars → Connect calendars** shows today's events from
accounts in Apple Calendar, including configured Google accounts. Touch and hold a
to-do for **Send to calendar**; the native editor lets you choose a writable calendar
and confirm saving. Repeat sends reopen the same event where its identifier is still
valid. Edits to calendar events do not update the original task. Calendar event
access currently runs on iPhone; Windows does not connect directly to calendar providers.

**Plan this day** has been removed while it is redesigned; see the
[design prompt](docs/prompts/plan-your-day.md). **Settings → Appearance → Compact habits
and tasks** reduces spacing while accessibility text keeps full-size controls.

Touch and hold a to-do for **Start focus timer**; starting a tracked task also suggests
one, and its progress menu offers Start timer. The timer uses the task duration
(5–240 minutes) and appears in Today, and as a Lock Screen Live Activity (and Dynamic
Island) when Live Activities are enabled; otherwise it runs in the app. On Windows, an
in-progress row shows a timer button on hover, and a notification appears when it ends.
Touch and hold (or right-click on Windows) any item for **Copy text**.

Email setup and recovery: [confirmation guide](docs/email-confirmation.md).
TestFlight uploads follow successful iOS checks on main: [release guide](docs/testflight.md).

## Planning a day

**Today** shows tasks dated today, anything overdue, and habits due today. Overdue
tasks offer **Today**, **Later** (removes the date) and **Someday**. Undated tasks
stay in their list until you add them to Today. Completed items move below the
open ones in a collapsed Completed section. Task and habit titles open their details;
use the separate check control to complete a task or log a habit. Touch and hold a
row for actions, including Make It a Habit / Make It a Task. Arrange sections in
Edit Today.

**Notes** replaces Lists. Notes are titled pages grouped into sections (Personal,
Work, Someday…); open one to edit it as a page with a large title, a Section property and
the text below. Type more than about 120 characters (or a line break) into Add a task and
the chip changes to *Note*; Return saves it to Notes instead of Today. Notes are task
records marked `isNote`, so they sync, back up and undo with everything else, and never
appear as to-dos. Sections are the former lists; tasks filed in one still show on its
Notes page (Windows) and in Today → All. Calendar's **Overview** (iPhone) and **Month / Week / All** views (Windows) show
every task in that period by day, and how each habit is going. Notes has the same bottom
bar as Today; whatever you type there becomes a note.

Today accepts tasks directly in its text field: Return adds one and keeps entry ready for another; Return on an empty field closes the keyboard. No success message appears; the cleared field is the confirmation. The field uses the system autocorrect and capitalisation. The options button opens date/list capture. Microphone controls dictate into an editable draft (iOS Speech and Windows voice typing); saving stays explicit. Habits offer 35 named icons or Automatic; on iPhone, task icons follow title keywords. Windows shows only icons you choose: automatic (title-guessed) emoji are hidden. Edit Lists lets you reorder lists.

Quick add reads plain phrases such as `gym tomorrow 6pm`, `read every day`,
`someday`; the chip shows what will be created before you save. On iPhone, Return saves the item and clears the field for another; Save saves and
closes. Items already added stay saved when you tap Done.

The phrase table is shared by both apps ([test cases](shared/test-cases)).

All-day tasks keep their calendar day when you travel; timed tasks keep their
moment. Habit reminders follow local time.

## Data

SQLite on Windows and SwiftData on iOS save edits before network activity. When
two devices edit one record concurrently, Settings lets you compare and choose a
version. Metadata-only differences resolve without prompting, and independent
field changes merge using the last synced baseline. A real conflicting edit shows
both readable versions before either is discarded. Sign-out preserves local data and the original account binding.
[Sync details](docs/sync-plan.md). Windows sessions use OS encryption; iOS uses
Keychain. Public client config includes only a publishable key. The database denies
anonymous access and enforces owner-scoped reads and revision-checked writes.
Signed-in users can permanently delete their account and synchronized data from
**Settings → Account**; the deleting device's local planner is cleared as part of
the same user flow. See the [privacy notice](docs/privacy.md) and
[small-beta launch checklist](docs/beta-launch-checklist.md).

## Validation

GitHub builds the iOS app, widget and share extension and runs simulator XCTest,
including the shared rule tables in `shared/test-cases`. Windows unit tests cover
the same tables plus offline persistence, tombstones, conflicts, reminders, import
and export. The Electron smoke test covers onboarding, quick add, overdue and
Someday moves, keyboard shortcuts, the conflict banner, import preview, CSV export,
restart and midnight rollover. iOS UI tests cover onboarding, quick add and Account. Hosted integration checks exercised two
clients and a second isolated account.

```powershell
cd windows
npm ci
npm run lint
npm test
npm run test:desktop
npm run pack
```

Physical-device UI, signing, real email confirmation, migration from an older iOS
installation, widget concurrency and iPhone-to-PC acceptance still need checking.
See [device checklist](docs/validation.md). Simulator success does not establish
those device-specific results.
