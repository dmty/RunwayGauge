#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/scripts/helpers-bundle/Helpers"
# ponytail: explicit list beats glob — bundle must stay predictable for install + tests
RUNTIME=(
  install-statusline.sh uninstall-statusline.sh install-poller.sh statusline-wrapper.sh
  com.mirabilia.runwaygauge.claudeusage.plist
  lib/accounts.sh lib/claude-config.sh lib/helper-state.sh lib/paths.sh lib/runtime-env.sh lib/usage-commit.sh
)

[[ "${1:-}" == "--list" ]] && { printf '%s\n' "${RUNTIME[@]}" runwaygauge-helper; exit 0; }

rm -rf "$DEST" && mkdir -p "$DEST/lib"
for f in "${RUNTIME[@]}"; do cp "$ROOT/scripts/$f" "$DEST/$f"; done

( cd "$ROOT/Core" && swift build -c release --product RunwayGaugeHelper )
cp "$ROOT/Core/.build/release/RunwayGaugeHelper" "$DEST/runwaygauge-helper"

find "$DEST" -type f \( -name '*.sh' -o -name 'runwaygauge-helper' \) -exec chmod 755 {} +
find "$DEST/lib" -type f -exec chmod 644 {} +
chmod 644 "$DEST/com.mirabilia.runwaygauge.claudeusage.plist"
