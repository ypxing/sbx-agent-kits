#!/usr/bin/env bash
# write-aws-config.sh — writes ~/.aws/config with an SSO session + profile.
#
# Called at Docker build time (as the agent user, so the file lands in
# their home dir) with:
#   INSTALL_AWSCLI   true | false   (default false — no-op when false)
#   SSO_START_URL    e.g. https://myorg.awsapps.com/start
#   SSO_REGION       e.g. ap-southeast-2
#   SSO_ROLE_NAME    e.g. MyRole
#   SSO_ACCOUNT_ID   e.g. 123456789012
#
# All four SSO_* vars are required when INSTALL_AWSCLI=true; the build
# fails loudly if any is missing.

set -euo pipefail

INSTALL_AWSCLI="${INSTALL_AWSCLI:-false}"

if [ "${INSTALL_AWSCLI}" != "true" ]; then
  echo "[write-aws-config] skipped (INSTALL_AWSCLI=false)"
  exit 0
fi

SSO_START_URL="${SSO_START_URL:-}"
SSO_REGION="${SSO_REGION:-}"
SSO_ROLE_NAME="${SSO_ROLE_NAME:-}"
SSO_ACCOUNT_ID="${SSO_ACCOUNT_ID:-}"

missing=""
[ -z "${SSO_START_URL}"  ] && missing="${missing} SSO_START_URL"
[ -z "${SSO_REGION}"     ] && missing="${missing} SSO_REGION"
[ -z "${SSO_ROLE_NAME}"  ] && missing="${missing} SSO_ROLE_NAME"
[ -z "${SSO_ACCOUNT_ID}" ] && missing="${missing} SSO_ACCOUNT_ID"
if [ -n "${missing}" ]; then
  echo "[write-aws-config] ERROR: required build-args not set:${missing}" >&2
  echo "[write-aws-config] Pass them with --build-arg or set as env vars for docker buildx bake" >&2
  exit 1
fi

mkdir -p "${HOME}/.aws"
printf '[sso-session live]\nsso_start_url = %s\nsso_region = %s\nsso_registration_scopes = sso:account:access\nregion = %s\n\n[profile sso-live]\nsso_session = live\nsso_role_name = %s\nsso_account_id = %s\nregion = %s\n' \
  "${SSO_START_URL}" "${SSO_REGION}" "${SSO_REGION}" \
  "${SSO_ROLE_NAME}" "${SSO_ACCOUNT_ID}" "${SSO_REGION}" \
  > "${HOME}/.aws/config"
echo "[write-aws-config] wrote ~/.aws/config (profile sso-live)"
