#!/bin/bash
body_file=""; config="$(cat)"
while (($#)); do
  case "$1" in
    -o) body_file="$2"; shift 2 ;;
    *) shift ;;
  esac
done
account="$(printf '%s' "$config" | awk -F'token-' 'NF > 1 {print $2}' | awk -F'"' '{print $1}')"
printf '%s\n' "$account" >> "$CURL_LOG"
if [[ -n "${OVERLAP_TARGET:-}" && "$account" == "${OVERLAP_ACCOUNT:-}" ]]; then
  cp "$OVERLAP_RECORD" "$OVERLAP_TARGET"
fi
if [[ "$account" == "${FAIL_ACCOUNT:-}" ]]; then
  printf '{"error":"unavailable"}\n' > "$body_file"
  printf '503'
else
  cp "$POLLER_RESPONSE_FIXTURE" "$body_file"
  printf '200'
fi
