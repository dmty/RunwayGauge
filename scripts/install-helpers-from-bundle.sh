#!/bin/bash
# Usage: install-helpers-from-bundle.sh <bundled-helpers-dir> <dest-helpers-dir>
set -euo pipefail
SRC="${1:?}"; DEST="${2:?}"

[[ -d "$SRC" && -x "$SRC/install-statusline.sh" && -x "$SRC/install-poller.sh" && -x "$SRC/runwaygauge-helper" ]] || {
  echo "bundled helpers incomplete: $SRC" >&2; exit 2
}

mkdir -p "$DEST"
rsync -a --delete "$SRC/" "$DEST/"
find "$DEST" -type f -name '*.sh' -exec chmod 755 {} +
chmod 755 "$DEST/runwaygauge-helper"

st=0 pl=0
echo "== statusline =="
"$DEST/install-statusline.sh" || st=1
echo "== poller =="
"$DEST/install-poller.sh" || pl=1

(( !st && !pl )) && exit 0
(( st && pl )) && exit 12
(( st )) && exit 10
exit 11
