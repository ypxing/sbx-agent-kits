#!/usr/bin/env bash
# install-agent.sh — installs the latest agent CLI selected by $AGENT.
#
# Called at Docker build time with:
#   AGENT=<copilot|pi|codex|claude>
#
# Each branch installs the agent CLI at its latest published version.
# Whether it ends up routing through AWS Bedrock is decided later, at
# sandbox-creation time, by the kits/mixins/aws/ mixin kit — not here.
# coding-crew skills are likewise applied later, via the
# kits/mixins/coding-crew/ mixin kit — not baked in here.

set -euo pipefail

AGENT="${AGENT:-copilot}"

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
    # Claude HUD (statusline plugin) is not baked in — apply it at
    # sandbox-creation time via the kits/mixins/agent-packages/ mixin kit.
    ;;

  *)
    echo "[install-agent] ERROR: unknown agent '${AGENT}'" >&2
    echo "  Supported values: copilot | pi | codex | claude" >&2
    exit 1
    ;;
esac

echo "[install-agent] Done: ${AGENT}"

