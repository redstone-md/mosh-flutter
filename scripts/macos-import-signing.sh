#!/usr/bin/env bash
# CI only: puts the self-signed code-signing identity into a throwaway
# keychain and exports MOSH_SIGN_IDENTITY for scripts/macos-package.sh.
#
# Reads MACOS_SIGNING_P12_BASE64 and MACOS_SIGNING_P12_PASSWORD (repo
# secrets made by scripts/macos-signing-cert.sh). Without them it does
# nothing, and the package script keeps the ad-hoc signature (forks, PRs
# from forks, local builds).
set -euo pipefail

if [ -z "${MACOS_SIGNING_P12_BASE64:-}" ]; then
  echo "no signing secret; the DMG stays ad-hoc signed"
  exit 0
fi

KEYCHAIN="$RUNNER_TEMP/mosh-signing.keychain-db"
P12="$RUNNER_TEMP/mosh-signing.p12"
KEYCHAIN_PASS="$(openssl rand -base64 24)"

printf '%s' "$MACOS_SIGNING_P12_BASE64" | base64 --decode > "$P12"
security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$MACOS_SIGNING_P12_PASSWORD" -T /usr/bin/codesign
# Let codesign use the key without a GUI prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null
# Search this keychain too, alongside the runner's own.
# shellcheck disable=SC2046
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
rm -f "$P12"

# The certificate is self-signed, so macOS does not trust it and `-v` would
# hide it; codesign signs with it by its SHA-1 hash all the same.
IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" | awk '/Mosh Self-Signed Code Signing/ { print $2; exit }')"
[ -n "$IDENTITY" ] || {
  echo "error: the imported p12 holds no Mosh code-signing identity" >&2
  exit 1
}
echo "MOSH_SIGN_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"
echo "signing identity ready: $IDENTITY"
