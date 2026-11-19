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

## Codemagic: automatic fallback when GitHub can't build

GitHub Actions is the main iOS pipeline. [Codemagic](https://codemagic.io) (500 free macOS minutes a month
on a personal account) takes over automatically when GitHub can't run, for example when the Actions
minutes run out. `codemagic.yaml` starts on the same pushes (to `main`, changing `ios/` or `shared/`), and
its first step, `scripts/defer_to_github.py`, asks GitHub whether its iOS run for that commit got a runner:

- **It did:** GitHub has the build; Codemagic stops (about a minute of Codemagic time).
- **GitHub cancelled it unstarted, or no runner came within 6 minutes:** Codemagic cancels GitHub's queued
  run, so only one of them uploads, then runs the unit tests and uploads to TestFlight itself.
- A commit saying `[skip testflight]` is skipped on both. A build started by hand in Codemagic with the
  variable `FORCE_BUILD=true` skips the check and always builds.

Both verify Apple processing with `scripts/wait_for_testflight.py` after uploading, before reporting success.
Both run `scripts/prepare_testflight.py`, whose build number is minutes since 1 January 2026 (UTC) plus
20000, so each upload is higher than the last whichever service built it.

### Setup (all in a browser)

1. Sign in at codemagic.io with GitHub (your **personal** account; team accounts get no free minutes) and
   add the `jaiten/Orbit` repository.
2. Make a GitHub token for the check: GitHub → Settings → Developer settings → Fine-grained tokens →
   Generate. Repository access: only `jaiten/Orbit`. Permissions: **Actions: Read and write**.
3. In the app's **Environment variables**, create a group named `orbit_testflight` and add, as *secure*
   variables: `CERTIFICATE_P12_BASE64`, `P12_PASSWORD`, `APP_PROFILE_BASE64`, `WIDGET_PROFILE_BASE64`,
   `SHARE_PROFILE_BASE64` (optional), `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY` (the same values as
   the GitHub secrets above; GitHub never shows them again, so use the original files) and `GITHUB_TOKEN`.
   On Windows, copy a file as base64 with PowerShell:
   `[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\file")) | Set-Clipboard`.
4. Codemagic adds the push webhook to GitHub when the app is added; check it under the app's settings →
   Webhooks if builds don't start.

If a file is lost: a new App Store Connect API key can be made in App Store Connect → Users and Access →
Integrations. A lost certificate or profile can be replaced from the Apple Developer website (Certificates,
Identifiers & Profiles).

## Apple SDK notices

ITMS-90725 on builds 482241 and 482285 is an SDK deadline notice, not an upload
rejection: Apple's delivery email says the delivery succeeded and gives an April
2027 deadline for the iOS 27 SDK / Xcode 27. Xcode 26.3 includes the iOS 26.2 SDK,
which explains the warning on the previous build.

The simulator and TestFlight workflows now use GitHub's `xcode-27` runner with
Xcode 27.2 selected explicitly. The Codemagic fallback also selects Xcode 27.2.
`scripts/check_ios_sdk.py` rejects a toolchain below Xcode/iOS SDK 27 and checks
the actual `DTSDKName` in the archived app and every extension before export or
upload. PR CI builds an unsigned device archive and verifies that metadata as
well as running simulator tests; it needs no distribution credentials and does
not upload to Apple.

The minimum supported device OS remains iOS 17. Building with a newer SDK does
not require raising the deployment target. An already delivered binary cannot
be updated in place: after merging the reviewed changes, the next signed build
gets a new build number, is uploaded, and must finish Apple processing. Do not
call the warning resolved for a delivery until that new package is verified.
Codemagic's runtime and the real signed upload still need verification when used.

Toolchain references:
- [Apple's Xcode SDK table](https://developer.apple.com/xcode/system-requirements)
- [GitHub Xcode 27 runner software](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
- [Codemagic Xcode 27.2 image](https://docs.codemagic.io/specs-macos/xcode-27-2/)
