# Orbit

A local-first planner for iPhone and Windows:
capture tasks, choose a manageable day, and keep small daily habits.

## Try it

- Windows: install the latest `Orbit-Setup-<version>.exe` from
  [GitHub Releases](https://github.com/jaiten/Orbit/releases/latest). Installed copies
  from 0.3.4 offer automatic updates. See [Windows setup](windows/README.md).
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
| Both apps | Today (today, plus anything still open from earlier days) with the writing bar docked at the bottom, Calendar with a Week / Month / All overview, Calendar, Notes in sections with a built-in Someday section, Habits, Settings and Account; one growing quick add field with an opaque preview chip, where long text becomes a note; first-launch onboarding with optional examples; JSON and CSV export, JSON import with a preview |
| iOS | Checklist tiles, swipe actions, week/month calendar, notes, tags, subtasks, reminders, Shortcuts and Siri (Add to Orbit, Complete Item), share sheet extension |
| Windows | Notion-style Notes (notes sidebar beside a full-page editor), a month Calendar with the chosen day beside it, start typing anywhere to add a task (or a page on Notes), a fixed-size onboarding with × to skip, Today with optional progress/history, compact rows, list reordering, Windows voice typing, keyboard shortcuts (Ctrl+N, Ctrl+1–5, Ctrl+F, Ctrl+/), reminders as Windows notifications, tray icon and a global quick add shortcut |
| Sync | Separate Supabase backend, email/password accounts, durable outbox, tombstones, revision checks, conflict review, reconnect catch-up |
| Widgets | Today in Progress, Checklist and Grid styles on Home and Lock Screen; Habit consistency with week/month options on both; interactive completion, focus Live Activity |
| Brand | Vector mark/wordmark, Windows/iOS icons, [brand guide](shared/brand/README.md), colours and spacing from [design tokens](shared/design-tokens.json) |

**Day starts at** (Settings → Today & Progress, 11 PM the evening before through 4 AM in
half hours, 2 AM by default) decides when a new planner day begins. Until then, Today, check-ins,
finished tasks and new habits count for the day before; scheduled dates and times never move.
The choice syncs between devices as one `preferences` record ([cases](shared/test-cases/day-start.json)).

Only habits repeat. Older repeating tasks were converted to habits (daily, weekdays,
weekends or weekly) with their history kept; monthly and custom repeats became one-off
tasks. Habits reset at midnight and show “X of the last 7 days”. There is no streak counter,
but a check-in that lands a streak on 7, 14, 30, 50, 100, 200 or 365 days (4, 8, 12, 26 or 52
weeks for weekly habits) shows a short celebration ([cases](shared/test-cases/streaks.json)).
Windows does not yet edit tags, subtasks or reminder offsets, but keeps them when
saving. Windows keeps syncing while it runs in the tray; iPhone syncs while open and uses
Background App Refresh, which iOS runs a few times a day at times it chooses. iOS
reminders schedule the nearest 60 requests and refill on app interaction.

## Beta interface refinements

Windows Today has compact, colored habit rows and squared cards. The layout icon
opens direct drag-and-drop editing: every panel, including tasks, can move between
columns or above the task list. Today always shows the current day on both apps; Recent
progress shows the last seven days, and earlier days are reviewed in Calendar. Habits on
Today log with one click anywhere on the row. A menu hides or shows completed tasks.
Open tasks from earlier days simply stay on Today with the rest; there is no Overdue
section, label or move prompt, so you move them yourself when you like. Touch and hold (right-click on Windows) any
open task for **Do on…** (tomorrow or any of the next few days, by name) and a timer of a chosen length. On Windows, clicking an empty spot
in Calendar's Any time row starts typing a task for that day, and pages widen with the window. The calendar button beside the writing bar opens the full task editor. Tasks is
grouped the same on both apps: Someday first, then tasks without a category by Today
(including earlier days) / Upcoming, then each category. A new task with no category takes the category of
earlier tasks with similar titles, shown in the chip before saving
([cases](shared/test-cases/category-suggestions.json)). In-progress tasks show only the
ring, and their timer offers 15 minutes, 30 minutes, 1 hour, 2 hours or the task's own
length; touch and hold (right-click on Windows) for **Mark in progress**. Overall progress
is optional, reads left to right, and uses a week/month choice in Settings or Edit layout.

Calendar has quarter-hour slots, draggable tasks, a 12/24-hour preference and thin
anytime rows. Drag the anytime boundary to resize or fully collapse it; the toolbar
restores it. New calendar tasks open their date/time options. Notes supports styled
bullet levels, inline photos, and section menus with explicit keep/delete-content
choices. New note sections and task categories are independent. Legacy shared groups
remain readable so existing filing is preserved.

On iPhone, Notes has an opaque keyboard accessory with horizontally scrolling list,
indent and undo/redo controls and a pinned Done button. Category creation uses an
inline plus button; native drag handles reorder categories, including Someday.
Settings groups appearance, Today/progress, calendars, notifications and data.
Both apps keep saving during note editing while the displayed edited time stays
fixed until the note is reopened. Task inclusion in daily progress defaults on,
including iPhone widgets. The release pipeline verifies Apple processing after upload.

## Calendars and focus

On iPhone, **Settings → Calendars → Connect calendars** shows today's events from
accounts in Apple Calendar, including configured Google accounts. Touch and hold a
to-do and choose **More → Send to calendar**; the native editor lets you choose a writable calendar
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

**Today** shows tasks dated today, anything still open from earlier days (in with the
rest, with no Overdue section), and habits due today. Undated tasks
stay in their list until you add them to Today. Completed items move below the
open ones in a collapsed Completed section. Task and habit titles open their details;
use the separate check control to complete a task or log a habit. Arrange sections in
Edit Today.

**Counters.** A counter is a habit with no target, for things you want to tally ("washroom
without my phone"). Each tap or click adds one for the day; Take One Off (touch and hold, or
right-click on Windows) goes back. Make one from Habits (**Counter** on iPhone, **New counter** on
Windows) or switch a habit's Type in its editor. Counters sit under the habits on Today and Habits,
show today's count, and have their own history (today, the last 7 days, a daily average and 12
weeks). They never count as done, so they stay out of the plan, progress, streaks, reminders and
badges. A counter is stored as a habit whose `frequencyRule` is `COUNTER`
([case](shared/test-cases/habits.json)).

