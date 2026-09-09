#!/usr/bin/env bash
# install-awscli.sh — installs AWS CLI v2 for the current architecture.
#
# Called at Docker build time (as root) with:
#   INSTALL_AWSCLI   true | false   (default false — no-op when false)
#
# Skipped by default so the base image stays lean; bedrock targets set
# INSTALL_AWSCLI=true unconditionally (see docker-bake.hcl's _bedrock
# target).

set -euo pipefail

INSTALL_AWSCLI="${INSTALL_AWSCLI:-false}"

if [ "${INSTALL_AWSCLI}" != "true" ]; then
  echo "[install-awscli] skipped (INSTALL_AWSCLI=false)"
  exit 0
fi

ARCH=$(uname -m)
case "${ARCH}" in
  x86_64)  URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" ;;
  aarch64) URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" ;;
  *) echo "[install-awscli] ERROR: unsupported arch: ${ARCH}" >&2; exit 1 ;;
esac

echo "[install-awscli] Installing AWS CLI v2 (${ARCH})"
curl -fsSL "${URL}" -o /tmp/awscli.zip
unzip -q /tmp/awscli.zip -d /tmp/aws-install
/tmp/aws-install/aws/install
rm -rf /tmp/awscli.zip /tmp/aws-install
aws --version
