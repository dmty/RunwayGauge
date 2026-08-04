#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/scripts/helpers-bundle/Helpers"
rm -rf "$DEST"
mkdir -p "$DEST/lib"
FILES=(
  install-statusline.sh uninstall-statusline.sh install-poller.sh
  statusline-wrapper.sh write-claude-usage.sh poll-claude-usage.sh
)
for f in "${FILES[@]}"; do
  cp "$ROOT/scripts/$f" "$DEST/$f"
  chmod 755 "$DEST/$f"
done
cp "$ROOT/scripts/com.mirabilia.runwaygauge.claudeusage.plist" "$DEST/"
chmod 644 "$DEST/com.mirabilia.runwaygauge.claudeusage.plist"
for f in claude-config.sh paths.sh runtime-env.sh; do
  cp "$ROOT/scripts/lib/$f" "$DEST/lib/$f"
  chmod 644 "$DEST/lib/$f"
done
