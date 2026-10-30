# Small beta launch checklist

Items marked **Dashboard/owner** require access or business information that is not
available in the repository. Do not invite external testers until every required
item has an owner and evidence link.

## Readiness review — 30 October 2026

The repository has automated distribution, local persistence, conflict handling,
account deletion and regression coverage. Earlier main builds passed
[iOS smoke checks](https://github.com/jaiten/Orbit/actions/runs/40609646021),
[TestFlight upload](https://github.com/jaiten/Orbit/actions/runs/40610552420), and
[Windows packaging](https://github.com/jaiten/Orbit/actions/runs/40608963497).
Those results do not establish physical-device acceptance or operational readiness.

For this UI release, local checks passed 124 Windows unit tests, Chromium interaction
checks (lists, photo placement/delete/undo, saved layouts, quarter-hour rescheduling,
clock preferences and selection), the native Electron smoke test, Swift syntax
validation and CI-helper tests. Xcode type checking and simulator tests run in CI.
The website passed its type check, 34 parser cases and production static build.

Before inviting external testers, record evidence for these five gates:

1. **Release artifacts:** install the exact Windows 0.3.6 and TestFlight builds on
   clean devices. Verify Windows signature/timestamp and automatic upgrading from
   0.3.5. Signing-secret names could not be inspected with this session's GitHub
   integration; their presence and the executable's signature remain unverified.
2. **Device acceptance:** use iPhone + Windows with one account; test offline edits,
   reconnect, concurrent notes/photos, conflict resolution, removal of a device,
   account deletion, daylight-saving/timezone changes and widget completion.
   Confirm the iOS note keyboard accessory has no extra gap, large-text buttons
   fit, week-start changes work and progress preferences refresh widgets.
3. **Auth/backend:** confirm production migrations, owner isolation, advisor
   findings, SMTP delivery, confirmation, password recovery, rate limits and
   abuse protection on the actual beta project. Record dashboard evidence below.
4. **Recovery/operations:** demonstrate a staging backup restore; monitor sync and
   email failures without planner content; assign incident/support ownership and
   a small invitation cap.
5. **Public information:** verify the real support contact and privacy notice,
   App Store privacy answers and the deployed TestFlight join URL. The website's
   source fallback still contains `REPLACE_ME`; a deployment override must supply
   the real link. Its Windows installer link is now concrete.

The unchecked items below remain open until there is evidence, even when the
corresponding implementation exists.

## Backend and authentication

- [ ] Apply all migrations through `supabase db push` from a reviewed main commit.
- [ ] Run `supabase test db`, Security Advisor and Performance Advisor; record or
      resolve every finding. Reviewed security-definer RPCs must keep explicit
      caller/session checks, empty search paths and restricted execute grants.
- [ ] **Dashboard/owner:** use a paid, non-pausing Supabase project for the beta.
- [ ] **Dashboard/owner:** enable SSL enforcement, organization MFA and least-privilege
      project membership. Decide whether database network restrictions fit support access.
- [ ] **Dashboard/owner:** configure custom SMTP on the Orbit domain, disable link
      tracking, publish SPF/DKIM/DMARC, and test signup, confirmation and recovery.
- [ ] **Dashboard/owner:** enable CAPTCHA for signup/sign-in/recovery, leaked-password
      protection, email confirmation, a maximum one-hour OTP lifetime and reviewed Auth limits.
- [ ] Verify account deletion on iPhone and Windows, then confirm the Auth user,
      records, sessions, device rows and quota row are gone.
- [ ] Verify a removed device cannot read, write or continue receiving Realtime events.

## Recovery and operations

- [ ] **Dashboard/owner:** confirm daily backups and retention; enable PITR if the
      chosen recovery-point objective requires it.
- [ ] Restore the staging project from backup and document recovery time and data loss.
- [ ] Publish content-free monitoring for sync duration/error code, pending changes,
      conflicts, transferred bytes, reconnects, database CPU/latency, Realtime lag and SMTP failures.
- [ ] Run a staged load test with realistic histories and define beta thresholds
      (for example p95 visible sync under two seconds and zero cross-account reads).
- [ ] Create an incident contact and a tester status/update channel.

## Distribution and policy

- [ ] Replace the contact wording in `docs/privacy.md` with the real support email,
      effective date and published privacy-policy URL.
- [ ] Complete App Store privacy answers from the published notice and verify the
      included `PrivacyInfo.xcprivacy` is present in each archived app/extension target.
- [ ] **Owner:** configure `WINDOWS_CERTIFICATE_BASE64` and
      `WINDOWS_CERTIFICATE_PASSWORD`; verify the released `.exe` signature and timestamp.
- [ ] Test the exact TestFlight and signed Windows artifacts on clean physical devices.
- [ ] Document how beta users receive urgent security updates; do not leave a known
      vulnerable Windows build downloadable.

## Beta scope

- [ ] Keep invitations capped and increase them only after reviewing one week of
      sync, database, Realtime and email metrics.
- [ ] Keep the two-minute fallback sync for the beta. Prioritize incremental cursor
      sync, batched writes and tombstone compaction before a broad public launch.

