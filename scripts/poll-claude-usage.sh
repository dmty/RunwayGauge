#!/bin/bash
# Refreshes widget data when Claude Code has not done so recently.
#
# The OAuth access token exists only for the duration of one request. This
# script never logs or persists it, and never refreshes it: refreshing could
# invalidate Claude Code's own rotating refresh token.
set -uo pipefail

# shellcheck source=scripts/lib/paths.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/paths.sh"

MAX_AGE=600

mkdir -p "$USAGE_DIR" || exit 0

if [[ -f "$USAGE_FILE" ]]; then
  age=$(( $(date +%s) - $(stat -f %m "$USAGE_FILE") ))
  (( age < MAX_AGE )) && exit 0
fi

if [[ -n "${POLLER_FIXTURE:-}" ]]; then
  body=$(<"$POLLER_FIXTURE")
else
  creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) || exit 0
  token=$(printf '%s' "$creds" | jq -r '.claudeAiOauth.accessToken // empty')
  unset creds
  [[ -z "$token" ]] && exit 0

  response=$(curl -sS --max-time 15 -w '\n%{http_code}' \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/json" \
    -H "User-Agent: mac-usage-widget/1.0" \
    "https://api.anthropic.com/api/oauth/usage") || exit 0
  unset token

  code=$(printf '%s' "$response" | tail -n1)
  body=$(printf '%s' "$response" | sed '$d')
  [[ "$code" == "200" ]] || exit 0
fi

now=$(date +%s)
out=$(printf '%s' "$body" | jq -c --argjson now "$now" '
  def iso_epoch: select(type == "string")
    | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601;
  def window($id; $label):
    select(. != null)
    | {id: $id, label: $label,
       usedPercent: .utilization,
       resetsAt: (.resets_at | iso_epoch)};
  {
    schema: 1,
    source: "claude-code",
    updatedAt: $now,
    origin: "poll",
    windows: [
      (.five_hour | window("five_hour"; "Session")),
      (.seven_day | window("seven_day"; "Week"))
    ]
    | map(select(.usedPercent != null and .resetsAt != null))
  }') || exit 0

[[ "$(printf '%s' "$out" | jq '.windows | length')" -gt 0 ]] || exit 0

tmp=$(mktemp "$USAGE_DIR/.claude-code.XXXXXX") || exit 0
if printf '%s\n' "$out" > "$tmp"; then
  mv "$tmp" "$USAGE_FILE"
else
  rm -f "$tmp"
fi
