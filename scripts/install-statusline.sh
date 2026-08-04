#!/bin/bash
# Wires the widget's statusline writer into each Claude Code config directory,
# preserving whatever statusline command is already configured.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/claude-config.sh
source "$SCRIPTS_DIR/lib/claude-config.sh"

WRAPPER="$SCRIPTS_DIR/statusline-wrapper.sh"
[[ -x "$WRAPPER" ]] || { echo "wrapper not executable: $WRAPPER" >&2; exit 1; }

for dir in "${CLAUDE_CONFIG_DIRS[@]}"; do
  settings="$dir/settings.json"
  [[ -f "$settings" ]] || { echo "skip $dir (no settings.json)"; continue; }

  current=$(jq -r '.statusLine.command // ""' "$settings")

  if [[ "$current" == *"statusline-wrapper.sh"* ]]; then
    echo "skip $dir (already installed)"
    continue
  fi

  cp "$settings" "$settings$SETTINGS_BACKUP_SUFFIX"

  new_command="bash \"$WRAPPER\" $(printf '%q' "$current")"
  tmp=$(mktemp)
  jq --arg cmd "$new_command" \
     '.statusLine = {type: "command", command: $cmd}' "$settings" > "$tmp"
  mv "$tmp" "$settings"

  echo "installed in $dir"
  echo "  was: $current"
  echo "  now: $new_command"
done
