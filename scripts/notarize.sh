#!/bin/bash
# Signs Flow with a Developer ID certificate, sends it to Apple for
# notarization, and staples the result.
#
#   ./scripts/notarize.sh
#
# This is what makes the app open on someone else's Mac with a double-click.
# Everything else in this repo is a workaround for not having done it.
#
# One-time setup:
#   1. Join the Apple Developer Program ($99/year) at developer.apple.com
#   2. Create a "Developer ID Application" certificate in the developer portal
#      and install it (Xcode > Settings > Accounts > Manage Certificates, or
#      download the .cer and double-click it)
#   3. Create an app-specific password at appleid.apple.com > Sign-In and
#      Security > App-Specific Passwords
#   4. Store it once:
#        xcrun notarytool store-credentials "free-flow" \
#          --apple-id "you@example.com" \
#          --team-id "YOURTEAMID" \
#          --password "abcd-efgh-ijkl-mnop"

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

APP_NAME="Flow"
BUNDLE="$ROOT/build/$APP_NAME.app"
PROFILE="${NOTARY_PROFILE:-free-flow}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
DMG="$ROOT/build/FreeFlow-$VERSION.dmg"

# `|| true` matters: grep exits non-zero when there is no such certificate,
# and under `set -e` that would kill the script before the helpful message
# below ever printed.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 \
  | sed -E 's/.*"(.*)"/\1/' || true)"

if [[ -z "$IDENTITY" ]]; then
  cat >&2 <<'EOF'
!! No "Developer ID Application" certificate found.

   Without one, Apple will not notarize the app, and macOS will block it on
   every machine except the one that built it. There is no way around this
   short of asking each person to override Gatekeeper by hand.

   See the setup steps at the top of this script.
EOF
  exit 1
fi

echo "==> Signing with: $IDENTITY"
# --options runtime enables the hardened runtime, which notarization requires.
# Signing is inside-out: nested code first, the bundle last.
find "$BUNDLE/Contents" -name "*.bundle" -o -name "*.dylib" -o -name "*.framework" \
  | while read -r nested; do
      codesign --force --timestamp --options runtime --sign "$IDENTITY" "$nested"
    done

codesign --force --timestamp --options runtime \
  --entitlements "$ROOT/Resources/Flow.entitlements" \
  --sign "$IDENTITY" "$BUNDLE"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$BUNDLE"

echo "==> Building the disk image"
"$ROOT/scripts/package-dmg.sh"

echo "==> Signing the disk image"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "==> Submitting to Apple (this usually takes 1-5 minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> Stapling the ticket"
# Stapling attaches Apple's approval to the file, so it opens even offline.
xcrun stapler staple "$DMG"

echo "==> Verifying the finished article"
spctl -a -t open --context context:primary-signature -vvv "$DMG"

echo
echo "==> Done: $DMG"
echo "    This will open with a double-click on any Apple Silicon Mac."
