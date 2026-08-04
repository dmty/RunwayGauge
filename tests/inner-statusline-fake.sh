#!/bin/bash
# Stands in for the user's real statusline command. Reads the payload and prints
# a deterministic line including a trailing-newline-free suffix.
input=$(cat)
printf '%s' "$(printf '%s' "$input" | jq -r '"MODEL:\(.model.display_name // "?")|DIR:\(.workspace.current_dir // "?")"')"
