# TestFlight setup

Team: `5T6K789X4T`. App: `com.jaiten.orbit`. Widget:
`com.jaiten.orbit.widgets`. Shared group: `group.com.jaiten.orbit.shared`.

1. Register both explicit App IDs and assign the shared App Group to each.
2. Create an Apple Distribution certificate using the public certificate request.
   Keep its matching private key outside the repository. Export the certificate
   and private key together as a password-protected PKCS#12 (`.p12`) file.
3. Create two **App Store Connect** distribution provisioning profiles, one per
   App ID, selecting that certificate. Download both `.mobileprovision` files.
4. Create the iOS app record in App Store Connect using the main app's bundle ID.
5. Create an App Store Connect team API key with Developer access for build uploads.
   Save the downloaded `.p8` file privately, along with its Key ID and Issuer ID.
6. Configure these repository Actions secrets:

| Secret | Value |
| --- | --- |
| `CERTIFICATE_P12_BASE64` | Base64-encoded password-protected `.p12` |
| `P12_PASSWORD` | Password used when exporting that `.p12` |
| `APP_PROFILE_BASE64` | Base64 of the main app distribution profile |
| `WIDGET_PROFILE_BASE64` | Base64 of the widget distribution profile |
| `ASC_KEY_ID` | App Store Connect team API key ID |
| `ASC_ISSUER_ID` | App Store Connect API issuer ID |
| `ASC_PRIVATE_KEY` | Full PEM contents of the `.p8` file |

Do not commit any signing material or paste it in chat. The public CSR can be
uploaded to Apple's certificate form; it does not contain the private key.

### Share extension (optional)

The "Add to Orbit" share extension (`com.jaiten.orbit.share`) is built and tested in CI.
To ship it in TestFlight builds: register that App ID with the shared App Group, create
an App Store Connect distribution profile for it with the same certificate, and add its
base64 as the `SHARE_PROFILE_BASE64` secret. Without that secret, TestFlight builds leave
the extension out and everything else uploads as before.

A successful **iOS prototype** beta check for a push to `main` automatically starts
**TestFlight** for that tested commit. Pull requests and failed checks do not upload.
You can also use **Actions → TestFlight → Run workflow** on `main` for a manual retry.
The workflow signs and uploads through an ephemeral keychain. Build numbers increase
with every upload run and retry.

This does not submit the app for public App Store review or invite testers. Apple
still processes every uploaded build. Internal groups configured to include new
builds automatically will receive the update after processing. Other groups may
need the build added in App Store Connect.

The app declares that it does not use non-exempt encryption: current networking
uses operating-system HTTPS and credentials use Keychain. Revisit that declaration
if encryption features change.

## Faster beta testing

Pushes run all unit tests plus four UI smoke tests: capture/Undo, Notes pages,
Calendar task creation, and Settings/theme/habit history. The full 15-test UI
suite remains available; it is no longer required for every beta upload.

In **Actions → iOS prototype → Run workflow**, choose:

- `smoke`: the same unit + core UI checks used before automatic TestFlight uploads.
- `unit`: unit tests only (quick logic checks).
- `focused`: one test class/method; enter a filter such as
  `OrbitUITests/ChecklistUITests/testNotesHaveSectionsAndPages`.
- `full`: all unit and UI tests; use before a wider release or after broad UI changes.

Manual test runs never automatically upload. Use the TestFlight workflow for an
explicit manual upload. A `[skip testflight]` marker in a commit message runs CI
but suppresses its automatic upload, useful for test/CI-only changes.

The app/test bundles build once, and the selected tests run without rebuilding.
Compiled products are cached before UI tests start, so a failed UI assertion does
not discard a successful build. Xcode build products and module caches are reused
between compatible runs. A
clean checkout restores source modification dates from Git so incremental builds
can use that cache. The first run still pays the full build cost; simulator startup
and Apple's TestFlight processing remain outside this cache. Signing keys,
provisioning profiles and credentials are never stored in the build cache.

On a Mac, use Xcode's Run button on a connected iPhone for UI iteration, and click
the diamond beside an individual test to rerun it. This avoids a TestFlight upload
for each visual adjustment. Without a Mac, focused CI runs provide the same narrow
feedback loop through GitHub Actions.

## Processing confirmation

After upload, CI runs `scripts/wait_for_testflight.py` with the existing App Store
Connect identity. It finds the exact bundle and archived build number, waits for
Apple's `VALID` processing state, and records the internal testing state in the job
summary. A rejected, expired or unprocessed build does not pass this release gate.
The check uses read-only App Store Connect requests and does not change tester groups.