**Due dates.** Any task can have a due date as well as the day it is planned for: **Due date** in
the task editor (under Date & time on Windows, a small calendar with Today, Tomorrow, Next week and
In 2 weeks). Open tasks then show "Due Fri", "Due today" or, in red,
"Overdue · Nov 20" beside the title; the planned day doesn't move. Stored as the task's `deadline`
day ([cases](shared/test-cases/deadlines.json)).

Tasks due today or overdue appear on Today wherever they are planned (even undated or in Someday).
Type `due fri`, `due tomorrow`, `due in 3 days` or `due dec 4` in quick add to set it. **Remind me
the day before** (in the editor, once a due date is set) sends a reminder at 9 AM the day before. On
Windows, Calendar's month shows a red **Due** flag on the day a task is due.

**Recurring tasks.** Set **Repeat** in the task editor (every day, weekday, week, 2 weeks, month or
year). Ticking one off adds the next with its planned day, time, due date and reminders moved forward,
skipping dates already past, so missed ones don't pile up; unticking it by mistake takes back the
untouched copy. Both devices make the same copy, so finishing it on both while offline doesn't double
it ([cases](shared/test-cases/repeats.json)). Older repeating tasks stay habits, as before.

**Calendar on Windows.** Month, Week and Day fit the window without a scrollbar; drag a task from one
day to another in Month, and click "3 more" to open that day. Drag the main sidebar's edge in to leave
just its icons (further hides it). Every date field uses the same small calendar, with Today, Tomorrow,
Next week and In 2 weeks.

**Taking a check-in off.** A habit partway through its check-ins (1 of 3) has a minus just before its
count that takes one off (on Windows it slides in when you hover the row); Take One Off is also in its
touch-and-hold (right-click) menu. Habits to avoid have a × to mark a slip in one tap, the same way (an
arrow takes it back on iPhone; on Windows, click the slipped row). A weekly or monthly habit ticked
today shows its tick but is only struck through once the week's or month's goal is met. With habits
split on Windows Today, habits to avoid get their own Avoiding card.

**Checking off, swipes and the hold menu.** A tick shows the moment you tap or click it. The row
stays where it is for about a third of a second (longer while you keep ticking others), then folds
away and appears under Completed; tap it again inside that pause to take the tick back. On iPhone,
swipe a task, habit or note left a little for Delete, or all the way to delete in one motion (Undo
brings it back); swipe right to edit it (or open the note). Touch and hold lifts the row as a card
with a short menu: Edit, Do on… (tomorrow and the next few days), Start focus timer, **Move** (Add to Today, Move to Someday),
**More** (Mark in progress, Send to calendar, Make It a Habit, Make It a Note), Copy text and
Delete. On Windows, dragging a task in Calendar's week and day views outlines the time it will
land on, and it can be dropped on a time that already has something.

