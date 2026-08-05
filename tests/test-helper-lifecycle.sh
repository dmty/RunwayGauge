#!/bin/bash
# Statusline helper ownership and reconciliation tests.
set -uo pipefail

cd "$(dirname "$0")/.." || exit
ROOT="$PWD"
# shellcheck source=tests/lib/assert.sh
source "$(dirname "$0")/lib/assert.sh"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
export USAGE_DIR_OVERRIDE="$SANDBOX/data"
export HELPER_STATE_FILE_OVERRIDE="$SANDBOX/helper state/installations.json"
mkdir -p "$HOME" "$USAGE_DIR_OVERRIDE"

FIRST="$SANDBOX/config one"
SECOND="$SANDBOX/config two"
mkdir -p "$FIRST" "$SECOND"
jq -n '{statusLine:{type:"command",command:"first-original"}}' > "$FIRST/settings.json"
jq -n '{statusLine:{type:"command",command:"second-original"}}' > "$SECOND/settings.json"

write_registry() {
  local include_second="${1:-0}"
  jq -n --arg first "$FIRST" --arg second "$SECOND" --argjson includeSecond "$include_second" '{
    schema:1, revision:1,
    prefs:{selectedAccountId:"acc_one",rotateEnabled:false,rotateIntervalSec:900},
    accounts: ([
      {id:"acc_one",label:"One",sourceKind:"claude-oauth",pinned:true,
       credentials:{configDir:$first,keychain:{service:"svc",account:"one"}}}
    ] + if $includeSecond == 1 then [
      {id:"acc_two",label:"Two",sourceKind:"claude-oauth",pinned:true,
       credentials:{configDir:$second,keychain:{service:"svc",account:"two"}}}
    ] else [] end)
  }' > "$USAGE_DIR_OVERRIDE/accounts.json"
}

cmd() { jq -r '.statusLine.command // ""' "$1/settings.json"; }
manifest_count() { jq -r '.entries | length' "$HELPER_STATE_FILE_OVERRIDE"; }
is_wrapper() { [[ "$1" == *statusline-wrapper.sh* ]] && printf yes || printf no; }

echo "helper lifecycle: install, rerun, add directory"
write_registry 0
"$ROOT/scripts/install-statusline.sh" >/dev/null
first_installed="$(cmd "$FIRST")"
check "wrapper installed in registry directory" "$(is_wrapper "$first_installed")" "yes"
check "one manifest owner" "$(manifest_count)" "1"
"$ROOT/scripts/install-statusline.sh" >/dev/null
check "rerun is idempotent" "$(manifest_count):$(cmd "$FIRST")" "1:$first_installed"

echo "helper lifecycle: interrupted install retries recorded ownership"
jq '.statusLine = {type:"command",command:"first-original"}' \
  "$FIRST/settings.json" > "$SANDBOX/interrupted-settings" &&
  mv "$SANDBOX/interrupted-settings" "$FIRST/settings.json"
"$ROOT/scripts/install-statusline.sh" >/dev/null
check "interrupted install is completed" "$(cmd "$FIRST")" "$first_installed"
check "recovered install keeps one owner" "$(manifest_count)" "1"

write_registry 1
"$ROOT/scripts/install-statusline.sh" >/dev/null
check "new registry directory installed" "$(is_wrapper "$(cmd "$SECOND")")" "yes"
check "manifest tracks both directories" "$(manifest_count)" "2"

echo "helper lifecycle: removed account restores only owned command"
write_registry 1
jq '.accounts = [.accounts[1]] | .prefs.selectedAccountId = "acc_two"' \
  "$USAGE_DIR_OVERRIDE/accounts.json" > "$SANDBOX/registry" &&
  mv "$SANDBOX/registry" "$USAGE_DIR_OVERRIDE/accounts.json"
"$ROOT/scripts/install-statusline.sh" >/dev/null
check "removed directory restored" "$(cmd "$FIRST")" "first-original"
check "removed owner deleted from manifest" "$(manifest_count)" "1"

echo "helper lifecycle: registry deletion cannot strand an owned wrapper"
rm "$USAGE_DIR_OVERRIDE/accounts.json"
"$ROOT/scripts/install-statusline.sh" >/dev/null
check "deleted registry restores manifest-owned directory" "$(cmd "$SECOND")" "second-original"
check "manifest emptied after reconcile" "$(manifest_count)" "0"

echo "helper lifecycle: full uninstall uses manifest and preserves user edits"
write_registry 1
"$ROOT/scripts/install-statusline.sh" >/dev/null
rm "$USAGE_DIR_OVERRIDE/accounts.json"
"$ROOT/scripts/uninstall-statusline.sh" >/dev/null
check "uninstall restores first without registry" "$(cmd "$FIRST")" "first-original"
check "uninstall restores second without registry" "$(cmd "$SECOND")" "second-original"

write_registry 0
"$ROOT/scripts/install-statusline.sh" >/dev/null
jq '.statusLine.command = "user-edited-after-install"' "$FIRST/settings.json" > "$SANDBOX/settings" &&
  mv "$SANDBOX/settings" "$FIRST/settings.json"
output="$("$ROOT/scripts/uninstall-statusline.sh")"
check "user edit preserved on uninstall" "$(cmd "$FIRST")" "user-edited-after-install"
check "manual cleanup reported" \
  "$([[ "$output" == *"manual cleanup"* ]] && printf yes || printf no)" "yes"

echo "helper lifecycle: upgrades an old unowned wrapper without nesting"
jq -n '{statusLine:{type:"command",command:"legacy-original"}}' \
  > "$FIRST/settings.json.bak-usagewidget"
jq -n --arg command "bash \"$ROOT/scripts/statusline-wrapper.sh\" legacy-original" \
  '{statusLine:{type:"command",command:$command}}' > "$FIRST/settings.json"
write_registry 0
"$ROOT/scripts/install-statusline.sh" >/dev/null
check "upgraded command has one wrapper" \
  "$(cmd "$FIRST" | grep -o 'statusline-wrapper\.sh' | wc -l | tr -d ' ')" "1"
check "backup command recorded as previous" \
  "$(jq -r '.entries[0].previousStatusLine.command' "$HELPER_STATE_FILE_OVERRIDE")" \
  "legacy-original"
"$ROOT/scripts/uninstall-statusline.sh" >/dev/null
check "upgrade uninstall restores backup command" "$(cmd "$FIRST")" "legacy-original"

echo "helper lifecycle: upgrades an unowned wrapper without a backup"
rm -f "$FIRST/settings.json.bak-usagewidget"
jq -n --arg command "bash \"$ROOT/scripts/statusline-wrapper.sh\" unknown-original" \
  '{statusLine:{type:"command",command:$command}}' > "$FIRST/settings.json"
"$ROOT/scripts/install-statusline.sh" >/dev/null
check "backup-free upgrade has one wrapper" \
  "$(cmd "$FIRST" | grep -o 'statusline-wrapper\.sh' | wc -l | tr -d ' ')" "1"
check "backup-free upgrade records unknown previous state" \
  "$(jq -r '.entries[0].previousStatusLine == null' "$HELPER_STATE_FILE_OVERRIDE")" \
  "true"
"$ROOT/scripts/uninstall-statusline.sh" >/dev/null
check "backup-free uninstall removes owned statusline" \
  "$(jq -r 'has("statusLine")' "$FIRST/settings.json")" "false"

summary "helper lifecycle"
