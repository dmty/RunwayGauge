#!/bin/bash
set -uo pipefail

cd "$(dirname "$0")/.."
FAILED=0
pass() { echo "  ok   - $1"; }
fail() { echo "  FAIL - $1"; FAILED=1; }
check_exit() {
  local label="$1" expected="$2" actual="$3"
  [[ "$actual" -eq "$expected" ]] && pass "$label" || {
    fail "$label"
    echo "         expected exit: $expected"
    echo "         actual exit:   $actual"
  }
}

BOOTSTRAP="$PWD/scripts/install-helpers-from-bundle.sh"
[[ -x "$BOOTSTRAP" ]] || { echo "missing bootstrap: $BOOTSTRAP"; exit 1; }

make_stub_helpers() {
  local root="$1"
  local statusline_exit="${2:-0}"
  local poller_exit="${3:-0}"
  mkdir -p "$root"
  cat > "$root/install-statusline.sh" <<EOF
#!/bin/bash
exit $statusline_exit
EOF
  cat > "$root/install-poller.sh" <<EOF
#!/bin/bash
exit $poller_exit
EOF
  chmod 755 "$root/install-statusline.sh" "$root/install-poller.sh"
}

run_bootstrap() {
  local src="$1" dest="$2"
  set +e
  "$BOOTSTRAP" "$src" "$dest" >/dev/null
  local code=$?
  set -e
  echo "$code"
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

echo "helper-setup: both installers succeed"
SRC="$SANDBOX/src-ok"
DEST="$SANDBOX/dest-ok"
make_stub_helpers "$SRC" 0 0
check_exit "exit 0 when both succeed" 0 "$(run_bootstrap "$SRC" "$DEST")"
[[ -x "$DEST/install-statusline.sh" && -x "$DEST/install-poller.sh" ]] \
  && pass "installers copied to destination" \
  || fail "installers copied to destination"

echo "helper-setup: rsync replaces stale destination files"
STALE="$SANDBOX/stale-marker"
echo stale > "$DEST/stale-marker"
make_stub_helpers "$SRC" 0 0
run_bootstrap "$SRC" "$DEST" >/dev/null
[[ ! -f "$STALE" ]] && pass "stale files removed" || fail "stale files removed"

echo "helper-setup: paths with spaces"
SRC="$SANDBOX/src with spaces"
DEST="$SANDBOX/dest with spaces"
make_stub_helpers "$SRC" 0 0
check_exit "spaces in paths" 0 "$(run_bootstrap "$SRC" "$DEST")"

echo "helper-setup: partial and failure exit codes"
SRC="$SANDBOX/src-exit10"
DEST="$SANDBOX/dest-exit10"
make_stub_helpers "$SRC" 1 0
check_exit "exit 10 statusline only" 10 "$(run_bootstrap "$SRC" "$DEST")"
SRC="$SANDBOX/src-exit11"
DEST="$SANDBOX/dest-exit11"
make_stub_helpers "$SRC" 0 1
check_exit "exit 11 poller only" 11 "$(run_bootstrap "$SRC" "$DEST")"
SRC="$SANDBOX/src-exit12"
DEST="$SANDBOX/dest-exit12"
make_stub_helpers "$SRC" 1 1
check_exit "exit 12 both failed" 12 "$(run_bootstrap "$SRC" "$DEST")"

echo "helper-setup: missing source or installers"
check_exit "missing source dir" 2 "$(run_bootstrap "$SANDBOX/no-such-dir" "$SANDBOX/dest-missing-src")"
BAD="$SANDBOX/bad-src"
mkdir -p "$BAD"
check_exit "missing installers" 2 "$(run_bootstrap "$BAD" "$SANDBOX/dest-bad-src")"

[[ $FAILED -eq 0 ]] && echo "all helper-setup tests passed" || echo "helper-setup tests FAILED"
exit $FAILED
