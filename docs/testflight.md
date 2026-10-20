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

A successful **iOS prototype** check for a push to `main` automatically starts
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
