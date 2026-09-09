#!/usr/bin/env bash
# scripts/gen-specs.sh — materialise agents/*/spec.yaml from *.tpl files.
#
# Resolves image references and writes a ready-to-use spec.yaml next to each
# template.  Commit the generated files so `sbx` works out of the box for
# anyone who clones the repo; re-run this script whenever you want to switch
# images.
#
# ── Variables ────────────────────────────────────────────────────────────────
#
#   SBX_IMAGE_REGISTRY   Registry prefix shared by all agents.
#                        Default: docker/sandbox-templates
#                        Change this to point every kit at your own registry
#                        in one shot:
#                          SBX_IMAGE_REGISTRY=my.registry.io ./scripts/gen-specs.sh
#                        → images become my.registry.io/pi:latest,
#                          my.registry.io/claude:latest, …
#
#   SBX_<AGENT>_IMAGE    Full image reference for one specific agent.
#                        Takes precedence over SBX_IMAGE_REGISTRY for that
#                        agent only.
#                          SBX_PI_IMAGE=ghcr.io/myorg/pi:v2 ./scripts/gen-specs.sh
#
# Precedence (per agent):
#   SBX_<AGENT>_IMAGE  >  ${SBX_IMAGE_REGISTRY}/<agent>:latest  >  upstream ECR default
#
# Requires: envsubst (part of the gettext package)
#   macOS:  brew install gettext
#   Debian: apt-get install gettext-base

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="${SCRIPT_DIR}/../agents"

if ! command -v envsubst &>/dev/null; then
  echo "[gen-specs] ERROR: envsubst not found." >&2
  echo "  macOS:  brew install gettext" >&2
  echo "  Debian: apt-get install gettext-base" >&2
  exit 1
fi

# Resolve defaults in bash first; templates use plain ${SBX_*} with no
# inline fallback syntax (envsubst only does simple substitution).
: "${SBX_IMAGE_REGISTRY:=docker/sandbox-templates}"
: "${SBX_PI_IMAGE:=${SBX_IMAGE_REGISTRY}:shell-docker}"
: "${SBX_CLAUDE_IMAGE:=${SBX_IMAGE_REGISTRY}:claude-docker}"
: "${SBX_CODEX_IMAGE:=${SBX_IMAGE_REGISTRY}:codex-docker}"
: "${SBX_COPILOT_IMAGE:=${SBX_IMAGE_REGISTRY}:copilot-docker}"

export SBX_IMAGE_REGISTRY SBX_PI_IMAGE SBX_CLAUDE_IMAGE SBX_CODEX_IMAGE SBX_COPILOT_IMAGE

# Only substitute the vars we own; leave any other $… in YAML untouched.
VARS='${SBX_PI_IMAGE}${SBX_CLAUDE_IMAGE}${SBX_CODEX_IMAGE}${SBX_COPILOT_IMAGE}'

for tpl in "${AGENTS_DIR}"/*/spec.yaml.tpl; do
  out="${tpl%.tpl}"
  envsubst "${VARS}" < "${tpl}" > "${out}"
  agent_path="${tpl#${AGENTS_DIR}/}"          # e.g. pi/spec.yaml.tpl
  image=$(grep 'image:' "${out}" | awk '{print $2}')
  echo "[gen-specs] ${agent_path%.tpl} ← ${image}"
done

echo "[gen-specs] Done — commit agents/*/spec.yaml to lock in these images."
