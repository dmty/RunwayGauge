#!/bin/bash
# Developer ID sign, notarize, staple, install to /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Mirabilia Limited (KCPFNDZWCD)}"
TEAM="${DEVELOPMENT_TEAM:-KCPFNDZWCD}"
KEY_ID="${APPLE_API_KEY_ID:-FBU34339DN}"
ISSUER="${APPLE_API_ISSUER:-c0f9acc1-8dc5-4760-a347-e6c2e884ff1f}"
KEY_PATH="${APPLE_API_KEY_PATH:-$HOME/private_keys/AuthKey_${KEY_ID}.p8}"
DERIVED="$PWD/build"
mkdir -p "$DERIVED" && touch "$DERIVED/.metadata_never_index"
APP_NAME="RunwayGauge.app"

[[ -f "$KEY_PATH" ]] || { echo "missing API key: $KEY_PATH" >&2; exit 1; }

export CODESIGN_IDENTITY="$IDENTITY"
export DEVELOPMENT_TEAM="$TEAM"

./scripts/sync-helpers-bundle.sh
xcodegen generate
VER=$(tr -d '[:space:]' < version.txt)
BUILD=$(./scripts/semver-to-build.sh "$VER")
xcodebuild -project RunwayGauge.xcodeproj \
  -scheme RunwayGauge \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VER" \
  CURRENT_PROJECT_VERSION="$BUILD" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  build

APP="$DERIVED/Build/Products/Release/$APP_NAME"
[[ -d "$APP" ]] || { echo "missing app: $APP" >&2; exit 1; }

HELPER="$APP/Contents/Resources/Helpers/runwaygauge-helper"
WIDGET="$APP/Contents/PlugIns/UsageWidget.appex"
[[ -f "$HELPER" ]] || { echo "missing helper: $HELPER" >&2; exit 1; }
[[ -d "$WIDGET" ]] || { echo "missing widget: $WIDGET" >&2; exit 1; }

# Inside-out: helper, widget, app.
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$HELPER"
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  --entitlements Widget/UsageWidget.entitlements "$WIDGET"
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  --entitlements App/RunwayGauge.entitlements "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | sed -n '1,12p'
codesign -dv --verbose=2 "$WIDGET" 2>&1 | sed -n '1,8p'
codesign -dv --verbose=2 "$HELPER" 2>&1 | sed -n '1,8p'

ZIP="$DERIVED/RunwayGauge-notarize.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

xcrun notarytool submit "$ZIP" \
  --key "$KEY_PATH" \
  --key-id "$KEY_ID" \
  --issuer "$ISSUER" \
  --wait

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute -vv "$APP"

osascript -e 'quit app "RunwayGauge"' 2>/dev/null || true
rm -rf "/Applications/$APP_NAME"
cp -R "$APP" "/Applications/$APP_NAME"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$APP" 2>/dev/null || true

open "/Applications/$APP_NAME"
echo "installed notarized app: /Applications/$APP_NAME"
