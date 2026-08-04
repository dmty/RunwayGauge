#!/bin/bash
set -euo pipefail
APP_PATH="${1:?app path}"
DMG_PATH="${2:?dmg path}"
[[ -d "$APP_PATH" ]] || { echo "missing app: $APP_PATH" >&2; exit 1; }
mkdir -p "$(dirname "$DMG_PATH")"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "RunwayGauge" -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH"
