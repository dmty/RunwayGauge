# shellcheck shell=bash
# Single source of truth for the data location. Task 3 gate selected the
# extension-container fallback. Tests set USAGE_DIR_OVERRIDE to a sandbox.
USAGE_DIR="${USAGE_DIR_OVERRIDE:-$HOME/Library/Containers/com.mirabilia.RunwayGauge.UsageWidget/Data/Library/Application Support/RunwayGauge}"
# Kept for migration and older helpers only. New writers must use the
# account-specific path returned by usage_file_for_account.
# shellcheck disable=SC2034
USAGE_FILE="$USAGE_DIR/claude-code.json"
# shellcheck disable=SC2034
ACCOUNTS_FILE="$USAGE_DIR/accounts.json"

usage_file_for_account() {
  local account_id="${1:-}"
  [[ "$account_id" =~ ^acc_[A-Za-z0-9_-]{1,64}$ ]] || return 1
  printf '%s/usage-%s.json\n' "$USAGE_DIR" "$account_id"
}
