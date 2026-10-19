#!/usr/bin/env bash
# Package dist/Spindle.app as a disk image with the usual drag-to-install layout.
#
#   VERSION=1.2.3   used in the file name (default: read from the bundle)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/Spindle.app"

[[ -d "$APP" ]] || { echo "error: $APP not found — run 'make app' first" >&2; exit 1; }

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
VERSION="${VERSION#v}"
DMG="$ROOT/dist/Spindle-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create \
  -volname "Spindle $VERSION" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -quiet \
  "$DMG"

echo "built $DMG"
