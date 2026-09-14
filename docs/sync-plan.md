# Sync implementation boundary

No network requests or account credentials are used by the iOS prototype.
`supabase/migrations/0001_dayos.sql` is a future schema scaffold, not a deployed
backend. `shared/SyncContract.swift` defines the future transport boundary.

## Before enabling sync

- Add a versioned SwiftData migration and transactional outbox, user ownership,
  tombstones, server revision, and per-user pull cursors to the local models.
- Replace physical deletes with tombstones. Atomically write each mutation and its
  outbox entry. Existing prototype records must be explicitly imported into the
  authenticated account; do not mix users when switching accounts.
- Add Supabase Auth with secure token storage and refresh. Never embed a service
  role key. Test RLS with two independent users for every table and foreign key.
- Implement an idempotent revision-checked mutation RPC and deduplication table.
  The scaffold's `updated_at` is server time; it alone does not resolve offline
  conflicts. Return conflicts for edits based on stale revisions, or implement a
  documented deterministic last-write-wins rule without trusting device clocks.
- Pull pages ordered by `(updated_at, id)` with overlap/deduplication and a stable
  high-water mark. Commit data and cursor together. Upsert logs by
  `(user_id, habit_id, day_key)` to reconcile independent device IDs.
- Subscribe to authorized Postgres changes only after authentication. Treat events
  as invalidation, then pull; perform a full catch-up after reconnect or app resume.
  Realtime delivery is not a durable queue. Retry outbox uploads with backoff.
- Represent all-day dates separately from UTC instants and preserve the scheduling
  time zone. Expand custom RRULEs with a tested RFC 5545 library before exposing them.
- Test create/update/delete offline, account switching, expired tokens, repeated
  acknowledgments, conflicting habit counts, and deletion from a second device.

The SQL enables RLS and owner policies on every table and publishes those tables
for Postgres Changes. It is intended for a standard Supabase database that already
has `auth.users`, the `authenticated`/`anon` roles and `supabase_realtime` publication.
It has not been executed against a hosted project.

References: [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security),
[Realtime database changes](https://supabase.com/docs/guides/realtime/subscribing-to-database-changes).
