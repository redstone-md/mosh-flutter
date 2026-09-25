# Code signing policy

Mosh ships **without a trusted signature**. The SignPath Foundation
application was declined, and no other certificate — Apple Developer ID
included — exists today, so neither platform is signed by an identity
the OS trusts. The SHA-256 checksums published beside every release
artifact are the integrity check. The macOS app does carry a
self-signed signature, for the keychain only (below).

## What a user sees

- **Windows** — SmartScreen on first run: **More info**, then
  **Run anyway**.
- **macOS (12+)** — Gatekeeper blocks the first launch: try to open the
  app once, then **System Settings → Privacy & Security → Security →
  Open Anyway** (Apple's documented flow; the button is offered for
  about an hour after the blocked attempt, then enter your login
  password). On macOS 14 and older, right-click → **Open** also works.
  Terminal equivalent: `xattr -dr com.apple.quarantine
  /Applications/mosh.app`.

The warning repeats for every newly downloaded build; that is the cost
of an unsigned channel.

## The macOS self-signed signature

`flutter build macos --release` applies an ad-hoc signature through
Xcode's "Sign to Run Locally". An ad-hoc signature names the app by the
hash of its binary, which changes with every build. The keychain
remembers "Always Allow" by that name, so each build was a new app to
it, and macOS asked for the login password again to reach the history
key.

So the release DMG is re-signed with a self-signed certificate,
"Mosh Self-Signed Code Signing". The app's name to macOS is now
"this identifier, signed by this certificate", the same in every build,
and "Always Allow" holds across updates. It does **not** make the app
trusted: Gatekeeper still treats it as unidentified, which is why the
"Open Anyway" flow applies. The data-protection keychain (no prompt at
all) still needs an Apple team, so the app keeps using the login
keychain.

How it is wired:

- `scripts/macos-signing-cert.sh` makes the certificate and key once.
  The maintainer keeps the output folder safe and stores two repo
  secrets: `MACOS_SIGNING_P12_BASE64` and `MACOS_SIGNING_P12_PASSWORD`.
- `scripts/macos-import-signing.sh` (CI) loads them into a throwaway
  keychain and sets `MOSH_SIGN_IDENTITY`.
- `scripts/macos-package.sh` signs the bundle inside out with that
  identity and prints the designated requirement. Without the secrets
  (forks, local builds) it keeps the ad-hoc signature.

Losing the key costs one more password prompt per install when a new
certificate replaces it. Rotating it on purpose has the same cost.

## If signing ever returns

- **Windows** — a new SignPath application or another open-source
  certificate; the release workflow then submits the built artifacts
  for signing.
- **macOS** — an Apple Developer Program membership ($99/year) replaces
  the self-signed identity in the packaging script: `codesign --sign "Developer ID
  Application: ..." --options runtime --timestamp`, then `xcrun
  notarytool submit` + `xcrun stapler staple` on the DMG. Once
  notarized, the Gatekeeper paragraph in README is deleted.
