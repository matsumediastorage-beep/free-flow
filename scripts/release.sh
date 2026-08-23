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

REPO="${FREE_FLOW_REPO:-matsumediastorage-beep/free-flow}"
BUNDLE="$ROOT/build/Flow.app"
ZIP="$ROOT/build/FreeFlow-$VERSION.zip"

echo "==> Stamping version $VERSION"
# sed, not PlistBuddy. PlistBuddy rewrites the entire file — it strips the
# comments and alphabetises the keys — so a version bump would silently delete
# the notes explaining why LSUIElement is absent. This touches one line.
/usr/bin/sed -i '' -E \
  "/<key>CFBundleShortVersionString<\/key>/{n;s|<string>[^<]*</string>|<string>$VERSION</string>|;}" \
  "$ROOT/Resources/Info.plist"

ACTUAL="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
[[ "$ACTUAL" == "$VERSION" ]] || { echo "!! Version stamp failed (got '$ACTUAL')" >&2; exit 1; }

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
git push origin HEAD
# --force so re-cutting the same version (a bad build, a last-minute fix)
# moves the tag instead of failing. `--tags` alone never overwrites.
git push origin --force "refs/tags/v$VERSION"

echo "==> Publishing"
gh release create "v$VERSION" "$ZIP" \
  -R "$REPO" \
  --title "Free Flow $VERSION" \
  --notes "Install: \`gh repo clone $REPO -- --depth 1 && cd free-flow && ./install.sh\`" \
  || gh release upload "v$VERSION" "$ZIP" -R "$REPO" --clobber

echo "==> Done: $ZIP"
