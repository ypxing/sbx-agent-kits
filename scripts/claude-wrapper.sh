#!/usr/bin/env bash
# claude — wrapper around the real claude.real binary.
#
# Written to PATH by install-agent.sh (which moves the npm-installed `claude`
# to `claude.real` and drops this file in its place).
#
# Purpose: pre-trust the sbx working directory in ~/.claude.json before the
# Claude Code UI starts. Required because --dangerously-skip-permissions does
# NOT suppress the "trust this folder?" dialog — that check is separate from
# tool permissions. sbx mirrors the host's literal path into the container, so
# the path is unknown at image-build time and must be patched at start time.
set -euo pipefail

CLAUDE_JSON="${HOME}/.claude.json"
PROJECT_DIR="$(pwd -P)"

_patch_trust() {
  local tmp
  tmp="$(mktemp "${CLAUDE_JSON}.XXXXXX")"
  # `_patch_trust || echo WARNING` below means bash's `-e` doesn't apply to
  # anything in this function, so a failing jq wouldn't otherwise stop
  # execution at the `mv` below — it would overwrite a good/existing
  # ${CLAUDE_JSON} with jq's empty output. Check its exit status explicitly
  # and bail without touching the real file instead.
  if [ -f "${CLAUDE_JSON}" ]; then
    if ! jq --arg dir "${PROJECT_DIR}" '
      .hasCompletedOnboarding = true
      | .projects[$dir].hasTrustDialogAccepted        = true
      | .projects[$dir].hasCompletedProjectOnboarding = true
      | .projects[$dir].projectOnboardingSeenCount    = (.projects[$dir].projectOnboardingSeenCount // 0)
      | .projects[$dir].allowedTools                  = (.projects[$dir].allowedTools // [])
    ' "${CLAUDE_JSON}" > "${tmp}"; then
      rm -f "${tmp}"
      return 1
    fi
  else
    jq -n --arg dir "${PROJECT_DIR}" '{
      hasCompletedOnboarding: true,
      projects: { ($dir): {
        hasTrustDialogAccepted:        true,
        hasCompletedProjectOnboarding: true,
        projectOnboardingSeenCount:    0,
        allowedTools:                  []
      }}
    }' > "${tmp}" || { rm -f "${tmp}"; return 1; }
  fi
  mv "${tmp}" "${CLAUDE_JSON}"
  chmod 600 "${CLAUDE_JSON}"
}

# Never let a patch failure block the session — worst case the trust prompt
# appears once, same as without this wrapper.
_patch_trust || echo "[claude] WARNING: could not pre-trust ${PROJECT_DIR}; continuing" >&2

exec claude.real "$@"
