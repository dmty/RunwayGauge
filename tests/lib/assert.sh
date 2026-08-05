#!/bin/bash
# ponytail: tiny shared assertions for shell integration tests.
FAILED=0
pass() { echo "  ok   - $1"; }
fail() { echo "  FAIL - $1"; FAILED=1; }
check() { [[ "$2" == "$3" ]] && pass "$1" || { fail "$1"; echo "         expected: $3"; echo "         actual:   $2"; }; }
check_exit() { [[ "$3" -eq "$2" ]] && pass "$1" || { fail "$1"; echo "         expected exit: $2"; echo "         actual exit:   $3"; }; }
exists() { [[ -f "$2" ]] && pass "$1" || fail "$1"; }
missing() { [[ ! -e "$2" ]] && pass "$1" || fail "$1"; }
summary() { [[ $FAILED -eq 0 ]] && echo "all $1 tests passed" || echo "$1 tests FAILED"; exit $FAILED; }
