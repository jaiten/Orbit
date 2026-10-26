# Orbit sync

The active transport is public.orbit_records and orbit_put in
`supabase/migrations/20261019065613_orbit_records.sql`. The older five-table schema
and shared/SyncContract.swift are historical scaffolding, not the active API.
The separate Orbit project is uwcwnjwijvawvvffaxdr in Canada Central.

Each document has an owner, entity/key, JSON payload, tombstone, revision and
mutation UUID. IDs are lowercase UUIDs. Habit-log keys combine habit ID and local
date. Calendar dates are YYYY-MM-DD; timed events/timestamps are Unix milliseconds.

SwiftData saves its outbox with the domain mutation. SQLite batches recurrence
mutations transactionally. Upload uses compare-and-swap revisions and the same
mutation ID on retry. Late acknowledgments never clear newer edits. Conflicting
versions are preserved for explicit review; same-day habit counts are not silently
added together because two devices may represent the same real-world check-in.

Pull pages the full owner collection ordered by stable key. Repeated catch-up
avoids lost events and timestamp-cursor gaps. This is intended for personal planners,
not massive collaborative workspaces. Desktop Realtime invalidates state; both
apps poll every eight seconds while active. iOS background execution is not
guaranteed. Widget edits queue locally and upload when the app is opened.

Auth uses email/password, Keychain on iOS and OS encryption on Windows. A local
owner binding prevents account mixing. Sign-out never silently deletes your data.
Real email confirmation needs an acceptance check; production SMTP and Auth abuse
controls are deployment settings tracked in `docs/beta-launch-checklist.md`.

## Database protections

RLS allows only owner SELECT. Direct authenticated writes and all anonymous table
access are revoked. The RPC deliberately uses SECURITY DEFINER to prevent clients
bypassing revision checks with direct writes. It takes no owner parameter, requires
auth.uid(), uses an empty search path, and serializes owner/key changes with an
advisory transaction lock. PUBLIC and anon cannot execute it.

The advisor flags authenticated execution of the definer function. This is an
intentional, reviewed API boundary:
[Supabase guidance](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

Verified on the hosted database: first write, duplicate retry, stale rejection,
cross-user isolation. Two authenticated clients also tested bidirectional sync,
conflicting offline edits, conflict resolution and remote deletion. Temporary test
users and their records were removed. Physical iPhone-to-PC testing is outstanding.

## Realtime and review

Both foreground clients subscribe to owner-filtered Postgres change notifications;
the authenticated REST catch-up remains the source of records and revisions.
The iPhone socket stops in the background and reconnects on foreground. Both clients
catch up after joining/rejoining and use a twenty-second fallback while open.
Local edits made during an in-flight sync queue another pass instead of being dropped.

A local baseline makes independent field changes mergeable. Metadata-only differences
and submillisecond date round-trip noise do not require a choice. Competing edits to
the same field, or removal versus editing, still retain both versions for explicit
review. Review shows readable content instead of raw JSON or unexplained device labels.
Existing conflicts without a baseline are only resolved automatically when their
meaningful content agrees; previous edits are never guessed away.

Desktop sync-status notifications update only the icon. Planner content renders only
when record content changes; open add menus and editors defer that render. Completion
uses the large tile area, and the pencil is reserved for editing.

## Time zones

There are no time-zone settings. Each kind of date follows one rule on both apps
(tests: `ios/Tests/TimeZoneTests.swift`, `windows/tests/time-zones.test.cjs`):

| Kind | Stored as | Behaviour after travel |
| --- | --- | --- |
| All-day task | `localDate` "YYYY-MM-DD", `dueDate` null | Stays on the same calendar day everywhere. iOS keeps a cached local midnight and re-anchors it on launch and on time-zone change; the payload does not change, so nothing re-uploads. |
| Habit check-in | key `habit_logs/<habit>-<YYYY-MM-DD>` | The local day of the device that recorded it. A check-in at 23:30 in Vancouver is the 20th on every device, even where it is already the 21st. |
| Habit reminder | `reminderMinutes` after midnight | Follows the device's current zone: 7:00 means 7:00 local wherever you are. |
| Timed task | `dueDate` Unix ms (plus `localDate` of that instant for older clients) | An instant, shown in each device's local time: a 3pm New York call shows at noon in Los Angeles. Its reminders keep their instant. |

Moving a timed task to another day keeps its wall-clock time and reminder lead, across
daylight-saving changes. Habit day arithmetic uses calendar dates, never 24-hour steps.

Midnight rollover and reminders re-evaluate when the zone changes: iOS listens for
`NSSystemTimeZoneDidChange` and `significantTimeChangeNotification`; Windows checks the
day and zone on focus, resume/unlock and every minute.

## Habit schedules and migration

`frequencyRule` is `DAILY`, `WEEKDAYS`, `WEEKENDS` or `WEEKLY`; `target` counts per day
(per week for `WEEKLY`). Clients older than this change read unknown values as daily.
Only habits repeat. On launch and after each sync both apps turn open repeating tasks into
habits with the same ID (`Migrations.run` on iOS, `migrateRecurring` on Windows): earlier
completed occurrences become check-ins and their task records stay; monthly and custom
rules become one-off tasks on their date. The output depends only on the records, and
`conversionData` (a restore aid) is ignored when comparing versions, so two devices
migrating the same data agree without a review.

## Someday

The built-in Someday list has the fixed ID `00000000-0000-4000-8000-000000000001` and is
created the first time something moves there, so two devices create identical records.
Someday items have no date and no reminders and never appear on Today.
