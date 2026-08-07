#!/bin/bash
# Usage: install-helpers-from-bundle.sh <bundled-helpers-dir> <dest-helpers-dir>
set -euo pipefail
SRC="${1:?}"; DEST="${2:?}"
[[ -d "$SRC" ]] || { echo "missing bundled helpers: $SRC" >&2; exit 2; }
[[ -x "$SRC/install-statusline.sh" && -x "$SRC/install-poller.sh" ]] || {
  echo "bundled installers are missing or not executable" >&2
  exit 2
}
[[ -x "$SRC/runwaygauge-helper" ]] || {
  echo "bundled runwaygauge-helper is missing or not executable" >&2
  exit 2
}
if ! mkdir -p "$DEST" || \
   ! rsync -a --delete "$SRC/" "$DEST/" || \
   ! find "$DEST" -type f -name '*.sh' -exec chmod 755 {} + || \
   ! chmod 755 "$DEST/runwaygauge-helper"; then
  echo "failed to prepare installed helper directory" >&2
  exit 2
fi

statusline_failed=0
poller_failed=0

echo "== statusline =="
if ! "$DEST/install-statusline.sh"; then
  statusline_failed=1
fi

echo "== poller =="
if ! "$DEST/install-poller.sh"; then
  poller_failed=1
fi

if (( statusline_failed && poller_failed )); then exit 12; fi
if (( statusline_failed )); then exit 10; fi
if (( poller_failed )); then exit 11; fi
exit 0
