#!/usr/bin/env bash
# install-herdr.sh — installs a pinned version of the herdr terminal
# multiplexer / agent automation CLI (https://herdr.dev) into the agent
# user's ~/.local/bin, which is already first on PATH in the base sandbox
# image.
#
# Downloads directly from the versioned GitHub release asset and verifies
# its SHA-256, bypassing herdr.dev/install.sh's "always latest" resolution
# (that script only ever reads latest.json, with no version-pinning
# option). This mirrors how CLAUDE_HUD_VERSION pins claude-hud: herdr is a
# supporting tool, not the agent CLI itself, so reproducibility wins over
# always-latest here.
#
# Called at Docker build time with:
#   INSTALL_HERDR   true | false   (default false — no-op when false)
#   HERDR_VERSION   e.g. 0.8.2 (default below)
#
# To bump: pick a new version, then look up its per-arch sha256 from
# https://herdr.dev/latest.json (the top-level "releases" map has one
# entry per past version, same shape as the top-level "assets"/"sha256"
# keys) and update HERDR_SHA256_* below to match.

set -euo pipefail

INSTALL_HERDR="${INSTALL_HERDR:-false}"
if [ "${INSTALL_HERDR}" != "true" ]; then
  echo "[install-herdr] skipped (INSTALL_HERDR=false)"
  exit 0
fi

HERDR_VERSION="${HERDR_VERSION:-0.8.2}"
HERDR_SHA256_X86_64="976150a14d490c94b243ea2e1a7eb2dfb67f12e36b182db90936f6728e6aecf4"
HERDR_SHA256_AARCH64="f55610658e1c2e0d2aaef730b4b2ab885f7f8ba00285ab372bfb14f2e3d5b40d"
INSTALL_DIR="${HOME}/.local/bin"

ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64)  asset="herdr-linux-x86_64";  expected_sha256="${HERDR_SHA256_X86_64}" ;;
  aarch64) asset="herdr-linux-aarch64"; expected_sha256="${HERDR_SHA256_AARCH64}" ;;
  *) echo "[install-herdr] ERROR: unsupported arch: ${ARCH}" >&2; exit 1 ;;
esac

URL="https://github.com/herdrdev/herdr/releases/download/v${HERDR_VERSION}/${asset}"
echo "[install-herdr] Installing herdr v${HERDR_VERSION} (${ARCH})"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
curl -fsSL --retry 3 --connect-timeout 10 --max-time 120 "${URL}" -o "${TMP}/herdr"

actual_sha256="$(sha256sum "${TMP}/herdr" | awk '{ print $1 }')"
if [ "${actual_sha256}" != "${expected_sha256}" ]; then
  echo "[install-herdr] ERROR: checksum mismatch for ${asset} v${HERDR_VERSION}" >&2
  echo "  expected: ${expected_sha256}" >&2
  echo "  actual:   ${actual_sha256}" >&2
  exit 1
fi

mkdir -p "${INSTALL_DIR}"
mv "${TMP}/herdr" "${INSTALL_DIR}/herdr"
chmod +x "${INSTALL_DIR}/herdr"

herdr --version
