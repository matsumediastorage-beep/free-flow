#!/bin/bash
# Matsu Flow installer.
#
#   ./install.sh
#
# Downloads the latest release from the private repo and installs it to
# /Applications. Authentication goes through the GitHub CLI, so nobody has to
# paste a token anywhere.
#
# Why a Terminal installer rather than "download the DMG and double-click":
# macOS attaches a `com.apple.quarantine` flag to anything a browser downloads,
# and Gatekeeper refuses to open a quarantined app that Apple has not notarized.
# Matsu Flow is signed with a self-signed certificate, not an Apple Developer ID,
# so a browser download would be blocked. A file fetched by `gh` or `curl` never
# gets the quarantine flag in the first place, so the app opens normally.
#
# This removes no security check — it never acquires one. The tradeoff is real
# and worth saying plainly: you are trusting whoever published this repo rather
# than Apple's notarization. Fine for an internal team tool; for anything wider,
# notarize it properly (see scripts/notarize.sh).

set -euo pipefail

REPO="${MATSU_FLOW_REPO:-matsumediastorage-beep/matsu-flow}"
APP="/Applications/Flow.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say()  { printf '\033[1m==>\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31m!!\033[0m %s\n' "$1" >&2; exit 1; }

# --- Machine checks ---------------------------------------------------------

[[ "$(uname -s)" == "Darwin" ]] || fail "Matsu Flow is macOS only."

if [[ "$(uname -m)" != "arm64" ]]; then
  fail "Matsu Flow needs an Apple Silicon Mac (M-series). The speech model runs
   on the Neural Engine, and there is no Intel build."
fi

MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if (( MAJOR < 14 )); then
  fail "Matsu Flow needs macOS 14 or later. This Mac is on $(sw_vers -productVersion)."
fi

# --- GitHub access ----------------------------------------------------------

if ! command -v gh >/dev/null 2>&1; then
  fail "This needs the GitHub CLI, because the repo is private.

   Install it:      brew install gh
   Then sign in:    gh auth login
   Then re-run:     ./install.sh"
fi

if ! gh auth status >/dev/null 2>&1; then
  fail "You are not signed in to GitHub.

   Run:  gh auth login
   Then re-run this script."
fi

if ! gh repo view "$REPO" >/dev/null 2>&1; then
  fail "Your GitHub account cannot see $REPO.

   Ask Brandon to add you as a collaborator, then re-run this script."
fi

# --- Download ---------------------------------------------------------------

say "Downloading the latest release of $REPO"
gh release download -R "$REPO" -p '*.zip' -D "$TMP" --clobber \
  || fail "No release found. Has one been published yet?"

ARCHIVE="$(find "$TMP" -maxdepth 1 -name '*.zip' | head -1)"
[[ -n "$ARCHIVE" ]] || fail "The release had no .zip asset."

say "Unpacking $(basename "$ARCHIVE")"
ditto -x -k "$ARCHIVE" "$TMP/unpacked" || fail "Could not unpack the archive."

SOURCE="$(find "$TMP/unpacked" -maxdepth 2 -name "Flow.app" -type d | head -1)"
[[ -n "$SOURCE" ]] || fail "No Flow.app inside the archive."

# --- Install ----------------------------------------------------------------

if [[ -d "$APP" ]]; then
  say "Replacing the existing install"
  # Quit it first, or the copy lands on a running binary.
  osascript -e 'tell application "Flow" to quit' 2>/dev/null || true
  pkill -f "$APP/Contents/MacOS/Flow" 2>/dev/null || true
  sleep 1
  rm -rf "$APP"
fi

# /Applications must be the destination, not ~/Downloads: macOS keys the
# Accessibility and Input Monitoring grants to the app's path, so a copy that
# moves later silently loses its permissions.
say "Installing to $APP"
if ! cp -R "$SOURCE" "$APP" 2>/dev/null; then
  say "Needs an administrator password to write to /Applications"
  sudo cp -R "$SOURCE" "$APP" || fail "Install failed."
  sudo chown -R "$(id -u):$(id -g)" "$APP"
fi

say "Launching"
open "$APP"

cat <<'EOF'

  Installed.

  Flow will now ask for three permissions. macOS requires a human to grant
  each one — no app can do it for itself. The setup window links straight to
  the right page for each:

      Accessibility     pastes text into whatever app you are using
      Input Monitoring  notices when you hold the dictation key
      Microphone        hears you

  If you also have Wispr Flow installed, watch which "Flow" you tick.

  Then it downloads about 600MB of speech model, once. The menu bar shows
  progress. After that it works entirely offline.

  To use it: hold Left Shift for a moment, talk, release. The text appears
  at your cursor. Prefer another key? Dashboard > Settings > Dictation key.

EOF
