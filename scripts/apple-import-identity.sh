#!/usr/bin/env bash
# CI only: puts an Apple signing identity from a .p12 into a throwaway
# keychain and exports MOSH_SIGN_IDENTITY (its SHA-1) and
# MOSH_SIGN_CERT_SERIAL to later steps.
#
#   APPLE_P12_BASE64=... APPLE_P12_PASSWORD=... \
#     bash scripts/apple-import-identity.sh "Developer ID Application"
#
# The argument is the certificate kind: "Developer ID Application" for the
# macOS DMG, "Apple Distribution" for the iOS app (CODE_SIGNING.md). Without
# APPLE_P12_BASE64 it does nothing, and the build stays unsigned or ad-hoc
# signed (forks, local builds). A certificate that expires within 30 days
# warns in the run summary, so the renewal is not a failed release.
set -euo pipefail

KIND="$1"
WARN_DAYS=30

if [ -z "${APPLE_P12_BASE64:-}" ]; then
  echo "no $KIND certificate; the build is not signed with it"
  exit 0
fi

KEYCHAIN="$RUNNER_TEMP/mosh-signing.keychain-db"
P12="$RUNNER_TEMP/mosh-signing.p12"
KEYCHAIN_PASS="$(openssl rand -base64 24)"

printf '%s' "$APPLE_P12_BASE64" | base64 --decode > "$P12"
security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$APPLE_P12_PASSWORD" -T /usr/bin/codesign
# Let codesign use the key without a GUI prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null
# Search this keychain too, alongside the runner's own.
# shellcheck disable=SC2046
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
rm -f "$P12"

# `-v` lists only identities whose chain macOS trusts: the p12 carries
# Apple's intermediate, the runner has Apple's root.
IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" |
  awk -v kind="\"$KIND: " 'index($0, kind) { print $2; exit }')"
[ -n "$IDENTITY" ] || {
  echo "error: the imported p12 holds no trusted $KIND identity" >&2
  exit 1
}
echo "MOSH_SIGN_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"
echo "signing identity ready: $IDENTITY"

# The identity's certificate: the PEM after its "SHA-1 hash:" line.
CERT="$(security find-certificate -a -Z -p "$KEYCHAIN" |
  awk -v sha="$IDENTITY" '/^SHA-1 hash:/ { keep = ($3 == sha); next } keep')"
# The serial names the certificate in the App Store Connect API (ios-profile.mjs).
echo "MOSH_SIGN_CERT_SERIAL=$(openssl x509 -noout -serial <<< "$CERT" | cut -d= -f2)" >> "$GITHUB_ENV"
expires="$(openssl x509 -noout -enddate <<< "$CERT" | cut -d= -f2)"
echo "certificate expires: $expires"
if ! openssl x509 -noout -checkend $((WARN_DAYS * 86400)) <<< "$CERT" >/dev/null; then
  echo "::warning::The $KIND certificate expires on $expires. Renew it (CODE_SIGNING.md)."
fi
