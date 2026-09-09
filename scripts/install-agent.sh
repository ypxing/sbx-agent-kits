#!/usr/bin/env bash
# install-agent.sh — installs the latest agent CLI selected by $AGENT.
#
# Called at Docker build time with:
#   AGENT=<copilot|pi|codex|claude>
#
# AGENT names the CLI only — the auth/routing backend (standard vs bedrock)
# is a separate PROVIDER build-arg that never changes which package gets
# installed here, only which config gets layered on later by
# apply-config.sh. Each branch installs the agent CLI at its latest
# published version. coding-crew skills are optional and installed
# separately.

set -euo pipefail

AGENT="${AGENT:-copilot}"
INSTALL_CODING_CREW="${INSTALL_CODING_CREW:-false}"
CODING_CREW_VERSION="${CODING_CREW_VERSION:-latest}"
BOOTSTRAP_URL="https://raw.githubusercontent.com/ypxing/coding-crew/main/bootstrap.sh"

echo "[install-agent] Installing agent: ${AGENT}"

case "${AGENT}" in

  # ── GitHub Copilot ────────────────────────────────────────────────────────
  copilot)
    npm install -g @github/copilot
    # Move the real binary to `copilot.real` and install the wrapper as
    # `copilot`. The wrapper pre-trusts the sbx working directory in
    # ~/.copilot/config.json at start time. See scripts/copilot-wrapper.sh.
    COPILOT_BIN="$(command -v copilot)"
    mv "${COPILOT_BIN}" "${COPILOT_BIN}.real"
    cp /tmp/copilot-wrapper.sh "${COPILOT_BIN}"
    chmod +x "${COPILOT_BIN}"
    ;;

  # ── Pi coding agent (npm) ─────────────────────────────────────────────────
  pi)
    npm install -g @earendil-works/pi-coding-agent
    ;;

  # ── OpenAI Codex CLI (npm) ────────────────────────────────────────────────
  codex)
    npm install -g @openai/codex
    ;;

  # ── Anthropic Claude Code (npm) ───────────────────────────────────────────
  claude)
    npm install -g @anthropic-ai/claude-code
    # Move the real binary to `claude.real` and install the wrapper as
    # `claude`. The wrapper pre-trusts the sbx working directory in
    # ~/.claude.json at start time (--dangerously-skip-permissions does NOT
    # suppress the trust dialog). See scripts/claude-wrapper.sh for details.
    CLAUDE_BIN="$(command -v claude)"
    mv "${CLAUDE_BIN}" "${CLAUDE_BIN}.real"
    cp /tmp/claude-wrapper.sh "${CLAUDE_BIN}"
    chmod +x "${CLAUDE_BIN}"
    # Claude HUD (statusline plugin) is installed later, by
    # install-agent-extras.sh, after apply-config.sh has written the base
    # settings.json — see that script for why.
    ;;

  *)
    echo "[install-agent] ERROR: unknown agent '${AGENT}'" >&2
    echo "  Supported values: copilot | pi | codex | claude" >&2
    exit 1
    ;;
esac

# ── Optional: coding-crew skills ────────────────────────────────────────────
if [ "${INSTALL_CODING_CREW}" = "true" ]; then
  echo "[install-agent] Installing coding-crew skills (${AGENT} @ ${CODING_CREW_VERSION})"
  curl -fsSL "${BOOTSTRAP_URL}" \
    | bash -s -- "${AGENT}" --version "${CODING_CREW_VERSION}"
fi

echo "[install-agent] Done: ${AGENT}"

