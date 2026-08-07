#!/bin/bash
# Writer and shell registry tests. Everything runs in an isolated data directory.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
FAILED=0

HELPER="$ROOT/Core/.build/debug/RunwayGaugeHelper"
if [[ ! -x "$HELPER" ]]; then
  (cd "$ROOT/Core" && swift build -c debug --product RunwayGaugeHelper) || exit 1
fi

pass() { echo "  ok   - $1"; }
fail() { echo "  FAIL - $1"; FAILED=1; }
check() {
  if [[ "$2" == "$3" ]]; then pass "$1"
  else fail "$1"; echo "         expected: $3"; echo "         actual:   $2"; fi
}

SANDBOX="$(mktemp -d)"
SANDBOX="$(cd -P "$SANDBOX" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
export USAGE_DIR_OVERRIDE="$SANDBOX/data"
mkdir -p "$HOME/.claude" "$USAGE_DIR_OVERRIDE"

# shellcheck source=scripts/lib/paths.sh
source "$ROOT/scripts/lib/paths.sh"
# shellcheck source=scripts/lib/accounts.sh
source "$ROOT/scripts/lib/accounts.sh"
# shellcheck source=scripts/lib/usage-commit.sh
source "$ROOT/scripts/lib/usage-commit.sh"

install_valid_registry() { cp "$ROOT/tests/fixtures/accounts-valid.json" "$ACCOUNTS_FILE"; }
run_writer() {
  local config="${1:-$HOME/.claude}"
  local fixture="${2:-$ROOT/tests/fixtures/statusline-both.json}"
  local account_id="${3:-}"
  if [[ -n "$account_id" ]]; then
    CLAUDE_CONFIG_DIR="$config" "$HELPER" write --account-id "$account_id" < "$fixture"
  else
    CLAUDE_CONFIG_DIR="$config" "$HELPER" write < "$fixture"
  fi
}
usage_file_count() { find "$USAGE_DIR" -name 'usage-*.json' -type f | wc -l | tr -d ' '; }
registry_validity() {
  if account_registry_valid "$ACCOUNTS_FILE"; then printf yes; else printf no; fi
}
race_fixture() {
  jq -n --argjson t "$2" --argjson p "$3" \
    '{schema:1,accountId:"acc_race",source:"claude-code",updatedAt:$t,origin:"test",
      windows:[{id:"five_hour",label:"Session",usedPercent:$p,resetsAt:1000}]}' > "$1"
}

echo "accounts: normalizes paths without evaluation"
mkdir -p "$SANDBOX/a directory/real"
ln -s "$SANDBOX/a directory/real" "$SANDBOX/config-link"
# shellcheck disable=SC2088
check "tilde path" "$(account_normalize_path "~/.claude/")" "$HOME/.claude"
check "absolute path with spaces" \
  "$(account_normalize_path "$SANDBOX/a directory/real/")" "$SANDBOX/a directory/real"
check "symlink path" \
  "$(account_normalize_path "$SANDBOX/config-link")" "$SANDBOX/a directory/real"
# shellcheck disable=SC2016
check "literal shell syntax is not evaluated" \
  "$(account_normalize_path '$HOME/not-expanded')" '$HOME/not-expanded'

echo "accounts: resolves exactly one Claude account"
install_valid_registry
account_resolve_claude "$ACCOUNTS_FILE" "$HOME/.claude/"
check "resolved tilde account" "$ACCOUNT_ID" "acc_primary"
check "resolved service" "$ACCOUNT_KEYCHAIN_SERVICE" "Claude Code-credentials"
check "resolved keychain account" "$ACCOUNT_KEYCHAIN_ACCOUNT" "primary-user"

jq --arg path "$SANDBOX/a directory/real/" \
  '.accounts[0].credentials.configDir = $path' \
  "$ROOT/tests/fixtures/accounts-valid.json" > "$ACCOUNTS_FILE"
account_resolve_claude "$ACCOUNTS_FILE" "$SANDBOX/config-link"
check "resolved absolute trailing-space path through symlink" "$ACCOUNT_ID" "acc_primary"

