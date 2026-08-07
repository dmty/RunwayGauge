#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DERIVED="$PWD/build"
APP_NAME="RunwayGauge.app"
VER=$(tr -d '[:space:]' < version.txt)
BUILD=$(./scripts/semver-to-build.sh "$VER")

./scripts/sync-helpers-bundle.sh
xcodegen generate
xcodebuild -project RunwayGauge.xcodeproj \
  -scheme RunwayGauge \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VER" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  build

BUILT="$DERIVED/Build/Products/Release/$APP_NAME"
[[ -d "$BUILT" ]] || { echo "missing app: $BUILT" >&2; exit 1; }
[[ -x "$BUILT/Contents/Resources/Helpers/install-statusline.sh" ]] || {
  echo "bundled Helpers resource is missing" >&2
  exit 1
}
[[ -x "$BUILT/Contents/Resources/Helpers/runwaygauge-helper" ]] || {
  echo "bundled runwaygauge-helper binary is missing" >&2
  exit 1
}
[[ -f "$BUILT/Contents/Resources/install-helpers-from-bundle.sh" ]] || {
  echo "helper bootstrap resource is missing" >&2
  exit 1
}

for plist in \
  "$BUILT/Contents/Info.plist" \
  "$BUILT/Contents/PlugIns/UsageWidget.appex/Contents/Info.plist"; do
  actual_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
  actual_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
  [[ "$actual_version" == "$VER" && "$actual_build" == "$BUILD" ]] || {
    echo "built version mismatch in $plist: expected $VER ($BUILD), got $actual_version ($actual_build)" >&2
    exit 1
  }
done
echo "$BUILT"
