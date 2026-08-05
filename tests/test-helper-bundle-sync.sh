#!/bin/bash
# sync-helpers-bundle.sh declared runtime set must match bundled copies.
set -uo pipefail

cd "$(dirname "$0")/.." || exit
# shellcheck source=lib/assert.sh
source "$(dirname "$0")/lib/assert.sh"

declared=()
while IFS= read -r relative; do declared+=("$relative"); done \
  < <(./scripts/sync-helpers-bundle.sh --list)
required=(lib/accounts.sh lib/usage-commit.sh lib/helper-state.sh)

for f in "${required[@]}"; do
  printf '%s\n' "${declared[@]}" | grep -Fxq "$f" && pass "$f declared" || fail "$f declared"
done

./scripts/sync-helpers-bundle.sh
bundle="scripts/helpers-bundle/Helpers"
for relative in "${declared[@]}"; do
  src="scripts/$relative"
  dst="$bundle/$relative"
  [[ -f "$src" && -f "$dst" ]] && cmp -s "$src" "$dst" \
    && pass "$relative matches bundled copy" || fail "$relative matches bundled copy"
done

summary "helper bundle sync"
