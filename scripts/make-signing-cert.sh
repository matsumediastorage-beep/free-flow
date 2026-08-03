#!/bin/bash
# Creates a stable self-signed code-signing identity named "Matsu Flow Dev".
#
# Why this exists:
#   macOS ties Accessibility / Input Monitoring / Microphone grants to an app's
#   code signature. Ad-hoc signing (`codesign -s -`) mints a brand new identity
#   on every build, so macOS quietly forgets the permissions and Flow stops
#   responding to the hotkey with no error message.
#
#   Signing with a cert that stays the same across rebuilds gives the app a
#   stable identity, so you grant permissions once and they stick.
#
# Run this ONCE:
#   ./scripts/make-signing-cert.sh
#
# You may be asked for your login password when the trust setting is applied.

set -euo pipefail

IDENTITY_NAME="Matsu Flow Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Apple's LibreSSL, NOT whatever `openssl` resolves to on PATH.
#
# This matters: Homebrew's OpenSSL 3.x writes PKCS#12 bundles with an AES-256 /
# SHA-256 MAC that Apple's Security framework cannot verify, and `security
# import` fails with the very misleading "MAC verification failed during PKCS12
# import (wrong password?)" — the password is fine, the algorithm isn't.
OPENSSL="/usr/bin/openssl"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

if security find-identity -v -p codesigning | grep -q "$IDENTITY_NAME"; then
  echo "==> '$IDENTITY_NAME' already exists. Nothing to do."
  security find-identity -v -p codesigning | grep "$IDENTITY_NAME"
  exit 0
fi

echo "==> Generating self-signed code-signing certificate"

# extendedKeyUsage=codeSigning is what makes codesign accept it.
cat > "$WORKDIR/openssl.cnf" <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[ dn ]
CN = Matsu Flow Dev

[ ext ]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
subjectKeyIdentifier   = hash
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORKDIR/key.pem" \
  -out "$WORKDIR/cert.pem" \
  -days 3650 \
  -config "$WORKDIR/openssl.cnf" 2>/dev/null

# A real password, not an empty one — `security import` handles empty passwords
# inconsistently. The value doesn't matter; the bundle is deleted on exit.
P12_PASS="matsu-flow-transient"

"$OPENSSL" pkcs12 -export \
  -inkey "$WORKDIR/key.pem" \
  -in "$WORKDIR/cert.pem" \
  -out "$WORKDIR/identity.p12" \
  -name "$IDENTITY_NAME" \
  -passout "pass:$P12_PASS" 2>/dev/null

echo "==> Importing into your login keychain"
# -A lets codesign use the key without a GUI prompt on every build. This is a
# throwaway cert that only ever signs this app and carries no authority
# anywhere else, so the convenience is worth it for a dev loop.
security import "$WORKDIR/identity.p12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASS" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -A

echo "==> Marking it trusted for code signing"
# User trust domain — no sudo needed, though macOS may ask for your password.
if ! security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" \
  "$WORKDIR/cert.pem" 2>/dev/null; then
  echo "    Trust step needed a dialog or was declined."
  echo "    If codesign complains later: open Keychain Access, find"
  echo "    '$IDENTITY_NAME', Get Info > Trust > Code Signing: Always Trust."
fi

echo
if security find-identity -v -p codesigning | grep -q "$IDENTITY_NAME"; then
  echo "==> Success."
  security find-identity -v -p codesigning | grep "$IDENTITY_NAME"
  echo
  echo "    build-app.sh will pick this up automatically from now on."
  echo "    Next: rebuild, then grant permissions one final time."
else
  echo "!! Identity was not registered. Fall back to the manual route:" >&2
  echo "   Keychain Access > Certificate Assistant > Create a Certificate…" >&2
  echo "   Name: $IDENTITY_NAME | Identity Type: Self Signed Root" >&2
  echo "   Certificate Type: Code Signing | check 'Let me override defaults'" >&2
  exit 1
fi
