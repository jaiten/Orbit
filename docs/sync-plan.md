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
Real email confirmation needs an acceptance check; production SMTP and account
recovery UX are not configured by this implementation.

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
