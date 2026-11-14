# Code signing policy

The macOS DMG is signed with an Apple Developer ID and notarized, so macOS
opens it without a warning. The iOS app is signed for the App Store and
reaches users through TestFlight. Windows downloads from GitHub ship **without a
trusted signature**: the SignPath Foundation application was declined, and
no other Windows certificate exists. The Microsoft Store package is the
exception there, because the Store signs it before anyone installs it. The
SHA-256 checksums published beside every release artifact are the integrity
check.

Android release APKs use a separate persistent release key; Android accepts
self-signed app certificates and requires the same signing identity for updates.
Release builds refuse missing credentials instead of using a debug signature.
The key is held in GitHub Secrets with an independent private backup; the public
certificate fingerprint is pinned by `ANDROID_SIGNING_CERT_SHA256`.
See [Android release builds](docs/Features/android-release.md).

## What a user sees

- **Windows**: SmartScreen on first run: **More info**, then
  **Run anyway**. The Microsoft Store build carries the Store's
  signature and installs without a warning; see
  [Windows release builds](docs/Features/windows-release.md).
- **macOS (12+)**: only the question macOS asks before the first launch of
  any app from the internet. No "Open Anyway" detour.

## macOS: Developer ID and notarization

`flutter build macos --release` applies an ad-hoc signature through
Xcode's "Sign to Run Locally". The release workflow re-signs the bundle with
the Developer ID Application certificate and submits the DMG to Apple's
notary service:

- `scripts/apple-import-identity.sh` (CI) loads the certificate into a
  throwaway keychain, sets `MOSH_SIGN_IDENTITY` and warns in the run
  summary 30 days before the certificate expires.
- `scripts/macos-package.sh` signs the bundle inside out with that identity,
  the hardened runtime and a secure timestamp, keeping the sandbox
  entitlements from `macos/Runner/Release.entitlements`. It then builds the
  DMG and signs the DMG too.
- `scripts/macos-notarize.sh` sends the DMG to `notarytool`, staples the
  ticket to it and checks it with `stapler validate` and `spctl`. If Apple
  rejects it, the build fails and prints Apple's log. The checksum is taken
  after stapling, because stapling rewrites the file.

Releases notarize (`notarize: true` in `release.yml`, and the default of a
manual run). CI proof builds only sign, so Apple's queue never slows a PR.
Without the secrets (forks, local builds) the app keeps the ad-hoc signature
and nothing is notarized.

The secrets in `redstone-md/mosh-flutter`:

- `APPLE_DEVELOPER_ID_P12_BASE64`, `APPLE_DEVELOPER_ID_P12_PASSWORD`: the
  Developer ID Application certificate (G2), its key and Apple's G2
  intermediate as a base64 .p12, encrypted with PBE-SHA1-3DES so that
  `security import` reads it.
- `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_ID`,
  `APP_STORE_CONNECT_KEY_P8_BASE64`: the App Store Connect API key "Mosh CI"
  (App Manager) that `notarytool` and the iOS export log in with.
- The repo variable `APPLE_TEAM_ID` holds the Team ID.

The maintainers keep the .p12, its password and the .p8 in their password
manager. The certificate expires five years after issue: a new one changes
nothing for users, since the designated requirement names the Team ID, not
the certificate. Losing the key means revoking the certificate on
developer.apple.com and issuing a new one.

Releases up to 0.29 carried a self-signed certificate. Its designated
requirement named that certificate, so the first Developer ID update is a
new app to macOS once: it may ask again for the camera and microphone.

## iOS: App Store signing

`.github/workflows/build-ios.yml` archives the app unsigned, then
`scripts/ios-package.sh` exports it for the App Store and, with `upload`,
sends it to TestFlight. Automatic signing at the archive would want a
development profile, and that needs a registered device; the export needs
only the App Store profile, which Xcode fetches or creates with the API key.
The certificate is the Apple Distribution identity that
`scripts/apple-import-identity.sh` loads, because cloud-managed certificates
need an Admin key and the CI key stays App Manager.

- `APPLE_DISTRIBUTION_P12_BASE64`, `APPLE_DISTRIBUTION_P12_PASSWORD`: the
  Apple Distribution certificate, its key and Apple's WWDR intermediate, made
  by `scripts/apple-distribution-wizard.sh` (no Mac needed).

The certificate expires a year after issue, and the iOS build warns 30 days
ahead. To renew, run the wizard again, wait for a green build and revoke the
old certificate on developer.apple.com. Users are not affected: an installed
app keeps working, and the next build simply carries the new signature.

The history key stays in a file in the app container rather than the
keychain ([ADR 0011](docs/ADR/0011-secure-storage-and-threat-model.md)).
