#!/usr/bin/env bash
# herdr-entrypoint.sh — sandbox entrypoint, generic across every supported
# agent CLI (copilot | pi | codex | claude). The Dockerfile installs this
# same script under an agent-specific command name (${AGENT}-herdr, e.g.
# claude-herdr, codex-herdr — see the Dockerfile's COPY step and each
# agents/<agent>/spec.yaml.tpl's `entrypoint:`), matching the
# claude-wrapper.sh/copilot-wrapper.sh naming convention. Which agent to
# drive is read from $HERDR_AGENT (baked into the image via the
# Dockerfile's `ENV HERDR_AGENT=${AGENT}`, so it always matches the CLI
# actually installed), not from the invoked command name.
#
# Ensures a herdr server is running (starting one itself if needed — client
# subcommands like `herdr status`/`herdr agent list` do NOT
# lazily spawn one; only the bare `herdr` TUI does, and only under a real
# tty, which headless runs never reach in time). It then starts one `main`
# agent in a fresh pane, and either hands off to the herdr TUI (if a real
# tty is attached) or polls the server to keep the container's lifecycle
# tracking it.
#
# Bare `herdr` needs a real tty and panics without one, so it's only exec'd
# when stdout is a tty (e.g. `docker run -it`). Headless/detached runs skip
# straight to polling the server; runtime access/orchestration then
# happens via `sbx exec -it <sandbox> herdr ...` against this same running
# server — confirmed working against a live sandbox.
#
# herdr itself is an opt-in build (INSTALL_HERDR=true) — this same script
# is always the entrypoint regardless, so a plain (no-herdr) image just
# falls straight through to that agent's own direct "yolo mode" launch
# below.

set -uo pipefail

AGENT="${HERDR_AGENT:-copilot}"

# Each agent's own flag for skipping interactive approval prompts — used
# both for the herdr-less fallback below and for the `herdr agent start`
# invocation further down. pi has none: its baked-in config already sets
# defaultProjectTrust=always (see config/pi/settings.json), so no CLI flag
# is needed.
case "${AGENT}" in
  claude)  YOLO_ARGS=(--dangerously-skip-permissions) ;;
  copilot) YOLO_ARGS=(--yolo) ;;
  codex)   YOLO_ARGS=(--dangerously-bypass-approvals-and-sandbox) ;;
  pi)      YOLO_ARGS=() ;;
  *)
    echo "[herdr-entrypoint] ERROR: unknown \$HERDR_AGENT '${AGENT}'" >&2
    echo "  Supported values: copilot | pi | codex | claude" >&2
    exit 1
    ;;
esac

if ! command -v herdr >/dev/null 2>&1; then
  exec "${AGENT}" "${YOLO_ARGS[@]}"
fi

PROJECT_DIR="$(pwd -P)"
LOG_DIR="${HOME}/.local/state"
mkdir -p "${LOG_DIR}"

# `herdr status` prints YAML (no --json), e.g.:
#   server:
#     status: running
#     ...
# so pull the "status:" line out of the "server:" section specifically,
# rather than relying on the command's exit code.
herdr_server_running() {
  herdr status 2>/dev/null | awk '
    /^[^[:space:]]/ { in_server = 0 }
    /^server:/ { in_server = 1; next }
    in_server && /^[[:space:]]*status:/ { print $2; exit }
  ' | grep -qx running
}

# If some other launcher (e.g. an external setup step running `herdr
# server &` via its own exec path) already started a server, it may have
# resolved this user's gid/groups differently than this entrypoint does —
# dropping supplementary groups like `docker` entirely. Detect that and
# restart the server so it ends up spawned fresh under *this* process's
# credentials instead.
docker_gid="$(getent group docker 2>/dev/null | cut -d: -f3 || true)"
if [ -n "${docker_gid}" ] && herdr_server_running; then
  server_pid="$(pgrep -f '(^|/)herdr server$' | head -1)"
  if [ -n "${server_pid}" ] && [ -r "/proc/${server_pid}/status" ] \
     && ! grep -E '^(Gid|Groups):' "/proc/${server_pid}/status" | grep -qw "${docker_gid}"; then
    echo "[herdr-entrypoint] existing herdr server (pid ${server_pid}) is missing the docker group; restarting it" >&2
    herdr server stop >/dev/null 2>&1 || true
    for _ in $(seq 1 25); do
      herdr_server_running || break
      sleep 0.2
    done
  fi
fi

# Client subcommands never spawn a server on their own, so start one
# explicitly if nothing is running at this point (whether none was ever
# started, or the bad one above was just stopped). Runs under this
# process's own credentials, which are resolved correctly.
if ! herdr_server_running; then
  echo "[herdr-entrypoint] starting herdr server" >&2
  herdr server >"${LOG_DIR}/herdr-server.log" 2>&1 &
  disown
fi

echo "[herdr-entrypoint] waiting for herdr server"
for _ in $(seq 1 50); do
  herdr_server_running && break
  sleep 0.2
done

if ! herdr_server_running; then
  echo "[herdr-entrypoint] ERROR: herdr server did not start within 10s; falling back to direct ${AGENT} launch" >&2
  exec "${AGENT}" "${YOLO_ARGS[@]}"
fi

if herdr agent list 2>/dev/null | jq -e '.result.agents[] | select(.name == "main")' >/dev/null 2>&1; then
  echo "[herdr-entrypoint] agent 'main' already running, skipping bootstrap"
else
  echo "[herdr-entrypoint] bootstrapping workspace + main ${AGENT} agent in ${PROJECT_DIR}"
  pane_id=$(herdr workspace create --cwd "${PROJECT_DIR}" --label main --no-focus | jq -r '.result.root_pane.pane_id // empty')
  if [ -z "${pane_id}" ]; then
    echo "[herdr-entrypoint] WARNING: workspace create failed; skipping agent start" >&2
  else
    # `herdr agent start` blocks up to --timeout waiting for interactive
    # readiness (60s here) — run it in the background so a tty-attached
    # caller reaches the TUI handoff below immediately instead of staring
    # at a blank screen for up to a minute. The pane's real-time output
    # (visible in the TUI, or in the log below) shows the agent booting
    # either way; this only removes an artificial wait before that's
    # visible.
    (
      if herdr agent start main --kind "${AGENT}" --pane "${pane_id}" --timeout 60000 -- "${YOLO_ARGS[@]}"; then
        echo "[herdr-entrypoint] agent 'main' ready"
      else
        echo "[herdr-entrypoint] WARNING: agent start failed or timed out; server still up for manual retry via 'sbx exec'"
      fi
    ) >>"${LOG_DIR}/herdr-agent-main.log" 2>&1 &
    disown
  fi
fi

if [ -t 1 ]; then
  echo "[herdr-entrypoint] tty attached, handing off to herdr TUI"
  exec herdr
fi

echo "[herdr-entrypoint] headless; tracking server lifecycle"
while herdr_server_running; do
  sleep 5
done
echo "[herdr-entrypoint] herdr server is no longer running, exiting" >&2
