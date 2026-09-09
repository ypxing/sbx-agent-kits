#!/usr/bin/env bash
# install-agent-extras.sh — post-config, agent-specific installs (statusline
# plugins, pre-installed packages, etc.), dispatched by $AGENT like
# install-agent.sh dispatches the CLI install itself.
#
# Must run AFTER apply-config.sh has written the agent's settings/config —
# claude's branch merges into ~/.claude/settings.json rather than replacing
# it, so config needs to already exist:
# `claude plugin install` merges `extraKnownMarketplaces` and
# `enabledPlugins` into whatever settings.json already exists, but
# apply-config.sh's own copy step (`cp -r`) fully overwrites settings.json.
# Running this first would have apply-config.sh clobber the plugin
# registration; running it after means the merge lands on top of our
# baked-in settings instead.
#
# Called at Docker build time (as the agent user) with:
#   AGENT                copilot | pi | codex | claude   (selects the branch below)
#   CLAUDE_HUD_VERSION   git tag of jarrodwatts/claude-hud to pin (e.g. v0.8.0,
#                        only used by the claude branch)

set -euo pipefail

AGENT="${AGENT:-copilot}"

# ── claude: install the claude-hud statusline plugin ────────────────────────
# (https://github.com/jarrodwatts/claude-hud), non-interactively via Claude
# Code's own plugin CLI.
#
# `claude plugin install` copies the plugin into a version-namespaced cache
# dir (~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/), so
# config/claude/settings.json ships a placeholder --
# __CLAUDE_HUD_VERSION__ -- in statusLine.command instead of a real path.
# This discovers the actual installed version directory and substitutes it
# in, giving a static (non-glob) statusline command that's fully known at
# image-build time.
install_claude_hud() {
  local version="${CLAUDE_HUD_VERSION:-v0.8.0}"
  local settings="${HOME}/.claude/settings.json"

  echo "[install-agent-extras] Adding claude-hud marketplace @ ${version}"
  claude plugin marketplace add "https://github.com/jarrodwatts/claude-hud.git#${version}"

  echo "[install-agent-extras] Installing claude-hud plugin"
  claude plugin install claude-hud@claude-hud

  local cache_root="${HOME}/.claude/plugins/cache/claude-hud/claude-hud"
  local installed_dir
  installed_dir=$(find "${cache_root}" -mindepth 1 -maxdepth 1 -type d | head -1)
  if [ -z "${installed_dir}" ] || [ ! -f "${installed_dir}/dist/index.js" ]; then
    echo "[install-agent-extras] ERROR: couldn't find dist/index.js under ${cache_root}" >&2
    exit 1
  fi
  local installed_version
  installed_version="$(basename "${installed_dir}")"
  echo "[install-agent-extras] Installed version: ${installed_version} (${installed_dir})"

  if [ ! -f "${settings}" ]; then
    echo "[install-agent-extras] ERROR: ${settings} not found — run apply-config.sh first" >&2
    exit 1
  fi

  sed -i.bak "s/__CLAUDE_HUD_VERSION__/${installed_version}/" "${settings}"
  rm -f "${settings}.bak"
}

# ── pi: pre-install pi packages ─────────────────────────────────────────────
# `pi install` is a non-interactive CLI subcommand (no TUI). It installs the
# package under ~/.pi/agent/npm/ and registers it in ~/.pi/agent/settings.json.
install_pi_packages() {
  local pkg
  for pkg in pi-mcp-adapter pi-web-access pi-subagents; do
    echo "[install-agent-extras] pi install npm:${pkg}"
    pi install "npm:${pkg}"
  done
}

case "${AGENT}" in
  claude) install_claude_hud ;;
  pi)     install_pi_packages ;;
  *)      echo "[install-agent-extras] nothing to do for ${AGENT}" ;;
esac

echo "[install-agent-extras] Done: ${AGENT}"
