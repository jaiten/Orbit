# Small beta launch checklist

Items marked **Dashboard/owner** require access or business information that is not
available in the repository. Do not invite external testers until every required
item has an owner and evidence link.

## Readiness review — 30 October 2026

The repository has automated distribution, local persistence, conflict handling,
account deletion and regression coverage. Windows 0.3.10 passed
[unit, browser, native app and installer checks](https://github.com/jaiten/Orbit/actions/runs/41130279959)
and is [published with installer, portable app and update feed](https://github.com/jaiten/Orbit/releases/tag/v0.3.10).
Those results do not establish physical-device acceptance or operational readiness.

Local checks passed 125 Windows unit tests, Chromium interaction checks and the
native Electron smoke test. The regression coverage includes past-day corrections,
fully closed completion rings, bulk overdue moves, independent note sections and
task categories, note image placement/deletion/undo, drag layouts, quarter-hour
rescheduling and calendar preferences. All 76 Swift source files passed syntax
validation, and 10 CI-helper tests passed. The final iOS source passed Xcode builds
and [52 unit tests plus four UI tests](https://github.com/jaiten/Orbit/actions/runs/41128489744),
including selecting a past day and resetting to Today on return.
The signed [iOS 0.2.0 (8001) release](https://github.com/jaiten/Orbit/actions/runs/41131092543)
was uploaded to TestFlight. App Store Connect confirmed **VALID** processing and
**IN_BETA_TESTING** at 21:37 UTC on 30 October 2026.
The website passed its type check and production static build; the download link
points to the published 0.3.10 installer.

Before inviting external testers, record evidence for these five gates:

1. **Release artifacts:** install Windows 0.3.10 and TestFlight 0.2.0 (8001) on
   clean devices and verify automatic upgrading from 0.3.9. The downloaded 0.3.10
   installer is **unsigned**: its PE Authenticode certificate table is absent. Its
   SHA-256 matches the published GitHub asset digest. Configure a publisher
   certificate, then verify its signature and timestamp on the next signed release.
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
   App Store privacy answers and the deployed TestFlight join URL. The live site
   still links to `https://testflight.apple.com/join/REPLACE_ME` (verified 30 October).
   Set `NEXT_PUBLIC_TESTFLIGHT_URL` to the real public beta URL before invitations.
   The live Windows link points to the verified 0.3.10 installer.

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

