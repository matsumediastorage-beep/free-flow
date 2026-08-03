#!/bin/bash
# Escape hatch for when macOS gets confused about Flow's permissions.
#
# Symptom: you granted Accessibility, the toggle is ON in System Settings, but
# the hotkey does nothing. This usually means TCC is holding a grant for an
# older build's code signature and silently ignoring the new one.
#
# This clears Flow's grants so you can re-grant them cleanly. It only touches
# this app's entries — nothing else on your Mac is affected.

set -euo pipefail

BUNDLE_ID="com.matsumedia.flow"

echo "==> Resetting permissions for $BUNDLE_ID"

for service in Accessibility ListenEvent Microphone; do
  if tccutil reset "$service" "$BUNDLE_ID" 2>/dev/null; then
    echo "    reset $service"
  else
    echo "    $service — nothing to reset"
  fi
done

echo
echo "==> Done. Now:"
echo "    1. Quit Flow if it's running"
echo "    2. Remove Flow from System Settings > Privacy & Security > Accessibility"
echo "       (select it, click the '−' button) — a stale entry blocks re-granting"
echo "    3. Relaunch Flow and grant again"
echo
echo "    If this keeps happening on every rebuild, you're on ad-hoc signing."
echo "    Fix it permanently with: ./scripts/make-signing-cert.sh"
