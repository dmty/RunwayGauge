#!/bin/bash
# Reads a Claude Code statusline payload on stdin and records the subscription
# usage windows for the widget. Never fails loudly: it runs inside the statusline.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/paths.sh"

MIN_WRITE_INTERVAL=30

mkdir -p "$USAGE_DIR" || exit 0

# The statusline re-renders constantly; rewriting on every render is pointless.
if [[ -f "$USAGE_FILE" ]]; then
  age=$(( $(date +%s) - $(stat -f %m "$USAGE_FILE") ))
  (( age < MIN_WRITE_INTERVAL )) && exit 0
fi

input=$(cat)
now=$(date +%s)

out=$(printf '%s' "$input" | jq -c --argjson now "$now" '
  {
    schema: 1,
    source: "claude-code",
    updatedAt: $now,
    origin: "statusline",
    windows: [
      (.rate_limits.five_hour | select(. != null)
        | {id: "five_hour", label: "Session", usedPercent: .used_percentage, resetsAt: .resets_at}),
      (.rate_limits.seven_day | select(. != null)
        | {id: "seven_day", label: "Week", usedPercent: .used_percentage, resetsAt: .resets_at})
    ]
  }') || exit 0

# rate_limits is absent until the first API response of a session. Writing an
# empty record then would erase numbers the widget is still usefully showing.
if [[ "$(printf '%s' "$out" | jq '.windows | length')" -eq 0 && -s "$USAGE_FILE" ]]; then
  exit 0
fi

tmp=$(mktemp "$USAGE_DIR/.claude-code.XXXXXX") || exit 0
if printf '%s\n' "$out" > "$tmp"; then
  mv "$tmp" "$USAGE_FILE"
else
  rm -f "$tmp"
fi
exit 0
