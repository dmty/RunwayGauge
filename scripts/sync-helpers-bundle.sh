#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/scripts/helpers-bundle/Helpers"

RUNTIME_HELPERS=(
  install-statusline.sh
  uninstall-statusline.sh
  install-poller.sh
  statusline-wrapper.sh
  write-claude-usage.sh
  poll-claude-usage.sh
  com.mirabilia.runwaygauge.claudeusage.plist
  lib/accounts.sh
  lib/claude-config.sh
  lib/helper-state.sh
  lib/paths.sh
  lib/runtime-env.sh
  lib/usage-commit.sh
)

if [[ "${1:-}" == "--list" ]]; then
  printf '%s\n' "${RUNTIME_HELPERS[@]}"
  exit 0
fi

rm -rf "$DEST"
mkdir -p "$DEST/lib"
for relative in "${RUNTIME_HELPERS[@]}"; do
  cp "$ROOT/scripts/$relative" "$DEST/$relative"
  case "$relative" in
    lib/*|*.plist) chmod 644 "$DEST/$relative" ;;
    *) chmod 755 "$DEST/$relative" ;;
  esac
done
