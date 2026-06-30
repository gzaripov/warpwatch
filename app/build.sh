#!/usr/bin/env bash
#
# Build & sign WarpwatchBar.app from warpwatch-bar.swift.
# Override the signing identity with WARPWATCH_SIGN_ID; otherwise the first
# "Apple Development" / "Developer ID Application" identity is used, falling
# back to ad-hoc signing.
set -euo pipefail
cd "$(dirname "$0")"

APP="WarpwatchBar.app"

echo "compiling..."
swiftc -O warpwatch-bar.swift -o warpwatch-bar

echo "assembling ${APP}..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp warpwatch-bar "$APP/Contents/MacOS/warpwatch-bar"
cp Info.plist "$APP/Contents/Info.plist"

SIGN_ID="${WARPWATCH_SIGN_ID:-}"
if [ -z "$SIGN_ID" ]; then
  SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development|Developer ID Application/{print $2; exit}')"
fi
if [ -n "$SIGN_ID" ]; then
  echo "signing with: $SIGN_ID"
  codesign --force --options runtime --timestamp=none --sign "$SIGN_ID" "$APP"
else
  echo "signing ad-hoc"
  codesign --force --sign - "$APP"
fi
codesign --verify --verbose=1 "$APP"
echo "built & signed: $(pwd)/$APP"
