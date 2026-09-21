# Code signing policy

Mosh ships **unsigned**. The SignPath Foundation application was
declined, and no other certificate — Apple Developer ID included —
exists today, so neither platform signs release binaries. The
SHA-256 checksums published beside every release artifact are the
integrity check.

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

## Why the macOS ad-hoc signature is not "signing"

`flutter build macos --release` applies an ad-hoc signature through
Xcode's "Sign to Run Locally". It identifies nobody — it only satisfies
the Apple Silicon requirement that every executable carry some
signature. Gatekeeper still treats the app as unidentified, which is
why the "Open Anyway" flow applies.

## If signing ever returns

- **Windows** — a new SignPath application or another open-source
  certificate; the release workflow then submits the built artifacts
  for signing.
- **macOS** — an Apple Developer Program membership ($99/year) upgrades
  the packaging script in place: `codesign --sign "Developer ID
  Application: ..." --options runtime --timestamp`, then `xcrun
  notarytool submit` + `xcrun stapler staple` on the DMG. Once
  notarized, the Gatekeeper paragraph in README is deleted.
