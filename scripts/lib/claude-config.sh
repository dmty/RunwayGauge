# shellcheck shell=bash
# Claude Code config-directory helpers. Registry data is the only source of
# desired directories; no alternate-client path is assumed here.
# shellcheck disable=SC2034 # sourced by install-statusline.sh
LEGACY_SETTINGS_BACKUP_SUFFIX=".bak-usagewidget"

claude_config_dirs() {
  local registry="${1:-}" raw normalized seen=$'\n'

  [[ -e "$registry" ]] || return 0
  account_registry_valid "$registry" || return 1

  while IFS= read -r -d '' raw; do
    normalized="$(account_normalize_path "$raw")" || return 1
    [[ "$seen" == *$'\n'"$normalized"$'\n'* ]] && continue
    seen+="$normalized"$'\n'
    printf '%s\0' "$normalized"
  done < <(jq -j '
    .accounts[]
    | select(.sourceKind == "claude-oauth")
    | .credentials.configDir // empty
    | select(length > 0)
    | ., "\u0000"
  ' "$registry")
}

claude_statusline_command() {
  local settings="${1:-}"
  jq -r '.statusLine.command // ""' "$settings"
}

claude_write_statusline() {
  local settings="${1:-}" statusline_json="${2:-}" tmp mode
  [[ -f "$settings" ]] || return 1
  jq -e 'type == "object" or type == "null"' <<< "$statusline_json" >/dev/null 2>&1 ||
    return 1

  tmp=$(mktemp "$(dirname "$settings")/.settings.XXXXXX") || return 1
  if ! jq --argjson statusLine "$statusline_json" \
      'if $statusLine == null then del(.statusLine) else .statusLine = $statusLine end' \
      "$settings" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mode="$(stat -f %Lp "$settings")" || { rm -f "$tmp"; return 1; }
  chmod "$mode" "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$settings"
}
