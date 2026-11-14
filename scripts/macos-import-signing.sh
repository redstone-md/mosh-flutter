#!/usr/bin/env bash
# CI only: puts the Developer ID Application identity into a throwaway
# keychain and exports MOSH_SIGN_IDENTITY for scripts/macos-package.sh.
#
# Reads APPLE_DEVELOPER_ID_P12_BASE64 and APPLE_DEVELOPER_ID_P12_PASSWORD
# (repo secrets, see CODE_SIGNING.md). Without them it does nothing, and the
# package script keeps the ad-hoc signature (forks, PRs from forks, local
# builds).
set -euo pipefail

if [ -z "${APPLE_DEVELOPER_ID_P12_BASE64:-}" ]; then
  echo "no signing secret; the DMG stays ad-hoc signed"
  exit 0
fi

KEYCHAIN="$RUNNER_TEMP/mosh-signing.keychain-db"
P12="$RUNNER_TEMP/mosh-signing.p12"
KEYCHAIN_PASS="$(openssl rand -base64 24)"

printf '%s' "$APPLE_DEVELOPER_ID_P12_BASE64" | base64 --decode > "$P12"
security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$APPLE_DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign
# Let codesign use the key without a GUI prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null
# Search this keychain too, alongside the runner's own.
# shellcheck disable=SC2046
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
rm -f "$P12"

# `-v` lists only identities whose chain macOS trusts: the p12 carries
# Apple's Developer ID G2 intermediate, the runner has Apple's root.
IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk '/"Developer ID Application: / { print $2; exit }')"
[ -n "$IDENTITY" ] || {
  echo "error: the imported p12 holds no trusted Developer ID Application identity" >&2
  exit 1
}
echo "MOSH_SIGN_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"
echo "signing identity ready: $IDENTITY"
