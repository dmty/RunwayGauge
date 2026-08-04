#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.mirabilia.macusagewidget.claudeusage"
TARGET="$HOME/Library/LaunchAgents/$LABEL.plist"

mkdir -p "$HOME/Library/LaunchAgents"
sed "s|__SCRIPT__|$DIR/poll-claude-usage.sh|" "$DIR/$LABEL.plist" > "$TARGET"

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$TARGET"
launchctl print "gui/$UID/$LABEL" | sed -n '1,12p'

echo "installed $TARGET"
echo "uninstall with: launchctl bootout gui/$UID/$LABEL && rm $TARGET"
