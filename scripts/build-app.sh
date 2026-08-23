#!/bin/bash
# Builds Flow.app from the SwiftPM package.
#
# No Xcode required — this assembles the bundle by hand from the CLT toolchain.
#
#   ./scripts/build-app.sh          debug build into ./build
#   ./scripts/build-app.sh release  release build
#   ./scripts/build-app.sh release --install   also copy to /Applications
#
# TCC note: macOS ties Accessibility/Mic grants to the code signature AND the
# path on disk. Run ./scripts/make-signing-cert.sh once so rebuilds keep their
# permissions, and always run the app from the same path.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

CONFIG="${1:-debug}"
INSTALL=false
for arg in "$@"; do
  [[ "$arg" == "--install" ]] && INSTALL=true
done

APP_NAME="Flow"
BUNDLE="$ROOT/build/$APP_NAME.app"
IDENTITY_NAME="Matsu Flow Dev"

echo "==> Building ($CONFIG)"
# -gnone in release: SwiftPM emits DWARF debug info even for release builds,
# which is dead weight in a shipped binary. Debug builds keep it.
SWIFT_FLAGS=()
[[ "$CONFIG" == "release" ]] && SWIFT_FLAGS=(-Xswiftc -gnone)

swift build -c "$CONFIG" --product "$APP_NAME" "${SWIFT_FLAGS[@]}"
BIN_PATH="$(swift build -c "$CONFIG" --product "$APP_NAME" "${SWIFT_FLAGS[@]}" --show-bin-path)/$APP_NAME"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "!! Build produced no binary at $BIN_PATH" >&2
  exit 1
fi

echo "==> Assembling $APP_NAME.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$BUNDLE/Contents/MacOS/$APP_NAME"

# Strip the release binary — 8.6MB to 4.4MB, about half the app.
#
# Must happen BEFORE signing: strip rewrites the Mach-O and would otherwise
# invalidate the signature, which on this app means macOS forgetting every
# permission grant.
#
# The cost is that crash reports come back unsymbolicated. Keep the unstripped
# binary next to the bundle so a crash can still be read:
#   atos -o build/Flow.unstripped -arch arm64 -l <load address> <address>
if [[ "$CONFIG" == "release" ]]; then
  cp "$BIN_PATH" "$ROOT/build/$APP_NAME.unstripped"
  BEFORE="$(stat -f%z "$BUNDLE/Contents/MacOS/$APP_NAME")"
  strip -rSTx "$BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null
  AFTER="$(stat -f%z "$BUNDLE/Contents/MacOS/$APP_NAME")"
  echo "==> Stripped: $((BEFORE / 1024))K -> $((AFTER / 1024))K"
fi
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"

# Bundled resources (app icon, etc.) if any exist.
if compgen -G "$ROOT/Resources/*.icns" > /dev/null; then
  cp "$ROOT/Resources/"*.icns "$BUNDLE/Contents/Resources/"
fi

# SwiftPM emits resource bundles for dependencies that ship them; they must sit
# next to the executable or the app will fault at runtime looking for them.
BIN_DIR="$(dirname "$BIN_PATH")"
if compgen -G "$BIN_DIR/*.bundle" > /dev/null; then
  cp -R "$BIN_DIR/"*.bundle "$BUNDLE/Contents/Resources/"
fi

echo "==> Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY_NAME"; then
  echo "    using stable identity: $IDENTITY_NAME"
  codesign --force --deep --sign "$IDENTITY_NAME" "$BUNDLE"
else
  echo "    !! No '$IDENTITY_NAME' identity found — falling back to ad-hoc."
  echo "       Permissions will reset on EVERY rebuild."
  echo "       Fix once with: ./scripts/make-signing-cert.sh"
  codesign --force --deep --sign - "$BUNDLE"
fi

if $INSTALL; then
  echo "==> Installing to /Applications"
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$BUNDLE" "/Applications/$APP_NAME.app"
  echo "    /Applications/$APP_NAME.app"
fi

echo "==> Done: $BUNDLE"
