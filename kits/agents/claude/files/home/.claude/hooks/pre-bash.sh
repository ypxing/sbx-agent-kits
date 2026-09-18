#!/usr/bin/env bash
input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || cmd=""

# shellcheck source=pre-bash-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/pre-bash-common.sh"

if pre_bash_command_blocked "$cmd"; then
  echo '{"hookSpecificOutput": {"permissionDecision": "deny"}, "systemMessage": "Blocked: make *deploy*, git push to main/master, non-read-only aws commands (only describe-/list-/get-/head-/lookup-/search-/query/scan/tail/ls are allowed), docker compose *deploy*, rm -rf, wget, reading .env*/.npmrc*/.yarnrc* files, destructive SQL (UPDATE/DELETE/DROP/TRUNCATE/ALTER DROP)"}' >&2
  exit 2
fi
