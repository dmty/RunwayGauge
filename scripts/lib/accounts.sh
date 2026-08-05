#!/bin/bash
# Read-only helpers for validating and querying the account registry.

account_id_is_valid() {
  [[ "${1:-}" =~ ^acc_[A-Za-z0-9_-]{1,64}$ ]]
}

account_normalize_path() {
  local path="${1:-}" expanded component result prefix
  local -a parts stack

  [[ -n "$path" ]] || return 1
  # shellcheck disable=SC2088
  case "$path" in
    "~") expanded="$HOME" ;;
    "~/"*) expanded="$HOME/${path#\~/}" ;;
    *) expanded="$path" ;;
  esac

  if [[ -d "$expanded" ]]; then
    (cd -P "$expanded" 2>/dev/null && pwd -P)
    return
  fi

  prefix=""
  [[ "$expanded" == /* ]] && prefix="/"
  IFS='/' read -r -a parts <<< "$expanded"
  stack=()
  for component in "${parts[@]}"; do
    case "$component" in
      ""|".") ;;
      "..")
        if ((${#stack[@]} > 0)) && [[ "${stack[${#stack[@]}-1]}" != ".." ]]; then
          unset 'stack[${#stack[@]}-1]'
        elif [[ -z "$prefix" ]]; then
          stack+=("..")
        fi
        ;;
      *) stack+=("$component") ;;
    esac
  done

  result="$prefix"
  for component in "${stack[@]}"; do
    [[ -z "$result" || "$result" == "/" ]] || result+="/"
    result+="$component"
  done
  [[ -n "$result" ]] || result="."
  printf '%s\n' "$result"
}

account_registry_valid() {
  local registry="${1:-}" id account config normalized paths=$'\n'

  [[ -f "$registry" ]] || return 1
  jq -e '
    type == "object"
    and .schema == 1
    and (.revision | type == "number")
    and (.prefs | type == "object")
    and (.prefs.rotateIntervalSec | type == "number" and . >= 300 and . <= 86400)
    and ((.prefs.selectedAccountId == null) or (.prefs.selectedAccountId | type == "string"))
    and (.accounts | type == "array")
    and all(.accounts[];
      type == "object"
      and (.id | type == "string")
      # Swift limits labels by user-perceived characters. jq length uses a
      # different counting model, so shell validates only trimmed non-emptiness.
      and (.label | type == "string" and test("\\S"))
      and (.sourceKind | type == "string")
      and (.pinned | type == "boolean")
      and (.credentials | type == "object")
      and ((.credentials.configDir == null) or
           (.credentials.configDir | type == "string" and length > 0))
      and ((.credentials.keychain == null) or
           ((.credentials.keychain | type == "object")
            and (.credentials.keychain.service | type == "string" and length > 0)
            and ((.credentials.keychain.account == null) or
                 (.credentials.keychain.account | type == "string"))))
    )
  ' "$registry" >/dev/null 2>&1 || return 1
  jq -e '[.accounts[].id] | length == (unique | length)' "$registry" >/dev/null 2>&1 || return 1
  jq -e '
    [.accounts[]
      | select(.sourceKind == "claude-oauth" and .credentials.keychain != null)
      | [
          (.credentials.keychain.service | gsub("^\\s+|\\s+$"; "")),
          (.credentials.keychain.account
            | if . == null then null else gsub("^\\s+|\\s+$"; "") end)
        ]
      | @json
    ]
    | length == (unique | length)
  ' "$registry" >/dev/null 2>&1 || return 1

  while IFS= read -r id; do
    account_id_is_valid "$id" || return 1
  done < <(jq -r '.accounts[].id' "$registry")

  while IFS= read -r account; do
    [[ "$(printf '%s' "$account" | jq -r '.sourceKind')" == "claude-oauth" ]] || continue
    config="$(printf '%s' "$account" | jq -r '.credentials.configDir // empty')"
    [[ -n "$config" ]] || continue
    normalized="$(account_normalize_path "$config")" || return 1
    [[ "$paths" != *$'\n'"$normalized"$'\n'* ]] || return 1
    paths+="$normalized"$'\n'
  done < <(jq -c '.accounts[]' "$registry")

  id="$(jq -r '.prefs.selectedAccountId // empty' "$registry")" || return 1
  if [[ -n "$id" ]]; then
    account_id_is_valid "$id" || return 1
    jq -e --arg id "$id" 'any(.accounts[]; .id == $id and .pinned == true)' \
      "$registry" >/dev/null 2>&1 || return 1
  fi
}

account_resolve_claude() {
  local registry="${1:-}" requested="${2:-}" normalized account config match="" count=0

  ACCOUNT_ID=""
  ACCOUNT_LABEL=""
  ACCOUNT_CONFIG_DIR=""
  ACCOUNT_KEYCHAIN_SERVICE=""
  ACCOUNT_KEYCHAIN_ACCOUNT=""

  account_registry_valid "$registry" || return 1
  normalized="$(account_normalize_path "$requested")" || return 1

  while IFS= read -r account; do
    config="$(printf '%s' "$account" | jq -r '.credentials.configDir // empty')"
    [[ -n "$config" ]] || continue
    [[ "$(account_normalize_path "$config")" == "$normalized" ]] || continue
    match="$account"
    count=$((count + 1))
    (( count > 1 )) && return 1
  done < <(jq -c '.accounts[] | select(.sourceKind == "claude-oauth")' "$registry")

  [[ $count -eq 1 ]] || return 1
  ACCOUNT_ID="$(printf '%s' "$match" | jq -r '.id')"
  account_id_is_valid "$ACCOUNT_ID" || return 1
  # shellcheck disable=SC2034
  ACCOUNT_LABEL="$(printf '%s' "$match" | jq -r '.label')"
  # shellcheck disable=SC2034
  ACCOUNT_CONFIG_DIR="$normalized"
  # shellcheck disable=SC2034
  ACCOUNT_KEYCHAIN_SERVICE="$(printf '%s' "$match" | jq -r '.credentials.keychain.service // empty')"
  # shellcheck disable=SC2034
  ACCOUNT_KEYCHAIN_ACCOUNT="$(printf '%s' "$match" | jq -r '.credentials.keychain.account // empty')"
}

account_enumerate_pinned_claude() {
  local registry="${1:-}" selected account id config service keychain_account

  account_registry_valid "$registry" || return 1
  selected="$(jq -r '.prefs.selectedAccountId // empty' "$registry")"

  while IFS= read -r account; do
    id="$(printf '%s' "$account" | jq -r '.id')"
    config="$(printf '%s' "$account" | jq -r '.credentials.configDir // empty')"
    [[ -z "$config" ]] || config="$(account_normalize_path "$config")"
    service="$(printf '%s' "$account" | jq -r '.credentials.keychain.service // empty')"
    keychain_account="$(printf '%s' "$account" | jq -r '.credentials.keychain.account // empty')"
    printf '%s\0%s\0%s\0%s\0%s\0' \
      "$id" "$(printf '%s' "$account" | jq -r '.label')" \
      "$config" "$service" "$keychain_account"
  done < <(jq -c --arg sel "$selected" '
    [.accounts[] | select(.pinned == true and .sourceKind == "claude-oauth")]
    | sort_by(.id != $sel)[]
  ' "$registry")
}
