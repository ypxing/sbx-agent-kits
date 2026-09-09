#!/usr/bin/env bash
# write-herdr-config.sh — writes ~/.config/herdr/config.toml from the
# static config baked into the image at build time (see
# config/herdr/config.toml for the settings and why).
#
# Called at Docker build time (as the agent user, so the file lands in
# their home dir) with:
#   INSTALL_HERDR   true | false   (default false — no-op when false, and
#                   when herdr itself wasn't installed by install-herdr.sh)
#
# Expects config/herdr/config.toml to already be staged at
# /tmp/herdr-config.toml (see Dockerfile COPY).

set -euo pipefail

INSTALL_HERDR="${INSTALL_HERDR:-false}"
if [ "${INSTALL_HERDR}" != "true" ]; then
  echo "[write-herdr-config] skipped (INSTALL_HERDR=false)"
  exit 0
fi

SRC="/tmp/herdr-config.toml"
DEST="${HOME}/.config/herdr/config.toml"

mkdir -p "$(dirname "${DEST}")"
cp "${SRC}" "${DEST}"
echo "[write-herdr-config] wrote ${DEST}"
