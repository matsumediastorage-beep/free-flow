#!/bin/bash
# One command to rebuild, test, install and relaunch Free Flow, with everything
# written to build/update.log so the output can be read back afterwards.
#
#   ./scripts/update.sh            build, test, install, relaunch, measure launch
#   ./scripts/update.sh check      build + tests only (no install)
#
# Also snapshots Flow's own status files (launch timings, last cleanup result)
# into build/diagnostics/, since they live in ~/Library where other tools can't
# see them.

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
MODE="${1:-install}"
LOG="$ROOT/build/update.log"
DIAG="$ROOT/build/diagnostics"
SUPPORT="$HOME/Library/Application Support/Flow"
mkdir -p "$ROOT/build" "$DIAG"
: > "$LOG"

log() { echo "$@" | tee -a "$LOG"; }
run() { log "\$ $*"; "$@" 2>&1 | tee -a "$LOG"; return "${PIPESTATUS[0]}"; }

log "==> Free Flow update ($MODE) — $(date)"
log "    macOS $(sw_vers -productVersion) · $(uname -m) · $(swift --version 2>&1 | head -1)"

cp "$SUPPORT/status.json" "$DIAG/status-before.json" 2>/dev/null
cp "$SUPPORT/cleanup-status.json" "$DIAG/cleanup-status.json" 2>/dev/null
log "    cleanup engine setting: $(defaults read com.matsumedia.flow cleanupEngine 2>/dev/null || echo 'not set (default: onDevice)')"
log "    last cleanup: $(tr -d '\n' < "$SUPPORT/cleanup-status.json" 2>/dev/null || echo 'none recorded')"
log "    installed app: $(defaults read /Applications/Flow.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null)"

log ""
log "==> Compiling"
if ! run swift build -c release --product Flow; then
  log "!! BUILD FAILED"
  exit 1
fi

log ""
log "==> Tests"
if ! run swift run FlowTests --skip-permissions; then
  log "!! TESTS FAILED"
  exit 1
fi

if [[ "$MODE" == "check" ]]; then
  log "==> CHECK OK"
  exit 0
fi

log ""
log "==> Installing"
osascript -e 'quit app "Flow"' >/dev/null 2>&1
pkill -x Flow >/dev/null 2>&1
sleep 1
if ! run ./scripts/build-app.sh release --install; then
  log "!! INSTALL FAILED"
  exit 1
fi

log ""
log "==> Relaunching and timing startup"
rm -f "$SUPPORT/status.json"
open /Applications/Flow.app
for i in $(seq 1 40); do
  sleep 1
  if grep -q '"speechModelReady" : true' "$SUPPORT/status.json" 2>/dev/null; then
    log "    speech model ready after ~${i}s"
    break
  fi
done
cp "$SUPPORT/status.json" "$DIAG/status-after.json" 2>/dev/null
cat "$SUPPORT/status.json" >> "$LOG" 2>/dev/null
/usr/bin/log show --last 3m --predicate 'subsystem == "com.matsumedia.flow"' --style compact \
  > "$DIAG/flow.log" 2>/dev/null
log "==> DONE"
