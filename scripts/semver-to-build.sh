#!/bin/bash
# Convert MAJOR.MINOR.PATCH -> M*10000 + m*100 + p (e.g. 0.1.0 -> 100).
set -euo pipefail
ver="${1:?usage: semver-to-build.sh MAJOR.MINOR.PATCH}"
[[ "$ver" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || {
  echo "invalid semver: $ver" >&2
  exit 1
}
(( BASH_REMATCH[2] <= 99 && BASH_REMATCH[3] <= 99 )) || {
  echo "minor and patch must be <= 99 for collision-free build numbers: $ver" >&2
  exit 1
}
echo $(( BASH_REMATCH[1] * 10000 + BASH_REMATCH[2] * 100 + BASH_REMATCH[3] ))
