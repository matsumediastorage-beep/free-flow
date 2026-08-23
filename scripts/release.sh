#!/bin/bash
# Cuts a release: builds, zips, tags, and publishes to GitHub.
#
#   ./scripts/release.sh 0.2.0
#
# A .zip rather than the .dmg, because `install.sh` fetches it with `gh` and
# `ditto` unpacks it without ever touching quarantine. The .dmg exists for
# anyone who would rather drag an icon, and is worth attaching too once the app
# is notarized.

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

VERSION="${1:-}"
[[ -n "$VERSION" ]] || { echo "usage: ./scripts/release.sh <version>" >&2; exit 2; }

REPO="${MATSU_FLOW_REPO:-matsumediastorage-beep/matsu-flow}"
BUNDLE="$ROOT/build/Flow.app"
ZIP="$ROOT/build/MatsuFlow-$VERSION.zip"

echo "==> Stamping version $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$ROOT/Resources/Info.plist"

echo "==> Building"
"$ROOT/scripts/build-app.sh" release

echo "==> Zipping"
rm -f "$ZIP"
# ditto -k preserves the bundle's signature and symlinks; `zip` does not.
ditto -c -k --keepParent "$BUNDLE" "$ZIP"

echo "==> Tagging"
git add -A
git commit -m "Release $VERSION" || echo "    (nothing to commit)"
git tag -f "v$VERSION"
git push origin HEAD --tags

echo "==> Publishing"
gh release create "v$VERSION" "$ZIP" \
  -R "$REPO" \
  --title "Matsu Flow $VERSION" \
  --notes "Install: \`gh repo clone $REPO -- --depth 1 && cd matsu-flow && ./install.sh\`" \
  || gh release upload "v$VERSION" "$ZIP" -R "$REPO" --clobber

echo "==> Done: $ZIP"
