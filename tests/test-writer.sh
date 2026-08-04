#!/bin/bash
# Writer tests. Runs against a temporary USAGE_DIR, never the real one.
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
FAILED=0

pass() { echo "  ok   - $1"; }
fail() { echo "  FAIL - $1"; FAILED=1; }
check() { [[ "$2" == "$3" ]] && pass "$1" || { fail "$1"; echo "         expected: $3"; echo "         actual:   $2"; }; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export USAGE_DIR_OVERRIDE="$SANDBOX/data"
# shellcheck source=scripts/lib/paths.sh
source "$ROOT/scripts/lib/paths.sh"
FILE="$USAGE_FILE"

echo "writer: both windows"
"$ROOT/scripts/write-claude-usage.sh" < tests/fixtures/statusline-both.json
check "schema is 1" "$(jq -r .schema "$FILE")" "1"
check "source" "$(jq -r .source "$FILE")" "claude-code"
check "origin" "$(jq -r .origin "$FILE")" "statusline"
check "window count" "$(jq -r '.windows | length' "$FILE")" "2"
check "first id" "$(jq -r '.windows[0].id' "$FILE")" "five_hour"
check "first label" "$(jq -r '.windows[0].label' "$FILE")" "Session"
check "first percent" "$(jq -r '.windows[0].usedPercent' "$FILE")" "19.4"
check "first resetsAt" "$(jq -r '.windows[0].resetsAt' "$FILE")" "1785823140"
check "second id" "$(jq -r '.windows[1].id' "$FILE")" "seven_day"
check "second label" "$(jq -r '.windows[1].label' "$FILE")" "Week"
check "updatedAt is a recent epoch" \
  "$(jq -r --argjson now "$(date +%s)" 'if (($now - .updatedAt) | fabs) < 30 then "recent" else "stale" end' "$FILE")" \
  "recent"

echo "writer: session only"
rm -f "$FILE"
"$ROOT/scripts/write-claude-usage.sh" < tests/fixtures/statusline-session-only.json
check "one window" "$(jq -r '.windows | length' "$FILE")" "1"
check "it is five_hour" "$(jq -r '.windows[0].id' "$FILE")" "five_hour"

echo "writer: no rate_limits, no existing file"
rm -f "$FILE"
"$ROOT/scripts/write-claude-usage.sh" < tests/fixtures/statusline-none.json
check "writes an empty-window record" "$(jq -r '.windows | length' "$FILE")" "0"

echo "writer: no rate_limits must not clobber good data"
rm -f "$FILE"   # the previous block left a fresh file, which would skip the write below
"$ROOT/scripts/write-claude-usage.sh" < tests/fixtures/statusline-both.json
touch -t 200001010000 "$FILE"   # age it past the 30s skip
"$ROOT/scripts/write-claude-usage.sh" < tests/fixtures/statusline-none.json
check "existing windows survive" "$(jq -r '.windows | length' "$FILE")" "2"

echo "writer: skips a write when the file is fresh"
"$ROOT/scripts/write-claude-usage.sh" < tests/fixtures/statusline-both.json
touch -t 200001010000 "$FILE"
"$ROOT/scripts/write-claude-usage.sh" < tests/fixtures/statusline-session-only.json
check "the aged file was rewritten" "$(jq -r '.windows | length' "$FILE")" "1"
"$ROOT/scripts/write-claude-usage.sh" < tests/fixtures/statusline-both.json
check "the fresh file was left alone" "$(jq -r '.windows | length' "$FILE")" "1"

echo "writer: leaves no temp files behind"
check "temp file count" "$(find "$USAGE_DIR" -name '.claude-code.*' | wc -l | tr -d ' ')" "0"

echo "wrapper: inner statusline output passes through byte-identical"
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
