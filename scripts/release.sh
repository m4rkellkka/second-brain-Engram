#!/bin/bash
# Builds a universal Release Engram.app (Apple silicon and Intel), checks
# its ad-hoc signature, and packs it as a zip and a DMG with checksums in
# build/release/, plus the release notes from CHANGELOG.md.
# Usage: make release
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
VERSION=$(sed -n 's/^MARKETING_VERSION = //p' Config/Version.xcconfig)
[ -n "$VERSION" ] || { echo "No MARKETING_VERSION in Config/Version.xcconfig"; exit 1; }
OUT=$ROOT/build/release
DERIVED=$ROOT/build/ReleaseData
APP=$DERIVED/Build/Products/Release/Engram.app

rm -rf "$OUT" && mkdir -p "$OUT"
echo "→ Building Engram $VERSION (Release, universal)"
xcodebuild -project Engram.xcodeproj -scheme Engram -configuration Release \
  -derivedDataPath "$DERIVED" -destination 'generic/platform=macOS' \
  ONLY_ACTIVE_ARCH=NO -quiet build

# Xcode signs ad hoc ("-") with the hardened runtime; make sure it holds.
codesign --verify --deep --strict "$APP"
lipo -info "$APP/Contents/MacOS/Engram"

echo "→ Packing"
ditto -c -k --keepParent "$APP" "$OUT/Engram-$VERSION.zip"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Engram $VERSION" -srcfolder "$STAGE" -ov -format UDZO \
  "$OUT/Engram-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"
(cd "$OUT" && shasum -a 256 "Engram-$VERSION.zip" "Engram-$VERSION.dmg" >SHA256SUMS.txt)

# The release notes: this version's section of the changelog.
awk -v version="$VERSION" '
  $0 ~ "^## \\[" version "\\]" { keep = 1; next }
  keep && /^## \[/ { exit }
  keep { print }
' CHANGELOG.md >"$OUT/notes.md"
[ -s "$OUT/notes.md" ] || { echo "CHANGELOG.md has no section for $VERSION"; exit 1; }
cat >>"$OUT/notes.md" <<NOTES

### Install

1. Download \`Engram-$VERSION.dmg\` (or the zip) and drag **Engram** into Applications.
2. Engram isn't notarized, so the first time macOS blocks it. Either run
   \`xattr -dr com.apple.quarantine /Applications/Engram.app\` in Terminal, or open
   System Settings → Privacy & Security and click **Open Anyway**.
3. Open Engram, then Settings (⌘,) → **Connect to Claude Desktop**, and restart Claude Desktop.
NOTES

echo "→ Done: $OUT"
ls -lh "$OUT"
