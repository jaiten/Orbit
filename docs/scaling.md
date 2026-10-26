# Scaling Orbit

Orbit can keep the native clients and Supabase. There is no reason to rewrite either client for an initial public beta. This is an implementation review, not a measured capacity guarantee: no production load test has been run.

## Current constraints

- `ios/App/SyncService.swift` and `windows/sync.cjs` download every owner record on each catch-up, with 500-record pages. Windows uses Realtime with a two-minute fallback poll; iOS catches up on foreground and Realtime wakeups. This is acceptable for a capped beta, but each catch-up still grows with the owner's full history.
- Local snapshot capture, record lookup and conflict detection scan collections repeatedly. History growth makes these scans increasingly expensive. Undo retains only the changed records, but calculating that difference also uses snapshots.
- The backend's `(user_id, key)` primary-key index supports current owner/key access. The database enforces ownership and session revocation. Preserve those checks when introducing new endpoints.
- Widgets use the shared local store and refresh at iOS's discretion. They are not a separate background sync engine. A user must reopen Orbit for widget edits to upload with the existing architecture.
- The default Supabase mailer is for testing, not a public signup/recovery service. Public rollout requires a custom SMTP provider and tested deliverability. No provider has been purchased or configured as part of this change.

## Before inviting a public beta

1. Test signup, confirmation, password recovery and device revocation on physical devices with production SMTP. Retain the PKCE same-device recovery flow. Verify App Store privacy information against actual telemetry and data use.
2. Test offline edits, repeated reconnections, different time zones, concurrent habit check-ins, deletions/restores and expired sessions across real iPhone/Windows accounts. Keep backups and exercise database restoration as well as client imports.
3. Add content-free operational metrics: sync duration, errors by code, pending-change count, conflicts, transferred bytes and reconnect frequency. Do not log planner titles, email links, passwords or session tokens. Measure active users separately from simultaneously open clients.
4. Run a staged load test against a staging project, with isolated test accounts and realistic record histories. Set product targets such as a p95 visible sync delay below two seconds, then measure rather than advertise unproven capacity.

## First architecture upgrade: incremental sync

Introduce an owner-scoped change feed and a durable cursor. A transactional outbox must preserve committed change order; a bare timestamp or global sequence without commit-order guarantees can skip concurrent transactions. Keep tombstones long enough for offline clients to catch up, with a full-snapshot recovery path for expired cursors.

Batch writes, acknowledge individual mutation IDs, and fetch only records after the saved cursor. Persist that cursor only after the corresponding local transaction commits. Use Realtime as an invalidation signal and keep a slower reconnect/foreground fallback. Avoid a full catch-up for every change event in a burst.

After correctness is proven, consider private per-user Broadcast channels instead of table-wide Postgres Changes subscriptions. Derive authorization from the authenticated owner and session, not a client-supplied channel name. Test revoked sessions on both reads and event delivery. Supabase documents the authorization work and single-thread ordering constraints of Postgres Changes:

- [Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes)
- [Subscribing to database changes](https://supabase.com/docs/guides/realtime/subscribing-to-database-changes)
- [Realtime reports](https://supabase.com/docs/guides/realtime/reports)

## Grow in measured stages

Start with a small invited beta, fix reliability issues, and then increase invitations. Watch database CPU, query latency, connections, egress, Realtime lag and email rejection rates. Optimize the bottleneck shown by those measurements before changing instance size or topology. At higher usage, infrastructure will have operating costs even if Orbit remains free for users.

Use these current upstream references when making deployment decisions:

- [Supabase production checklist](https://supabase.com/docs/guides/deployment/going-into-prod)
- [Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp)
- [Password recovery](https://supabase.com/docs/guides/auth/passwords)

## Product priorities after this release

Keep the main loop small: capture, choose a manageable day, check in, reflect. Useful next additions are planned rest days, a gentle weekly review, reusable routines and optional duration suggestions when planning. Avoid a large settings surface or generated AI until usage demonstrates a concrete need. Local coaching should remain explainable and opt-in.
