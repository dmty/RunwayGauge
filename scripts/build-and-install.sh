#!/bin/bash
# Regenerates the Xcode project, builds Release, installs to /Applications,
# and launches once so widgetd registers the extension.
set -euo pipefail

cd "$(dirname "$0")/.."
DERIVED="$PWD/build"
APP="MacUsageWidget.app"

xcodegen generate
xcodebuild -project MacUsageWidget.xcodeproj \
  -scheme MacUsageWidget \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  build

BUILT="$DERIVED/Build/Products/Release/$APP"
[[ -d "$BUILT" ]] || { echo "build produced no app at $BUILT" >&2; exit 1; }

# Replacing a running app confuses widgetd; quit it first.
osascript -e 'quit app "MacUsageWidget"' 2>/dev/null || true
rm -rf "/Applications/$APP"
cp -R "$BUILT" "/Applications/$APP"

codesign -dv --verbose=2 "/Applications/$APP" 2>&1 | sed -n '1,6p'
codesign -dv --verbose=2 "/Applications/$APP/Contents/PlugIns/UsageWidget.appex" 2>&1 | sed -n '1,6p'

open "/Applications/$APP"
echo "installed and launched: /Applications/$APP"
