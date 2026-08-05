#!/bin/bash
# Atomic ownership manifest for statusline helpers installed by RunwayGauge.

_HELPER_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER_STATE_FILE="${HELPER_STATE_FILE_OVERRIDE:-$(dirname "$_HELPER_SCRIPTS_DIR")/helper-installations.json}"

helper_state_valid() {
  [[ -f "$HELPER_STATE_FILE" ]] &&
    jq -e '
      type == "object"
      and .schema == 1
      and (.entries | type == "array")
      and all(.entries[];
        (.configDir | type == "string" and length > 0)
        and (.settingsPath | type == "string" and length > 0)
        and (.installedCommand | type == "string" and length > 0)
        and has("previousStatusLine")
        and .owner == "RunwayGauge")
      and ([.entries[].configDir] | length == (unique | length))
    ' "$HELPER_STATE_FILE" >/dev/null 2>&1
}

helper_state_save() {
  local json="${1:-}" dir tmp
  dir="$(dirname "$HELPER_STATE_FILE")"
  mkdir -p "$dir" || return 1
  tmp=$(mktemp "$dir/.helper-installations.XXXXXX") || return 1
  if ! printf '%s\n' "$json" | jq -c . > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$HELPER_STATE_FILE"
}

helper_state_init() {
  if [[ -e "$HELPER_STATE_FILE" ]]; then
    helper_state_valid
    return
  fi
  helper_state_save '{"schema":1,"entries":[]}'
}

helper_state_entry() {
  local config_dir="${1:-}"
  jq -c --arg dir "$config_dir" \
    '.entries[] | select(.configDir == $dir)' "$HELPER_STATE_FILE"
}

helper_state_add() {
  local entry="${1:-}" updated
  updated=$(jq -c --argjson entry "$entry" '
    .entries = ([.entries[] | select(.configDir != $entry.configDir)] + [$entry])
  ' "$HELPER_STATE_FILE") || return 1
  helper_state_save "$updated"
}

helper_state_remove() {
  local config_dir="${1:-}" updated
  updated=$(jq -c --arg dir "$config_dir" \
    '.entries = [.entries[] | select(.configDir != $dir)]' \
    "$HELPER_STATE_FILE") || return 1
  helper_state_save "$updated"
}

helper_state_entries() {
  jq -j '.entries[] | @json, "\u0000"' "$HELPER_STATE_FILE"
}
