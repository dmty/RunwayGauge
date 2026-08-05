#!/bin/bash
# Reads a Claude Code statusline payload on stdin and records the subscription
# usage windows for the widget. Never fails loudly: it runs inside the statusline.
set -uo pipefail

# shellcheck source=lib/runtime-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/runtime-env.sh"
# shellcheck source=lib/paths.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/paths.sh"
# shellcheck source=lib/accounts.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/accounts.sh"
# shellcheck source=lib/usage-commit.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/usage-commit.sh"

MIN_WRITE_INTERVAL=30
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

account_resolve_claude "$ACCOUNTS_FILE" "$config_dir" || exit 0
target="$(usage_file_for_account "$ACCOUNT_ID")" || exit 0
mkdir -p "$USAGE_DIR" || exit 0

# The statusline re-renders constantly; rewriting on every render is pointless.
if [[ -f "$target" ]]; then
  age=$(( $(date +%s) - $(stat -f %m "$target") ))
  (( age < MIN_WRITE_INTERVAL )) && exit 0
fi

input=$(cat)
observed_at=$(date +%s)

out=$(printf '%s' "$input" | jq -c \
  --arg accountId "$ACCOUNT_ID" \
  --argjson observedAt "$observed_at" '
  {
    schema: 1,
    accountId: $accountId,
    source: "claude-code",
    updatedAt: $observedAt,
    origin: "statusline",
    windows: [
      (.rate_limits.five_hour | select(. != null)
        | {id: "five_hour", label: "Session", usedPercent: .used_percentage, resetsAt: .resets_at}),
      (.rate_limits.seven_day | select(. != null)
        | {id: "seven_day", label: "Week", usedPercent: .used_percentage, resetsAt: .resets_at})
    ]
  }') || exit 0

candidate=$(mktemp "$USAGE_DIR/.usage-${ACCOUNT_ID}.candidate.XXXXXX") || exit 0
printf '%s\n' "$out" > "$candidate" || { rm -f "$candidate"; exit 0; }

# The helper re-reads the latest same-account record while holding the lock,
# rejects stale/empty candidates, and atomically replaces from beside target.
usage_commit "$target" "$candidate" "$MIN_WRITE_INTERVAL" >/dev/null 2>&1 || true
exit 0
