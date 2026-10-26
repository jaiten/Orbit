# Small beta launch checklist

Items marked **Dashboard/owner** require access or business information that is not
available in the repository. Do not invite external testers until every required
item has an owner and evidence link.

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

