#!/usr/bin/env bash
# apply-config.sh — copies the agent-specific settings + hooks from
# /tmp/agent-configs/<agent>/ into the correct home-dir location.
#
# Agent → home dir mapping:
#   copilot  → ~/.copilot/
#   pi       → ~/.pi/agent/   (pi nests its config under an `agent/` subdir;
#                             see install-agent-extras.sh, which writes
#                             `pi install` packages to ~/.pi/agent/settings.json)
#   codex    → ~/.codex/
#   claude   → ~/.claude/
#
# When PROVIDER=bedrock, the base settings above are layered with a patch
# from /tmp/agent-configs/<agent>-bedrock/ (jq deep merge for settings.json,
# TOML splice for config.toml). PROVIDER=standard (the default) copies the
# base config only.

set -euo pipefail

AGENT="${AGENT:-copilot}"
PROVIDER="${PROVIDER:-standard}"
SRC="/tmp/agent-configs/${AGENT}"

if [ ! -d "${SRC}" ]; then
  echo "[apply-config] ERROR: no config directory found for agent '${AGENT}' at ${SRC}" >&2
  exit 1
fi

# apply_patch BASE_DIR PATCH_DIR DEST_DIR
#   Copies BASE_DIR into DEST_DIR, then layers PATCH_DIR on top:
#     - settings.json (JSON): deep-merged onto the base settings.json with
#                             jq. Objects merge recursively; arrays are
#                             concatenated + de-duplicated (patch entries
#                             are additive, e.g. one more allowed command).
#     - config.toml (TOML):   jq/JSON tools can't parse TOML, so instead of
#                             a real merge we splice the patch onto the base
#                             file. TOML requires all root-level (bare)
#                             key/values to appear before the first [table]
#                             header in the document, so a naive append
#                             would silently nest the patch's root keys
#                             inside whatever table the base file left open
#                             last. To stay valid we split each file into
#                             its "preamble" (root scalars, before the first
#                             line starting with '[') and its "tables" (from
#                             that line on), then emit: base preamble, patch
#                             preamble, base tables, patch tables. This
#                             assumes single-line values only (no multi-line
#                             arrays/strings starting a line with '['), which
#                             holds for these configs. Base and patch must
#                             still define disjoint keys/tables -- TOML
#                             hard-errors on a duplicate key, so silent
#                             drift isn't possible; a real overlap just
#                             fails the build loudly.
#     - anything else (hooks, etc.): overlaid as a plain file copy.
apply_patch() {
  local base_src="$1" patch_src="$2" dest="$3"
  mkdir -p "${dest}"
  cp -r "${base_src}/." "${dest}/"

  if [ -f "${patch_src}/settings.json" ]; then
    jq -s '
      def deepmerge($a; $b):
        if ($a|type) == "object" and ($b|type) == "object" then
          reduce ($b|keys_unsorted[]) as $k ($a; .[$k] = (if ($a[$k]? != null) then deepmerge($a[$k]; $b[$k]) else $b[$k] end))
        elif ($a|type) == "array" and ($b|type) == "array" then ($a + $b | unique)
        else $b end;
      deepmerge(.[0]; .[1])
    ' "${dest}/settings.json" "${patch_src}/settings.json" \
      > "${dest}/settings.json.tmp" \
      && mv "${dest}/settings.json.tmp" "${dest}/settings.json"
  fi

  if [ -f "${patch_src}/config.toml" ]; then
    dest_toml="${dest}/config.toml"
    patch_toml="${patch_src}/config.toml"
    [ -f "${dest_toml}" ] || : > "${dest_toml}"

    toml_preamble() { awk '/^\[/{exit} {print}' "$1"; }
    toml_tables()   { awk 'BEGIN{f=0} /^\[/{f=1} f{print}' "$1"; }

    merged="${dest_toml}.tmp"
    {
      toml_preamble "${dest_toml}"
      printf '# --- %s patch ---\n' "$(basename "${patch_src}")"
      toml_preamble "${patch_toml}"
      toml_tables "${dest_toml}"
      printf '\n# --- %s patch (tables) ---\n' "$(basename "${patch_src}")"
      toml_tables "${patch_toml}"
    } > "${merged}"
    mv "${merged}" "${dest_toml}"
  fi

  # overlay any extra files the patch variant ships (hooks, etc.), skipping
  # the settings files already merged above
  find "${patch_src}" -not -name "settings.json" -not -name "config.toml" -not -type d \
    | while IFS= read -r f; do
        rel="${f#${patch_src}/}"
        mkdir -p "${dest}/$(dirname "${rel}")"
        cp "${f}" "${dest}/${rel}"
      done
}

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

if [ "${PROVIDER}" = "bedrock" ]; then
  PATCH_SRC="/tmp/agent-configs/${AGENT}-bedrock"
  if [ ! -d "${PATCH_SRC}" ]; then
    echo "[apply-config] ERROR: PROVIDER=bedrock but no patch dir at ${PATCH_SRC}" >&2
    exit 1
  fi
  echo "[apply-config] ${AGENT} + bedrock patch → ${DEST}"
  apply_patch "${SRC}" "${PATCH_SRC}" "${DEST}"
else
  echo "[apply-config] ${SRC} → ${DEST}"
  mkdir -p "${DEST}"
  cp -r "${SRC}/." "${DEST}/"
fi

# Hooks share a common guardrail library (config/common/pre-bash-common.sh) —
# each agent's pre-bash.sh sources it by relative path, so it must land
# alongside them. Then make every file in hooks/ executable.
if [ -d "${DEST}/hooks" ]; then
  cp "$(dirname "$0")/common/pre-bash-common.sh" "${DEST}/hooks/pre-bash-common.sh"
  chmod +x "${DEST}/hooks/"*.sh 2>/dev/null || true
fi

echo "[apply-config] Done"
