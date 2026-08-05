#!/bin/bash
# Refreshes widget data when Claude Code has not done so recently.
#
# The OAuth access token exists only for the duration of one request. This
# script never logs or persists it, and never refreshes it: refreshing could
# invalidate Claude Code's own rotating refresh token.
set -uo pipefail

# shellcheck source=lib/runtime-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/runtime-env.sh"
# shellcheck source=scripts/lib/paths.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/paths.sh"
# shellcheck source=scripts/lib/accounts.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/accounts.sh"
# shellcheck source=scripts/lib/usage-commit.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/usage-commit.sh"

MAX_AGE=600
SECURITY_BIN="${POLLER_SECURITY_BIN:-security}"
CURL_BIN="${POLLER_CURL_BIN:-curl}"

mkdir -p "$USAGE_DIR" || exit 0

registry_snapshot=$(mktemp "$USAGE_DIR/.accounts.snapshot.XXXXXX") || exit 0
trap 'rm -f "$registry_snapshot"' EXIT
cp "$ACCOUNTS_FILE" "$registry_snapshot" 2>/dev/null || exit 0
account_registry_valid "$registry_snapshot" || exit 0

while IFS= read -r -d '' account_id &&
      IFS= read -r -d '' _label &&
      IFS= read -r -d '' _config_dir &&
      IFS= read -r -d '' keychain_service &&
      IFS= read -r -d '' keychain_account; do
  target="$(usage_file_for_account "$account_id")" || continue
  if [[ -f "$target" ]]; then
    age=$(( $(date +%s) - $(stat -f %m "$target") ))
    (( age < MAX_AGE )) && continue
  fi

  # Config-only accounts cannot be polled. Both selectors are mandatory:
  # accounts may share a service while holding different credentials.
  [[ -n "$keychain_service" && -n "$keychain_account" ]] || continue
  creds=$("$SECURITY_BIN" find-generic-password \
    -s "$keychain_service" -a "$keychain_account" -w 2>/dev/null) || continue
  token=$(printf '%s' "$creds" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
  unset creds
  [[ -n "$token" ]] || { unset token; continue; }

  observed_at=$(date +%s)
  body_file=$(mktemp "$USAGE_DIR/.poll-body-${account_id}.XXXXXX") || {
    unset token
    continue
  }

  # Feed the bearer header on stdin so the token never appears in argv.
  code=$("$CURL_BIN" -sS --max-time 15 -o "$body_file" -w '%{http_code}' -K - <<EOF
header = "Authorization: Bearer $token"
header = "Accept: application/json"
user-agent = "runway-gauge/1.0"
url = "https://api.anthropic.com/api/oauth/usage"
EOF
  )
  curl_status=$?
  unset token
  if ((curl_status != 0)) || [[ "$code" != "200" ]]; then
    rm -f "$body_file"
    continue
  fi

  candidate=$(mktemp "$USAGE_DIR/.usage-${account_id}.candidate.XXXXXX") || {
    rm -f "$body_file"
    continue
  }
  if ! jq -c --arg accountId "$account_id" --argjson observedAt "$observed_at" '
    def iso_epoch: select(type == "string")
      | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601;
    def window($id; $label):
      select(. != null)
      | {id: $id, label: $label,
         usedPercent: .utilization,
         resetsAt: (.resets_at | iso_epoch)};
    {
      schema: 1,
      accountId: $accountId,
      source: "claude-code",
      updatedAt: $observedAt,
      origin: "poll",
      windows: [
        (.five_hour | window("five_hour"; "Session")),
        (.seven_day | window("seven_day"; "Week"))
      ]
      | map(select(.usedPercent != null and .resetsAt != null))
    }
    | select(.windows | length > 0)
  ' "$body_file" > "$candidate"; then
    rm -f "$body_file" "$candidate"
    continue
  fi
  rm -f "$body_file"

  # Rejection means another writer won or the response was invalid. Preserve it.
  usage_commit "$target" "$candidate" 0 >/dev/null 2>&1 || true
done < <(account_enumerate_pinned_claude "$registry_snapshot")

exit 0
