#!/bin/bash
# One-off probe: prints the /api/oauth/usage status code and body shape so the
# poller can be written against the real response.
#
# The token is read into a variable, used once, and never written to disk or logged.
set -uo pipefail

creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) || {
  echo "could not read the keychain item 'Claude Code-credentials'" >&2
  echo "if a prompt appeared, choose Always Allow and re-run" >&2
  exit 1
}

token=$(printf '%s' "$creds" | jq -r '.claudeAiOauth.accessToken // empty')
unset creds

if [[ -z "$token" ]]; then
  echo "no accessToken at .claudeAiOauth.accessToken; inspect the keychain item's key names" >&2
  exit 1
fi

response=$(curl -sS --max-time 15 -w '\n%{http_code}' \
  -H "Authorization: Bearer $token" \
  -H "Accept: application/json" \
  -H "User-Agent: mac-usage-widget-probe/1.0" \
  "https://api.anthropic.com/api/oauth/usage")
unset token

code=$(printf '%s' "$response" | tail -n1)
body=$(printf '%s' "$response" | sed '$d')

echo "HTTP $code"
if [[ "$code" == "200" ]]; then
  mkdir -p tests/fixtures
  printf '%s\n' "$body" | jq . > tests/fixtures/oauth-usage-response.json
  echo "saved tests/fixtures/oauth-usage-response.json"
  echo "--- key paths ---"
  printf '%s' "$body" | jq -r '[paths(scalars) | join(".")] | .[]'
else
  printf '%s\n' "$body" | head -c 2000
fi
