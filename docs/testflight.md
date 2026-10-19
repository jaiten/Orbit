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

After normal iOS CI passes for the intended commit, run **Actions → TestFlight →
Run workflow**, selecting `main`. This signs and uploads the build, but does not
submit it for public App Store review or automatically invite testers. Wait for
Apple processing, answer any export compliance questions accurately, then add the
build to your internal testing group in App Store Connect.

The workflow is restricted to manual runs on main and uses an ephemeral keychain.
Signed archive/export and Apple's processing cannot be verified until credentials
are configured. Build numbers increase with each workflow run and retry.
