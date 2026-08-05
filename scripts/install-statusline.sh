#!/bin/bash
# Wires the widget's statusline writer into each Claude Code config directory,
# preserving whatever statusline command is already configured.
set -euo pipefail

# shellcheck source=lib/runtime-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/runtime-env.sh"

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/paths.sh
source "$SCRIPTS_DIR/lib/paths.sh"
# shellcheck source=lib/accounts.sh
source "$SCRIPTS_DIR/lib/accounts.sh"
# shellcheck source=lib/claude-config.sh
source "$SCRIPTS_DIR/lib/claude-config.sh"
# shellcheck source=lib/helper-state.sh
source "$SCRIPTS_DIR/lib/helper-state.sh"

WRAPPER="$SCRIPTS_DIR/statusline-wrapper.sh"
[[ -x "$WRAPPER" ]] || { echo "wrapper not executable: $WRAPPER" >&2; exit 1; }
helper_state_init || { echo "invalid helper ownership manifest" >&2; exit 1; }

desired=()
if [[ -e "$ACCOUNTS_FILE" ]]; then
  registry_snapshot=$(mktemp "$(dirname "$ACCOUNTS_FILE")/.accounts.install.XXXXXX")
  trap 'rm -f "${registry_snapshot:-}"' EXIT
  cp "$ACCOUNTS_FILE" "$registry_snapshot"
  account_registry_valid "$registry_snapshot" || {
    echo "invalid account registry; helper ownership unchanged" >&2
    exit 1
  }
  while IFS= read -r -d '' dir; do
    desired+=("$dir")
  done < <(claude_config_dirs "$registry_snapshot")
fi
desired_count=${#desired[@]}

is_desired() {
  local candidate="$1" item i
  for ((i = 0; i < desired_count; i++)); do
    item="${desired[$i]}"
    [[ "$item" == "$candidate" ]] && return 0
  done
  return 1
}

restore_entry() {
  local entry="$1" dir settings installed previous current
  dir="$(printf '%s' "$entry" | jq -r '.configDir')"
  settings="$(printf '%s' "$entry" | jq -r '.settingsPath')"
  installed="$(printf '%s' "$entry" | jq -r '.installedCommand')"
  previous="$(printf '%s' "$entry" | jq -c '.previousStatusLine')"

  if [[ ! -f "$settings" ]]; then
    echo "manual cleanup: $settings is missing"
  else
    current="$(claude_statusline_command "$settings")"
    if [[ "$current" == "$installed" ]]; then
      claude_write_statusline "$settings" "$previous" || return 1
      echo "restored $dir"
    else
      echo "manual cleanup: preserved user-edited statusline in $dir"
    fi
  fi
  helper_state_remove "$dir"
}

# Reconcile entries no longer represented by the registry before installing new
# ones. A deleted registry intentionally means an empty desired set.
while IFS= read -r -d '' entry; do
  entry_dir="$(printf '%s' "$entry" | jq -r '.configDir')"
  is_desired "$entry_dir" && continue
  restore_entry "$entry" || { echo "failed to reconcile $entry_dir" >&2; exit 1; }
done < <(helper_state_entries)

for ((desired_index = 0; desired_index < desired_count; desired_index++)); do
  dir="${desired[$desired_index]}"
  settings="$dir/settings.json"
  [[ -f "$settings" ]] || { echo "skip $dir (no settings.json)"; continue; }

  entry="$(helper_state_entry "$dir")"
  if [[ -n "$entry" ]]; then
    installed="$(printf '%s' "$entry" | jq -r '.installedCommand')"
    previous_command="$(printf '%s' "$entry" | jq -r '.previousStatusLine.command // ""')"
    current="$(claude_statusline_command "$settings")"
    if [[ "$current" == "$installed" ]]; then
      echo "skip $dir (already installed)"
    elif [[ "$current" == "$previous_command" ]]; then
      statusline="$(jq -cn --arg command "$installed" \
        '{type:"command",command:$command}')"
      claude_write_statusline "$settings" "$statusline" || {
        echo "failed to recover interrupted install in $dir" >&2
        exit 1
      }
      echo "recovered interrupted install in $dir"
    else
      echo "manual cleanup: preserved user-edited statusline in $dir"
    fi
    continue
  fi

  current="$(claude_statusline_command "$settings")"
  previous="$(jq -c '.statusLine // null' "$settings")"
  if [[ "$current" == *"statusline-wrapper.sh"* ]]; then
    legacy_backup="$settings$LEGACY_SETTINGS_BACKUP_SUFFIX"
    legacy_recovered=0
    if [[ -f "$legacy_backup" ]] &&
       jq -e '
         type == "object"
         and ((.statusLine == null) or (.statusLine.command | type == "string"))
       ' "$legacy_backup" >/dev/null 2>&1; then
      legacy_command="$(claude_statusline_command "$legacy_backup")"
      if [[ "$legacy_command" != *"statusline-wrapper.sh"* ]]; then
        previous="$(jq -c '.statusLine // null' "$legacy_backup")"
        current="$legacy_command"
        legacy_recovered=1
      fi
    fi
    if ((legacy_recovered == 0)); then
      previous="null"
      current=""
    fi
    echo "upgrading unowned legacy wrapper in $dir"
  fi
  new_command="bash $(printf '%q' "$WRAPPER") $(printf '%q' "$current")"
  statusline="$(jq -cn --arg command "$new_command" \
    '{type:"command",command:$command}')"
  entry="$(jq -cn \
    --arg dir "$dir" \
    --arg settings "$settings" \
    --arg command "$new_command" \
    --argjson previous "$previous" \
    --argjson installedAt "$(date +%s)" '
      {
        configDir:$dir,
        settingsPath:$settings,
        installedCommand:$command,
        previousStatusLine:$previous,
        installedAt:$installedAt,
        owner:"RunwayGauge"
      }
    ')"

  # Record ownership first so interruption cannot leave an untracked wrapper.
  helper_state_add "$entry" || exit 1
  if ! claude_write_statusline "$settings" "$statusline"; then
    helper_state_remove "$dir" || true
    echo "failed to install in $dir" >&2
    exit 1
  fi
  echo "installed in $dir"
  echo "  was: $current"
  echo "  now: $new_command"
done
