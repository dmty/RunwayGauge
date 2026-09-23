#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/scripts/helpers-bundle/Helpers"
# ponytail: explicit list beats glob — bundle must stay predictable for install + tests
RUNTIME=(
  install-statusline.sh uninstall-statusline.sh install-poller.sh statusline-wrapper.sh
  com.mirabilia.runwaygauge.claudeusage.plist
  lib/accounts.sh lib/claude-config.sh lib/helper-state.sh lib/paths.sh lib/runtime-env.sh lib/usage-commit.sh
)

[[ "${1:-}" == "--list" ]] && { printf '%s\n' "${RUNTIME[@]}" runwaygauge-helper; exit 0; }

rm -rf "$DEST" && mkdir -p "$DEST/lib"
for f in "${RUNTIME[@]}"; do cp "$ROOT/scripts/$f" "$DEST/$f"; done

# Universal binary (arm64 + x86_64) for Intel + Apple Silicon Macs.
(
  cd "$ROOT/Core"
  ARCHS=(--arch arm64 --arch x86_64)
  swift build -c release "${ARCHS[@]}" --product RunwayGaugeHelper
  # Output dir differs between SwiftPM build systems; ask instead of hardcoding.
  cp "$(swift build -c release "${ARCHS[@]}" --show-bin-path)/RunwayGaugeHelper" "$DEST/runwaygauge-helper"
  for arch in arm64 x86_64; do lipo "$DEST/runwaygauge-helper" -verify_arch "$arch"; done
  # Ad-hoc by default; Developer ID when CODESIGN_IDENTITY is set.
  if [[ -n "${CODESIGN_IDENTITY:-}" && "$CODESIGN_IDENTITY" != "-" ]]; then
    codesign -s "$CODESIGN_IDENTITY" --force --timestamp --options runtime "$DEST/runwaygauge-helper"
  else
    codesign -s - --force --timestamp=none "$DEST/runwaygauge-helper"
  fi
)

find "$DEST" -type f \( -name '*.sh' -o -name 'runwaygauge-helper' \) -exec chmod 755 {} +
find "$DEST/lib" -type f -exec chmod 644 {} +
chmod 644 "$DEST/com.mirabilia.runwaygauge.claudeusage.plist"
