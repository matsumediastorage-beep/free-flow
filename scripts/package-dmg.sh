#!/bin/bash
# Packages Flow.app into a drag-to-Applications disk image.
#
#   ./scripts/package-dmg.sh            # uses the existing build/Flow.app
#   ./scripts/package-dmg.sh --build    # rebuilds first
#
# A DMG rather than a zip because it carries the /Applications symlink, so
# "install" is one drag — and because macOS keys permissions to the app's path,
# which makes "put it in /Applications" a functional requirement here, not a
# convention. A zip invites people to run it from ~/Downloads, where their
# grants break the moment they move it.
#
# NOTE: this does not make the app distributable on its own. Read the
# Distribution section of the README — without Developer ID signing plus
# notarization, Gatekeeper blocks this on every Mac but the one that built it.

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

APP_NAME="Flow"
BUNDLE="$ROOT/build/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
DMG="$ROOT/build/MatsuFlow-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

for arg in "$@"; do
  [[ "$arg" == "--build" ]] && "$ROOT/scripts/build-app.sh" release
done

if [[ ! -d "$BUNDLE" ]]; then
  echo "!! No $BUNDLE — run ./scripts/build-app.sh release first" >&2
  exit 1
fi

echo "==> Staging"
cp -R "$BUNDLE" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

# A short read-me visible in the mounted image, because the permission grants
# are not optional and nobody reads a repo before dragging an icon.
cat > "$STAGING/READ ME FIRST.txt" <<'EOF'
Matsu Flow
==========

1. Drag Flow.app onto the Applications folder.
   Keep it there — macOS ties permissions to the app's location.

2. Open it. It will ask for three permissions:
     Accessibility     — pastes text into whatever app you're using
     Input Monitoring  — notices when you hold the dictation key
     Microphone        — hears you
   macOS requires you to grant these by hand. The setup window links
   straight to the right page for each.

3. First launch downloads about 600MB of speech model, once.
   The menu bar shows progress. After that it works offline.

4. Hold Left Shift, talk, release. Text appears at your cursor.
   Prefer a different key? Settings -> Dictation key.

Requires an Apple Silicon Mac (M-series) running macOS 14 or later.
Free on-device cleanup needs macOS 26 with Apple Intelligence enabled.
EOF

echo "==> Building $DMG"
rm -f "$DMG"
hdiutil create \
  -volname "Matsu Flow" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG" > /dev/null

SIZE="$(du -h "$DMG" | cut -f1)"
echo "==> Done: $DMG ($SIZE)"
echo
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "    Next: ./scripts/notarize.sh \"$DMG\""
else
  echo "    !! This DMG is NOT notarized and NOT Developer ID signed."
  echo "       Gatekeeper will block it on every Mac except this one."
  echo "       See the Distribution section of the README."
fi
