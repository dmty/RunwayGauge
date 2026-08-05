#!/bin/bash
printf '%q ' "$@" >> "$SECURITY_LOG"; printf '\n' >> "$SECURITY_LOG"
service=""; account=""
while (($#)); do
  case "$1" in
    -s) service="$2"; shift 2 ;;
    -a) account="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$service" && -n "$account" ]] || exit 9
[[ "$account" != "missing-user" ]] || exit 44
printf '{"claudeAiOauth":{"accessToken":"token-%s"}}\n' "$account"
