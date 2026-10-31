#!/usr/bin/env bash
# Cursor sends {"hook_event_name": "beforeShellExecution", "command": "...", "cwd": "...", ...}
# on stdin and reads a JSON decision from stdout.
input=$(cat)
cmd=$(echo "$input" | jq -r '.command // empty' 2>/dev/null) || cmd=""

# shellcheck source=pre-bash-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/pre-bash-common.sh"

if pre_bash_command_blocked "$cmd"; then
  reason="Blocked: make *deploy*, git push to main/master, non-read-only aws commands (only describe-/list-/get-/head-/lookup-/search-/query/scan/tail/ls are allowed), docker compose *deploy*, wget, reading .env*/.npmrc*/.yarnrc* files, destructive SQL (UPDATE/DELETE/DROP/TRUNCATE/ALTER DROP)"
  jq -cn --arg r "$reason" '{continue: true, permission: "deny", user_message: $r, agent_message: $r}'
  exit 0
fi
# Cursor counts empty stdout as a failed hook, so answer with an empty decision:
# no explicit "allow", leaving any other beforeShellExecution hook free to decide.
echo '{}'