echo "accounts: enumerates pinned Claude accounts selected-first"
install_valid_registry
jq '.prefs.selectedAccountId = "acc_secondary"' "$ACCOUNTS_FILE" > "$ACCOUNTS_FILE.tmp"
mv "$ACCOUNTS_FILE.tmp" "$ACCOUNTS_FILE"
fields=()
while IFS= read -r -d '' field; do fields+=("$field"); done < <(
  account_enumerate_pinned_claude "$ACCOUNTS_FILE"
)
check "selected account is first" "${fields[0]:-}" "acc_secondary"
check "enumeration returns service" "${fields[3]:-}" "Claude Code-credentials"
check "enumeration returns keychain account" "${fields[4]:-}" "secondary-user"
check "remaining account follows" "${fields[5]:-}" "acc_primary"

echo "accounts: shell label validation avoids incompatible length counting"
install_valid_registry
jq --arg label "$(printf 'x%.0s' {1..101})" \
  '.accounts[0].label = $label' "$ACCOUNTS_FILE" > "$ACCOUNTS_FILE.tmp"
mv "$ACCOUNTS_FILE.tmp" "$ACCOUNTS_FILE"
check "shell accepts long nonempty label" "$(registry_validity)" "yes"
jq '.accounts[0].label = " \n\t "' "$ACCOUNTS_FILE" > "$ACCOUNTS_FILE.tmp"
mv "$ACCOUNTS_FILE.tmp" "$ACCOUNTS_FILE"
check "shell rejects whitespace-only label" "$(registry_validity)" "no"

echo "writer: refuses invalid or unresolved registries"
for name in malformed unknown-schema duplicate-id duplicate-keychain unsafe-id unmatched ambiguous; do
  rm -f "$USAGE_DIR"/usage-*.json
  case "$name" in
    malformed) cp "$ROOT/tests/fixtures/accounts-malformed.json" "$ACCOUNTS_FILE"; config="$HOME/.claude" ;;
    unknown-schema) jq '.schema = 2' "$ROOT/tests/fixtures/accounts-valid.json" > "$ACCOUNTS_FILE"; config="$HOME/.claude" ;;
    duplicate-id) jq '.accounts[1].id = .accounts[0].id' "$ROOT/tests/fixtures/accounts-valid.json" > "$ACCOUNTS_FILE"; config="$HOME/.claude" ;;
    duplicate-keychain) jq '.accounts[1].credentials.keychain = .accounts[0].credentials.keychain' "$ROOT/tests/fixtures/accounts-valid.json" > "$ACCOUNTS_FILE"; config="$HOME/.claude" ;;
    unsafe-id) jq '.accounts[0].id = "acc_../escape"' "$ROOT/tests/fixtures/accounts-valid.json" > "$ACCOUNTS_FILE"; config="$HOME/.claude" ;;
    unmatched) install_valid_registry; config="$SANDBOX/not-registered" ;;
    ambiguous)
      jq --arg real "$SANDBOX/a directory/real" --arg link "$SANDBOX/config-link" \
        '.accounts[0].credentials.configDir = $real | .accounts[1].credentials.configDir = $link' \
        "$ROOT/tests/fixtures/accounts-valid.json" > "$ACCOUNTS_FILE"
      config="$SANDBOX/a directory/real"
      ;;
  esac
  run_writer "$config"
  check "$name registry writes nothing" "$(usage_file_count)" "0"
done

