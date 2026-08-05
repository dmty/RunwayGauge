#!/bin/bash
set -uo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=lib/assert.sh
source "$(dirname "$0")/lib/assert.sh"

BOOTSTRAP="$PWD/scripts/install-helpers-from-bundle.sh"
[[ -x "$BOOTSTRAP" ]] || { echo "missing bootstrap: $BOOTSTRAP"; exit 1; }

make_stub_helpers() {
  local root="$1" statusline_exit="${2:-0}" poller_exit="${3:-0}"
  mkdir -p "$root"
  printf '#!/bin/bash\nexit %s\n' "$statusline_exit" > "$root/install-statusline.sh"
  printf '#!/bin/bash\nexit %s\n' "$poller_exit" > "$root/install-poller.sh"
  chmod 755 "$root/install-statusline.sh" "$root/install-poller.sh"
}

run_bootstrap() {
  set +e
  "$BOOTSTRAP" "$1" "$2" >/dev/null
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
  && pass "installers copied to destination" || fail "installers copied to destination"

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
for spec in "10:1:0" "11:0:1" "12:1:1"; do
  IFS=: read -r code st pl <<< "$spec"
  SRC="$SANDBOX/src-exit$code"
  DEST="$SANDBOX/dest-exit$code"
  make_stub_helpers "$SRC" "$st" "$pl"
  check_exit "exit $code" "$code" "$(run_bootstrap "$SRC" "$DEST")"
done

echo "helper-setup: missing source or installers"
check_exit "missing source dir" 2 "$(run_bootstrap "$SANDBOX/no-such-dir" "$SANDBOX/dest-missing-src")"
BAD="$SANDBOX/bad-src"
mkdir -p "$BAD"
check_exit "missing installers" 2 "$(run_bootstrap "$BAD" "$SANDBOX/dest-bad-src")"

summary "helper-setup"
