#!/usr/bin/env bash
# install-herdr-integration.sh — registers herdr's official per-agent
# integration hook (`herdr integration install <kind>`).
#
# Must run AFTER apply-config.sh has written the agent's settings.json —
# same constraint as install_claude_hud in install-agent-extras.sh: the
# integration merges a SessionStart hook into settings.json rather than
# replacing it, so the file needs to exist first.
#
# Called at Docker build time (as the agent user) with:
#   INSTALL_HERDR   true | false   (default false — no-op when false, and
#                   when herdr itself wasn't installed by install-herdr.sh)
#   AGENT           copilot | pi | codex | claude   (matches herdr's
#                   --kind names 1:1)

set -euo pipefail

INSTALL_HERDR="${INSTALL_HERDR:-false}"
if [ "${INSTALL_HERDR}" != "true" ]; then
  echo "[install-herdr-integration] skipped (INSTALL_HERDR=false)"
  exit 0
fi

AGENT="${AGENT:-copilot}"

echo "[install-herdr-integration] herdr integration install ${AGENT}"
herdr integration install "${AGENT}"
herdr integration status | grep "^${AGENT}:"
