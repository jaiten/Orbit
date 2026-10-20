# October product direction

Orbit has three jobs: capture a commitment, make a manageable daily plan, and make progress visible. Today is the checklist; Calendar shows available time; Lists stores to-dos that need a home. Habits has deeper history on demand. Ideas is hidden from the product; existing records are preserved.

Today layout and theme preferences are local to each device. Editing the home layout never deletes planner records. Pinned lists show all unfinished items, including future plans. The consistency strip uses current habits that existed on that day; daily targets are fractional and a weekly habit counts a check-in on that day. Deleting a habit removes its history, so this chart is not an immutable historical report.

“Days showing up” counts distinct local dates the app was opened, starting with this update; it is not a fabricated lifetime count or a consecutive streak. Local time suggestions count only the first visit per day, require three visits at a similar daytime hour, and are applied only when the user chooses them. No personal text leaves the device for coaching. General check-ins are opt-in local notifications.

## Account access

Devices lists real Supabase auth sessions, including sessions from earlier app versions. Multiple sessions can belong to one device. Names come from a client label or a conservative user-agent fallback. No access/refresh tokens or IP addresses are returned.

Removing access stores a revocation for the session ID. Both reads (RLS) and writes (`orbit_put`) check that the JWT session still exists and is not revoked. This blocks sync immediately without changing managed Auth tables. It does not remotely erase local files or prevent a person who knows the password from signing in again. Current-device sign-out calls the Auth local logout endpoint.

`orbit_devices` intentionally has no direct client grants or RLS policies: only the narrowly scoped RPCs may access it. The security-definer functions are intentional, have an empty search path, validate the caller's live session, and check ownership before revoking access. The Supabase advisor reports these callable RPCs; they must stay reviewed. Leaked-password protection remains an existing backend setting, outside this change.

Run `supabase/tests/device_access.sql` to verify account isolation, revoked reads/writes, and revoked session listing. The test rolls back synthetic fixtures.

## Next priorities

1. Reliability and forgiveness: a brief Undo after deletes and conversions, offline indicators only when action is needed, and tested restore/export.
2. A short evening review: what moved forward, what can wait, and at most three priorities for tomorrow. Avoid scores that punish taking a day off.
3. Calendar planning: conflict warnings and optional duration-based suggestions before considering more automation. Current calendar access uses iOS calendars, including configured Google accounts; it is not a Windows Google OAuth integration or two-way task sync.

Keep generated AI out of the critical path. Useful next local signals would be completion-time patterns and opt-in reminders that suppress themselves after the day's commitments are done. Establish enough real usage before adding more dashboards, social features, or customization controls.
