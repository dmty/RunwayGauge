#!/bin/bash
# Locked, atomic, write-if-newer commit for one account usage record.

_usage_commit_locked() {
  local target="${1:-}" candidate="${2:-}" min_interval="${3:-0}"
  local account_id candidate_time existing_time age now modified_at

  [[ -f "$candidate" ]] || return 1
  [[ "$(dirname "$candidate")" == "$(dirname "$target")" ]] || return 1

  jq -e '
    type == "object"
    and .schema == 1
    and (.accountId | type == "string" and test("^acc_[A-Za-z0-9_-]{1,64}$"))
    and (.updatedAt | type == "number")
    and (.windows | type == "array")
  ' "$candidate" >/dev/null 2>&1 || return 1

  account_id="$(jq -r '.accountId' "$candidate")"
  [[ "$(basename "$target")" == "usage-$account_id.json" ]] || return 1
  candidate_time="$(jq -r '.updatedAt' "$candidate")"

  if [[ -f "$target" ]]; then
    existing_time="$(jq -r '.updatedAt' "$target")" || return 1
    jq -e --arg id "$account_id" --argjson candidate "$candidate_time" --argjson existing "$existing_time" '
      type == "object"
      and .schema == 1
      and .accountId == $id
      and (.updatedAt | type == "number")
      and (.windows | type == "array")
      and ($candidate > $existing)
    ' "$target" >/dev/null 2>&1 || return 1

    if jq -e '.windows | length == 0' "$candidate" >/dev/null &&
       jq -e '.windows | length > 0' "$target" >/dev/null; then
      return 1
    fi

    if [[ "$min_interval" =~ ^[0-9]+$ ]] && ((min_interval > 0)); then
      now="$(date +%s)"
      modified_at="$(stat -f %m "$target")"
      age=$((now - modified_at))
      if ((age < min_interval)) &&
         jq -en --argjson modified "$modified_at" --argjson candidate "$candidate_time" \
           '$modified < $candidate' >/dev/null; then
        return 1
      fi
    fi
  fi

  mv -f "$candidate" "$target"
}

usage_commit() {
  local target="${1:-}" candidate="${2:-}" min_interval="${3:-0}"
  local lock="${target}.lock" script="${BASH_SOURCE[0]}" status

  mkdir -p "$(dirname "$target")" || return 1
  /usr/bin/lockf -k "$lock" /bin/bash "$script" --locked "$target" "$candidate" "$min_interval"
  status=$?
  rm -f "$candidate"
  return "$status"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  [[ "${1:-}" == "--locked" ]] || exit 2
  shift
  _usage_commit_locked "$@"
  exit $?
fi
