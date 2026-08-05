#!/bin/bash
# Multi-account poller: selected-first, service+account keychain, no token logging.
set -uo pipefail

cd "$(dirname "$0")/.." || exit
ROOT="$PWD"
# shellcheck source=lib/assert.sh
source "$(dirname "$0")/lib/assert.sh"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export USAGE_DIR_OVERRIDE="$SANDBOX/data"
export POLLER_SECURITY_BIN="$SANDBOX/security"
export POLLER_CURL_BIN="$SANDBOX/curl"
export SECURITY_LOG="$SANDBOX/security.log"
export CURL_LOG="$SANDBOX/curl.log"
export POLLER_RESPONSE_FIXTURE="$ROOT/tests/fixtures/oauth-usage-response.json"
cp "$ROOT/tests/fixtures/poller-fake-security.sh" "$POLLER_SECURITY_BIN"
cp "$ROOT/tests/fixtures/poller-fake-curl.sh" "$POLLER_CURL_BIN"
chmod 755 "$POLLER_SECURITY_BIN" "$POLLER_CURL_BIN"

write_registry() {
  local selected="${1:-acc_secondary}"
  mkdir -p "$USAGE_DIR_OVERRIDE"
  jq --arg selected "$selected" '.prefs.selectedAccountId = $selected' \
    "$ROOT/tests/fixtures/accounts-poller.json" > "$USAGE_DIR_OVERRIDE/accounts.json"
}

reset_case() {
  rm -rf "$USAGE_DIR_OVERRIDE"
  mkdir -p "$USAGE_DIR_OVERRIDE"
  : > "$SECURITY_LOG"
  : > "$CURL_LOG"
  unset FAIL_ACCOUNT OVERLAP_TARGET OVERLAP_RECORD OVERLAP_ACCOUNT
}

run_poller() { "$ROOT/scripts/poll-claude-usage.sh"; }
usage_file() { printf '%s/usage-%s.json' "$USAGE_DIR_OVERRIDE" "$1"; }

echo "poller: selected account is polled first and credentials use service plus account"
reset_case
write_registry acc_secondary
run_poller
check "selected-first request order" "$(paste -sd, "$CURL_LOG")" "secondary-user,primary-user"
check "service-identical credentials select distinct accounts" \
  "$(sed -E 's/.*-s ([^ ]+) -a ([^ ]+) -w.*/\1:\2/' "$SECURITY_LOG" | paste -sd, -)" \
  "shared-service:secondary-user,shared-service:primary-user"
check "no service-only Keychain lookup" "$(awk '!/-a/ {bad++} END {print bad+0}' "$SECURITY_LOG")" "0"
check "primary output account" "$(jq -r .accountId "$(usage_file acc_primary)")" "acc_primary"
check "secondary output account" "$(jq -r .accountId "$(usage_file acc_secondary)")" "acc_secondary"
check "poll origin" "$(jq -r .origin "$(usage_file acc_primary)")" "poll"

echo "poller: freshness is evaluated per account"
: > "$CURL_LOG"
touch "$(usage_file acc_primary)"
touch -t 200001010000 "$(usage_file acc_secondary)"
run_poller
check "only stale account requested" "$(paste -sd, "$CURL_LOG")" "secondary-user"

echo "poller: config-only selected account is skipped and failures do not block later accounts"
reset_case
write_registry acc_primary
jq '(.accounts[0].credentials.keychain) = null' "$USAGE_DIR_OVERRIDE/accounts.json" > "$SANDBOX/r" &&
  mv "$SANDBOX/r" "$USAGE_DIR_OVERRIDE/accounts.json"
run_poller
check "config-only account skipped" "$(paste -sd, "$CURL_LOG")" "secondary-user"
missing "config-only account not written" "$(usage_file acc_primary)"
exists "next account still written" "$(usage_file acc_secondary)"

reset_case
write_registry acc_primary
export FAIL_ACCOUNT=primary-user
run_poller
check "HTTP failure continues" "$(paste -sd, "$CURL_LOG")" "primary-user,secondary-user"
missing "failed account preserves absence" "$(usage_file acc_primary)"
exists "second account committed" "$(usage_file acc_secondary)"

echo "poller: a newer overlapping writer observation wins"
reset_case
write_registry acc_primary
jq '.accounts = [.accounts[0]]' "$USAGE_DIR_OVERRIDE/accounts.json" > "$SANDBOX/r" &&
  mv "$SANDBOX/r" "$USAGE_DIR_OVERRIDE/accounts.json"
OVERLAP_TARGET="$(usage_file acc_primary)"
export OVERLAP_TARGET OVERLAP_ACCOUNT=primary-user
export OVERLAP_RECORD="$SANDBOX/newer.json"
future=$(( $(date +%s) + 60 ))
jq -n --argjson now "$future" '{
  schema:1, accountId:"acc_primary", source:"claude-code", updatedAt:$now,
  origin:"statusline", windows:[{id:"five_hour",label:"Session",usedPercent:7,resetsAt:1999999999}]
}' > "$OVERLAP_RECORD"
run_poller
check "newer statusline record retained" \
  "$(jq -r '.origin + ":" + (.updatedAt|tostring)' "$OVERLAP_TARGET")" "statusline:$future"

summary "poller"
