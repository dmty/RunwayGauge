#!/bin/bash
# Tests the poller's response→contract mapping against the recorded response.
set -uo pipefail

cd "$(dirname "$0")/.."
FAILED=0
pass() { echo "  ok   - $1"; }
fail() { echo "  FAIL - $1"; FAILED=1; }
check() { [[ "$2" == "$3" ]] && pass "$1" || { fail "$1"; echo "         expected: $3"; echo "         actual:   $2"; }; }
run_poller() { POLLER_FIXTURE=tests/fixtures/oauth-usage-response.json ./scripts/poll-claude-usage.sh; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export USAGE_DIR_OVERRIDE="$SANDBOX/data"
FILE="$USAGE_DIR_OVERRIDE/claude-code.json"

echo "poller: maps the recorded response into the data contract"
run_poller
check "schema" "$(jq -r .schema "$FILE")" "1"
check "origin" "$(jq -r .origin "$FILE")" "poll"
check "source" "$(jq -r .source "$FILE")" "claude-code"
check "windows present" "$(jq -r '.windows | length >= 1' "$FILE")" "true"
check "every window has an id" "$(jq -r '[.windows[] | select(.id == null)] | length' "$FILE")" "0"
check "every window has a numeric percent" "$(jq -r '[.windows[] | select(.usedPercent | type != "number")] | length' "$FILE")" "0"
check "every window has a numeric resetsAt" "$(jq -r '[.windows[] | select(.resetsAt | type != "number")] | length' "$FILE")" "0"
check "session percent" "$(jq -r '.windows[] | select(.id == "five_hour") | .usedPercent' "$FILE")" "38.0"
check "session reset converts to epoch" "$(jq -r '.windows[] | select(.id == "five_hour") | .resetsAt' "$FILE")" "1785824400"

echo "poller: skips when the file is fresh"
before=$(jq -r .updatedAt "$FILE")
run_poller
check "file untouched" "$(jq -r .updatedAt "$FILE")" "$before"

echo "poller: runs when the file is stale"
touch -t 200001010000 "$FILE"
run_poller
check "file rewritten" "$(jq -r --argjson now "$(date +%s)" 'if (($now - .updatedAt) | fabs) < 30 then "recent" else "old" end' "$FILE")" "recent"

[[ $FAILED -eq 0 ]] && echo "all poller tests passed" || echo "poller tests FAILED"
exit $FAILED
