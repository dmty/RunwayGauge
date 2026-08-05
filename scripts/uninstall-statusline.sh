#!/bin/bash
# Restores manifest-owned statusline commands, even if their accounts are gone.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/accounts.sh
source "$SCRIPTS_DIR/lib/accounts.sh"
# shellcheck source=lib/claude-config.sh
source "$SCRIPTS_DIR/lib/claude-config.sh"
# shellcheck source=lib/helper-state.sh
source "$SCRIPTS_DIR/lib/helper-state.sh"

helper_state_init || { echo "invalid helper ownership manifest" >&2; exit 1; }

while IFS= read -r -d '' entry; do
  dir="$(printf '%s' "$entry" | jq -r '.configDir')"
  settings="$(printf '%s' "$entry" | jq -r '.settingsPath')"
  installed="$(printf '%s' "$entry" | jq -r '.installedCommand')"
  previous="$(printf '%s' "$entry" | jq -c '.previousStatusLine')"

  if [[ ! -f "$settings" ]]; then
    echo "manual cleanup: $settings is missing"
  else
    current="$(claude_statusline_command "$settings")"
    if [[ "$current" == "$installed" ]]; then
      claude_write_statusline "$settings" "$previous"
      echo "restored $settings"
    else
      echo "manual cleanup: preserved user-edited statusline in $dir"
    fi
  fi
  helper_state_remove "$dir"
done < <(helper_state_entries)
