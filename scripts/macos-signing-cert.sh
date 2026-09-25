#!/usr/bin/env bash
# Makes the self-signed code-signing identity the macOS DMG is signed with.
# Run ONCE, keep the output folder safe, and store two repo secrets:
#
#   bash scripts/macos-signing-cert.sh [output-dir]   # default ~/.mosh-signing
#   gh secret set MACOS_SIGNING_P12_BASE64   < <output-dir>/mosh-signing.p12.b64
#   gh secret set MACOS_SIGNING_P12_PASSWORD < <output-dir>/mosh-signing.p12.pass
#
# Why: an ad-hoc signature names the app by its binary hash, which changes on
# every build, so macOS cannot keep a keychain "Always Allow" for it. This
# certificate names the app the same way in every build. It is NOT an Apple
# Developer ID: Gatekeeper still warns on first launch (CODE_SIGNING.md).
#
# Losing the key means the next build is a "new app" to the keychain again,
# once. Never commit anything from the output folder.
set -euo pipefail

OUT="${1:-$HOME/.mosh-signing}"
# Git Bash on Windows: a native openssl cannot open /c/... paths.
if command -v cygpath >/dev/null 2>&1; then
  OUT="$(cygpath -m "$OUT")"
fi
NAME="Mosh Self-Signed Code Signing"
DAYS=7300

[ -e "$OUT/mosh-signing.p12" ] && {
  echo "error: $OUT/mosh-signing.p12 exists; refusing to replace a live identity" >&2
  exit 1
}
mkdir -p "$OUT"
chmod 700 "$OUT"

cat > "$OUT/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days "$DAYS" \
  -config "$OUT/cert.cnf" \
  -keyout "$OUT/mosh-signing.key" -out "$OUT/mosh-signing.crt"

# macOS `security import` cannot read OpenSSL 3's default PKCS#12
# encryption, so the bundle uses the older SHA1/3DES scheme it accepts.
openssl rand -base64 24 | tr -d '\n' > "$OUT/mosh-signing.p12.pass"
openssl pkcs12 -export \
  -inkey "$OUT/mosh-signing.key" -in "$OUT/mosh-signing.crt" \
  -name "$NAME" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -passout "file:$OUT/mosh-signing.p12.pass" \
  -out "$OUT/mosh-signing.p12"
openssl base64 -A -in "$OUT/mosh-signing.p12" > "$OUT/mosh-signing.p12.b64"
chmod 600 "$OUT"/mosh-signing.*

echo "identity: $NAME"
echo "sha256:   $(openssl x509 -in "$OUT/mosh-signing.crt" -noout -fingerprint -sha256)"
echo "files in: $OUT"
echo "next:     gh secret set MACOS_SIGNING_P12_BASE64 < \"$OUT/mosh-signing.p12.b64\""
echo "          gh secret set MACOS_SIGNING_P12_PASSWORD < \"$OUT/mosh-signing.p12.pass\""