**Quick add rules** (Settings, synced) hold three things. *Someday visibility rules*: type an
@tag that has a rule (`water plants @home`) and the task stays in Someday, showing on Today, in
Calendar and in Coming up on the days a rule matches (a calendar event, no matching event, a date
range, or every few weeks or months). Saving a rule offers to hand over open tasks that already
carry its tag. *Abbreviations*: `gs = grocery shopping #errands` per line; in quick add the word
expands as soon as you type a space after it, and the text can use quick add words
([cases](shared/test-cases/shortcuts.json)). *Start & finish* is learned: after you track it on a
task, a similar new task suggests it, and from the second time on it starts tracked (turning it off
on one teaches it otherwise); words listed in the rules always turn it on.
On Windows, Ctrl+Shift+Enter adds a task even when long text would otherwise make a note. It stays
on the day you are viewing unless date words close the text ("… tomorrow"), and the bar says where
a capture went when it lands somewhere the page doesn't show (iPhone does the same).

**Selecting and undo on Windows.** Ctrl-click selects rows (tasks, notes and habits), Shift-click
selects a run of them, and Ctrl+C copies the selection as a list; the pencil and bin still edit
and delete while selecting. Undo and Redo sit at the top of the window and walk back and forward
through every change made on the PC (Ctrl+Z, Ctrl+Y); deletes and moves also show the Undo toast.

**Calendar events on Today** open on tap or click; touch and hold (right-click on Windows) for
Edit, Copy text, Add as a task and Delete event (and Show in Calendar on iPhone). An event's address
shows under its title; tap it (or Open address in maps on Windows) to open it in Maps, or to join
when the location is a meeting link.

**Accents and milestones.** Nine accent colours: Coral, Sage and Blue to start with, and six
(Lavender, Teal, Honey, Rose, Plum, Midnight) unlocked by badges, out of 17 milestones in all
([shared/rewards.json](shared/rewards.json)).

**Notes** replaces Lists. Notes are titled pages grouped into sections (Personal,
Work, Someday…); open one to edit it as a page with a large title, a Section property and
the text below. Type more than 8 words (date and time words such as "friday at 6pm" don't
count), about 120 characters, or a line break into the bar on Today, Tasks or Habits and it
unfolds into a note card in place — a title above, your text as the body — without the
keyboard or caret moving. Return is then a new line; Save (Ctrl+Enter on Windows) adds it to
Notes instead of Today.

**Locked notes and sections.** Touch and hold (right-click on Windows) a note to lock it, or a
note section to lock all of its pages. iPhone unlocks with Face ID, Touch ID or the passcode;
Windows uses one notes password (set it the first time you lock something, or in Settings →
Notes & Writing; only a salted hash is kept on that PC). Locked pages show their title with a
lock and no text; a locked section's pages are listed only once unlocked. Everything locks again
when the app is minimised or leaves the screen, or with **Lock Now**. **Hide titles** on a
section shows its pages as "Hidden note", with no title or text in lists and search. Locks keep
notes out of view on the device; note text is not encrypted separately in sync.

**Adding tasks to your calendar.** Touch and hold a dated task on iPhone and choose
**More → Send to calendar** (or open the task): the system event editor opens with it filled in, for any calendar on the phone,
including Google or Outlook accounts added in iOS Settings. On Windows, right-click a dated task
(or use **Add to calendar…** in its editor) for Google Calendar or Outlook in the browser, or an
.ics file for the default calendar app (Windows Calendar, Outlook, Apple Calendar). It is a one-time
copy: later changes in Orbit don't update the event.

**Sections.** New note sections can be locked as they are made. On iPhone, Manage sections is the
folder icon at the top right of Notes; touch and hold a section for Lock, Hide titles and Delete
Section (keeping its notes in All notes, or deleting them too). Notes are grouped by when they were
last edited (Today, Yesterday, Previous 7 Days, Previous 30 Days, then by month and year), and a
page with only a title shows "No additional text".

**Writing on Windows.** Notes autocorrect as you type: missing apostrophes (dont → don't,
im → I'm), common typos (teh → the), your own rules (Settings → Notes & Writing, one
`btw = by the way` per line), and one-letter slips Windows' spell checker is sure about.
Ctrl+Z straight after takes a correction back. A long note keeps a chin of space below the
line you are typing. Add photo, Copy text and Make it a Task sit behind the note's ⋯ button;
right-click a note in the list for Make it a Task too. Notes are task
records marked `isNote`, so they sync, back up and undo with everything else, and never
appear as to-dos. New note sections and task categories are scoped independently; older shared groups stay readable. Calendar's **Overview** (iPhone) and **Month / Week / All** views (Windows) show
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
