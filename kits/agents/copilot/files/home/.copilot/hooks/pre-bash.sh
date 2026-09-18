#!/usr/bin/env bash
input=$(cat)
# Copilot sends toolArgs (camelCase) or tool_input (PascalCase)
cmd=$(echo "$input" | jq -r '(try (.toolArgs | fromjson | .command) // .tool_input.command) // empty' 2>/dev/null) || cmd=""

# shellcheck source=pre-bash-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/pre-bash-common.sh"

if pre_bash_command_blocked "$cmd"; then
  printf '{"permissionDecision":"deny","permissionDecisionReason":"Blocked: make *deploy*, git push to main/master, non-read-only aws commands (only describe-/list-/get-/head-/lookup-/search-/query/scan/tail/ls are allowed), docker compose *deploy*, rm -rf, wget, reading .env/.npmrc/.yarnrc files, destructive SQL (UPDATE/DELETE/DROP/TRUNCATE/ALTER DROP)"}\n'
fi
# Otherwise stay silent (no explicit "allow") so any other PreToolUse hook can
# still return its own decision.
