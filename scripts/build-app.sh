#!/usr/bin/env bash
# Builds build/mtts.app with SwiftPM. The Xcode Command Line Tools are enough.
#
#   scripts/build-app.sh            # release build, ad-hoc signed
#   CONFIG=debug scripts/build-app.sh
#   SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" scripts/build-app.sh
#
# Ad-hoc signing ("-") works, but macOS treats every rebuild as a new app and asks for
# Motion permission again. A real signing identity keeps the grant across rebuilds.
set -euo pipefail

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/mtts.app"

cd "$ROOT"
swift build -c "$CONFIG" --product mtts
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/mtts" "$APP/Contents/MacOS/mtts"
cp "$ROOT/mtts/Info.plist" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP"

echo "Built $APP"
echo "Run it with: open \"$APP\""
