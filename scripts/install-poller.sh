#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.mirabilia.runwaygauge.claudeusage"
TARGET="$HOME/Library/LaunchAgents/$LABEL.plist"
HELPER="$DIR/runwaygauge-helper"

[[ -x "$HELPER" ]] || {
  echo "missing helper binary: $HELPER" >&2
  exit 1
}

mkdir -p "$HOME/Library/LaunchAgents"
sed "s|__HELPER__|$HELPER|" "$DIR/$LABEL.plist" > "$TARGET"

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$TARGET"
launchctl print "gui/$UID/$LABEL" | sed -n '1,12p'

echo "installed $TARGET"
echo "uninstall with: launchctl bootout gui/$UID/$LABEL && rm $TARGET"
