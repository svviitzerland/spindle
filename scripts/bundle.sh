#!/usr/bin/env bash
# Assemble a runnable Spindle.app around the SwiftPM binary.
#
# macOS will not grant Apple Events permission to a bare executable, and a
# desktop-level window needs a real bundle identity, so even `make run` goes
# through here.
#
#   CONFIG=release|debug   which SwiftPM build to bundle (default: release)
#   VERSION=1.2.3          stamped into the Info.plist (default: leave as-is)
#   SIGN_IDENTITY=...      a Developer ID; unset means an ad-hoc signature
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP="$ROOT/dist/Spindle.app"

# A universal build (`swift build --arch arm64 --arch x86_64`) lands somewhere
# else entirely, so look there first.
CONFIG_CAP="$(tr '[:lower:]' '[:upper:]' <<< "${CONFIG:0:1}")${CONFIG:1}"
for candidate in \
  "$ROOT/.build/apple/Products/$CONFIG_CAP/spindle" \
  "$ROOT/.build/$CONFIG/spindle"
do
  if [[ -x "$candidate" ]]; then BIN="$candidate"; break; fi
done

if [[ -z "${BIN:-}" ]]; then
  echo "error: no spindle binary found — run 'swift build -c $CONFIG' first" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/spindle"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -n "${VERSION:-}" ]]; then
  # Strip a leading v so the tag v1.2.3 and the version 1.2.3 agree.
  SHORT="${VERSION#v}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-$SHORT}" "$APP/Contents/Info.plist"
fi

# The icon is drawn by the app itself, so the repo carries no binary assets.
if "$APP/Contents/MacOS/spindle" icon --out "$ROOT/dist/icon" >/dev/null 2>&1; then
  cp "$ROOT/dist/icon.icns" "$APP/Contents/Resources/Spindle.icns"
else
  echo "warning: could not generate the app icon; bundling without one" >&2
fi

# An ad-hoc signature is enough for local use and for the Apple Events prompt
# to remember its answer. Releases pass a Developer ID so Gatekeeper is happy.
IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --timestamp --options runtime \
  --entitlements "$ROOT/Resources/Spindle.entitlements" \
  --sign "$IDENTITY" "$APP"

codesign --verify --strict "$APP"
echo "built $APP ($(lipo -archs "$APP/Contents/MacOS/spindle" 2>/dev/null || echo unknown), signed as ${IDENTITY})"
