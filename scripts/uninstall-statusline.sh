#!/bin/bash
# Restores the statusline command that was in place before install-statusline.sh.
set -euo pipefail

# shellcheck source=lib/claude-config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/claude-config.sh"

for dir in "${CLAUDE_CONFIG_DIRS[@]}"; do
  backup="$dir/settings.json$SETTINGS_BACKUP_SUFFIX"
  if [[ -f "$backup" ]]; then
    mv "$backup" "$dir/settings.json"
    echo "restored $dir/settings.json"
  else
    echo "skip $dir (no backup)"
  fi
done
