#!/bin/bash
# Claude Code statusline entry point. Records usage for the widget, then runs the
# user's real statusline command with the same payload and passes its output through.
#
# Usage: statusline-wrapper.sh '<inner statusline command>'
#
# The inner command is passed as an argument rather than hardcoded because the two
# config directories in use have different statusline commands.

INNER="${1:-}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

input=$(cat)
pipe_input() { printf '%s' "$input" | "$@"; }

HELPER="$DIR/runwaygauge-helper"
[[ -n "${BROKEN_WRITER:-}" ]] && HELPER="$DIR/does-not-exist"

# Backgrounded and fully silenced: the widget must never be able to slow, break,
# or add noise to the statusline. Account resolution uses CLAUDE_CONFIG_DIR + registry.
pipe_input "$HELPER" write >/dev/null 2>&1 &
[[ -n "$INNER" ]] && pipe_input bash -c "$INNER"

exit 0
