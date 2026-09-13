#!/usr/bin/env bash
# apply-config.sh — copies the agent-specific settings + hooks from
# /tmp/agent-configs/<agent>/ into the correct home-dir location.
#
# Agent → home dir mapping:
#   copilot  → ~/.copilot/
#   pi       → ~/.pi/agent/   (pi nests its config under an `agent/` subdir;
#                             see the kits/mixins/agent-packages/ mixin kit,
#                             which writes `pi install` packages to
#                             ~/.pi/agent/settings.json at sandbox-creation
#                             time)
#   codex    → ~/.codex/
#   claude   → ~/.claude/
#
# AWS Bedrock model-routing config is not baked in here — it's layered on
# top at sandbox-creation time by the kits/mixins/aws/ mixin kit (`--kit-arg
# use_bedrock=true`), since it needs AWS credentials to be useful anyway and
# those already only get applied at that point (see README's "Optional: AWS
# / Bedrock auth" section).

set -euo pipefail

AGENT="${AGENT:-copilot}"
SRC="/tmp/agent-configs/${AGENT}"

if [ ! -d "${SRC}" ]; then
  echo "[apply-config] ERROR: no config directory found for agent '${AGENT}' at ${SRC}" >&2
  exit 1
fi

case "${AGENT}" in
  copilot)        DEST="${HOME}/.copilot" ;;
  pi)             DEST="${HOME}/.pi/agent" ;;
  codex)          DEST="${HOME}/.codex"   ;;
  claude)         DEST="${HOME}/.claude"  ;;
  *)
    echo "[apply-config] ERROR: unknown agent '${AGENT}'" >&2
    exit 1
    ;;
esac

echo "[apply-config] ${SRC} → ${DEST}"
mkdir -p "${DEST}"
cp -r "${SRC}/." "${DEST}/"

# Hooks share a common guardrail library (config/common/pre-bash-common.sh) —
# each agent's pre-bash.sh sources it by relative path, so it must land
# alongside them. Then make every file in hooks/ executable.
if [ -d "${DEST}/hooks" ]; then
  cp "$(dirname "$0")/common/pre-bash-common.sh" "${DEST}/hooks/pre-bash-common.sh"
  chmod +x "${DEST}/hooks/"*.sh 2>/dev/null || true
fi

echo "[apply-config] Done"
