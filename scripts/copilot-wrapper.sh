#!/usr/bin/env bash
# copilot — wrapper around the real copilot binary.
#
# Written to PATH by install-agent.sh (which moves the npm-installed `copilot`
# to `copilot.real` and drops this file in its place).
#
# Purpose: pre-trust the sbx working directory in ~/.copilot/config.json
# before the Copilot agent UI starts. The `trustedFolders` key in that file
# must contain the *resolved* working directory; sbx mirrors the host's
# literal path into the container, so the path is unknown at image-build time
# and must be patched at start time (same reason claude-wrapper.sh exists).
set -euo pipefail

COPILOT_CONFIG="${HOME}/.copilot/config.json"
PROJECT_DIR="$(pwd -P)"

_patch_trust() {
  local tmp
  mkdir -p "$(dirname "${COPILOT_CONFIG}")"
  tmp="$(mktemp "${COPILOT_CONFIG}.XXXXXX")"
  if [ -f "${COPILOT_CONFIG}" ]; then
    # config.json is "managed automatically" by copilot itself and starts
    # with `//`-style comment lines once copilot has written to it, which
    # jq's strict JSON parser rejects outright. Strip those before merging.
    # An empty/blank file (e.g. left behind by a past version of this
    # script that clobbered it on a jq failure) has no JSON value for jq to
    # operate on and would silently produce no output — treat it as `{}`
    # instead, self-healing that corruption. Bail out (without touching
    # the real file) if the merge still fails for any other reason — jq
    # writing nothing to `tmp` must never become the `mv` below
    # overwriting a good config with an empty one.
    local stripped
    stripped="$(grep -v '^[[:space:]]*//' "${COPILOT_CONFIG}")"
    if [ -z "${stripped//[[:space:]]/}" ]; then
      stripped='{}'
    fi
    if ! printf '%s' "${stripped}" \
       | jq --arg dir "${PROJECT_DIR}" '
           .trustedFolders = ((.trustedFolders // []) + [$dir] | unique)
         ' > "${tmp}"; then
      rm -f "${tmp}"
      return 1
    fi
  else
    jq -n --arg dir "${PROJECT_DIR}" '{
      trustedFolders: [$dir]
    }' > "${tmp}" || { rm -f "${tmp}"; return 1; }
  fi
  mv "${tmp}" "${COPILOT_CONFIG}"
  chmod 600 "${COPILOT_CONFIG}"
}

# Never let a patch failure block the session — worst case the trust prompt
# appears once, same as without this wrapper.
_patch_trust || echo "[copilot] WARNING: could not pre-trust ${PROJECT_DIR}; continuing" >&2

exec copilot.real "$@"