echo "writer: writes only the matched account file"
install_valid_registry
printf 'legacy\n' > "$USAGE_DIR/claude-code.json"
printf 'archive\n' > "$USAGE_DIR/claude-code.legacy.json"
FILE="$USAGE_DIR/usage-acc_primary.json"
run_writer "$HOME/.claude" "$ROOT/tests/fixtures/statusline-both.json" acc_primary
check "schema is 2" "$(jq -r .schema "$FILE")" "2"
check "matching accountId" "$(jq -r .accountId "$FILE")" "acc_primary"
check "source" "$(jq -r .source "$FILE")" "claude-code"
check "origin" "$(jq -r .origin "$FILE")" "statusline"
check "window count" "$(jq -r '.windows | length' "$FILE")" "2"
check "first percent" "$(jq -r '.windows[0].usedPercent' "$FILE")" "19.4"
check "observation is recent" \
  "$(jq -r --argjson now "$(date +%s)" 'if (($now - .updatedAt) | fabs) < 30 then "recent" else "stale" end' "$FILE")" \
  "recent"
check "legacy usage remains untouched" "$(cat "$USAGE_DIR/claude-code.json")" "legacy"
check "legacy archive remains untouched" "$(cat "$USAGE_DIR/claude-code.legacy.json")" "archive"

echo "writer: preserves throttled and nonempty account data"
run_writer "$HOME/.claude" "$ROOT/tests/fixtures/statusline-session-only.json" acc_primary
check "fresh account file is throttled" "$(jq -r '.windows | length' "$FILE")" "2"
touch -t 200001010000 "$FILE"
run_writer "$HOME/.claude" "$ROOT/tests/fixtures/statusline-none.json" acc_primary
check "empty payload preserves windows" "$(jq -r '.windows | length' "$FILE")" "2"
touch -t 200001010000 "$FILE"
sleep 1
run_writer "$HOME/.claude" "$ROOT/tests/fixtures/statusline-session-only.json" acc_primary
check "stale account file is replaced" "$(jq -r '.windows | length' "$FILE")" "1"

echo "usage commit: concurrent candidates retain newer observation"
TARGET="$USAGE_DIR/usage-acc_race.json"
OLDER="$USAGE_DIR/.usage-acc_race.older"
NEWER="$USAGE_DIR/.usage-acc_race.newer"
race_fixture "$OLDER" 100 10
race_fixture "$NEWER" 200 20
usage_commit "$TARGET" "$OLDER" 30
usage_commit "$TARGET" "$NEWER" 30
check "in-flight newer observation beats fresh older commit" "$(jq -r .updatedAt "$TARGET")" "200"

rm -f "$TARGET"
race_fixture "$OLDER" 100 10
race_fixture "$NEWER" 200 20
usage_commit "$TARGET" "$OLDER" 30 & older_pid=$!
usage_commit "$TARGET" "$NEWER" 30 & newer_pid=$!
wait "$older_pid" "$newer_pid" 2>/dev/null
check "newer observation wins" "$(jq -r .updatedAt "$TARGET")" "200"
check "newer payload wins" "$(jq -r '.windows[0].usedPercent' "$TARGET")" "20"

echo "writer: leaves no candidate files behind"
check "temporary file count" \
  "$(find "$USAGE_DIR" -name '.usage-*.candidate.*' -o -name '.usage-*.tmp.*' | wc -l | tr -d ' ')" "0"

echo "wrapper: inner statusline output passes through byte-identical"
install_valid_registry
INNER="bash $ROOT/tests/inner-statusline-fake.sh"
direct="$(bash "$ROOT/tests/inner-statusline-fake.sh" < tests/fixtures/statusline-both.json | xxd -p)"
wrapped="$("$ROOT/scripts/statusline-wrapper.sh" "$INNER" < tests/fixtures/statusline-both.json | xxd -p)"
check "identical bytes" "$wrapped" "$direct"

echo "wrapper: survives a broken writer"
BROKEN_WRITER=1 "$ROOT/scripts/statusline-wrapper.sh" "$INNER" < tests/fixtures/statusline-both.json >/dev/null 2>&1
check "wrapper exit code" "$?" "0"

echo "wrapper: survives a missing inner command"
"$ROOT/scripts/statusline-wrapper.sh" "" < tests/fixtures/statusline-both.json >/dev/null 2>&1
check "wrapper exit code with no inner" "$?" "0"

[[ $FAILED -eq 0 ]] && echo "all writer tests passed" || echo "writer tests FAILED"
exit $FAILED
