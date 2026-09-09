# Universal agent sandbox template
#
# Starts from the minimal Docker sandbox base (shell or shell-docker) and
# installs exactly one agent CLI at build time — no runtime setup step needed.
#
# ARGs
#   AGENT         copilot | pi | codex | claude   (which CLI to install)
#   PROVIDER      standard | bedrock               (auth/routing backend; only
#                 changes which config patch is layered on — the CLI install
#                 itself is identical either way)
#   BASE_VARIANT  shell | shell-docker              (controls Docker-in-Docker support)
#   INSTALL_CODING_CREW  true | false  (default false) — install coding-crew skills after the CLI
#   CODING_CREW_VERSION   version tag passed to the coding-crew bootstrap (default latest)
#   CLAUDE_HUD_VERSION    git tag of jarrodwatts/claude-hud to bake in for the claude
#                         agent's statusline (default v0.8.0, ignored for other agents)
#   INSTALL_HERDR         true | false  (default false) — install herdr.dev and switch
#                         the sandbox entrypoint to boot it (see
#                         scripts/herdr-entrypoint.sh); false keeps the classic
#                         direct `$AGENT` launch
#   HERDR_VERSION         pinned herdr.dev release to install when INSTALL_HERDR=true
#                         (default 0.8.2, no leading "v" — see scripts/install-herdr.sh
#                         to bump)
#
# Image naming: the repository name is the agent only (pi, codex, claude,
# copilot). PROVIDER and BASE_VARIANT are encoded in the tag instead:
#   <agent>:latest            standard provider, shell base
#   <agent>:docker             standard provider, shell-docker base
#   <agent>:bedrock            bedrock provider,  shell base
#   <agent>:bedrock-docker      bedrock provider,  shell-docker base
# (copilot has no bedrock backend, so it only ever gets :latest / :docker)
#
# Quick builds:
#   docker build \
#     --build-arg AGENT=copilot \
#     -t copilot:latest \
#     .
#
#   docker build \
#     --build-arg BASE_VARIANT=shell-docker \
#     --build-arg AGENT=claude \
#     --build-arg PROVIDER=bedrock \
#     --build-arg INSTALL_AWSCLI=true \
#     -t claude:bedrock-docker \
#     .
#
# Build the full matrix in parallel:
#   docker buildx bake

ARG BASE_VARIANT=shell-docker
FROM docker/sandbox-templates:${BASE_VARIANT}

# Re-declare ARGs after FROM (Docker requirement)
ARG AGENT=copilot
ARG PROVIDER=standard
ARG INSTALL_CODING_CREW=false
ARG CODING_CREW_VERSION=latest
ARG CLAUDE_HUD_VERSION=v0.8.0
ARG INSTALL_HERDR=false
ARG HERDR_VERSION=0.8.2
ARG INSTALL_AWSCLI=false
# AWS SSO config — written to ~/.aws/config when INSTALL_AWSCLI=true.
# All four vars are required when INSTALL_AWSCLI=true; the build fails if any is missing.
#   --build-arg SSO_START_URL=https://myorg.awsapps.com/start
#   --build-arg SSO_REGION=ap-southeast-2
#   --build-arg SSO_ROLE_NAME=MyRole
#   --build-arg SSO_ACCOUNT_ID=123456789012
ARG SSO_START_URL=""
ARG SSO_REGION=""
ARG SSO_ROLE_NAME=""
ARG SSO_ACCOUNT_ID=""

USER agent
# ── 1. Install the agent CLI ─────────────────────────────────────────────────
# claude-wrapper.sh is staged to /tmp so install-agent.sh can place it as
# the `claude` command (renaming the real binary to `claude.real`).
COPY --chown=1000:1000 scripts/install-agent.sh   /tmp/install-agent.sh
COPY --chown=1000:1000 scripts/claude-wrapper.sh  /tmp/claude-wrapper.sh
COPY --chown=1000:1000 scripts/copilot-wrapper.sh /tmp/copilot-wrapper.sh
RUN chmod +x /tmp/install-agent.sh /tmp/claude-wrapper.sh /tmp/copilot-wrapper.sh \
 && AGENT=${AGENT} INSTALL_CODING_CREW=${INSTALL_CODING_CREW} CODING_CREW_VERSION=${CODING_CREW_VERSION} /tmp/install-agent.sh \
 && rm /tmp/install-agent.sh /tmp/claude-wrapper.sh

# ── 1.5 Optionally install herdr ─────────────────────────────────────────────
# Terminal multiplexer / agent-automation CLI (https://herdr.dev). Opt-in via
# INSTALL_HERDR=true; the script no-ops otherwise. Used by
# scripts/herdr-entrypoint.sh to boot a headless server and start the
# interactive $AGENT agent (copilot | pi | codex | claude) in a managed pane.
COPY --chown=1000:1000 scripts/install-herdr.sh /tmp/install-herdr.sh
RUN chmod +x /tmp/install-herdr.sh \
 && INSTALL_HERDR=${INSTALL_HERDR} HERDR_VERSION=${HERDR_VERSION} /tmp/install-herdr.sh \
 && rm /tmp/install-herdr.sh

# Sandbox-sensible defaults for herdr itself (onboarding, update checks,
# sound — see config/herdr/config.toml for the full rationale), written to
# ~/.config/herdr/config.toml. No-ops when INSTALL_HERDR=false.
COPY --chown=1000:1000 config/herdr/config.toml   /tmp/herdr-config.toml
COPY --chown=1000:1000 scripts/write-herdr-config.sh /tmp/write-herdr-config.sh
RUN chmod +x /tmp/write-herdr-config.sh \
 && INSTALL_HERDR=${INSTALL_HERDR} /tmp/write-herdr-config.sh \
 && rm /tmp/write-herdr-config.sh /tmp/herdr-config.toml

# Baked into the image (rather than a sandbox spec.yaml environment
# variable) so every consumer of the image gets it for free. Harmless
# when INSTALL_HERDR=false — nothing reads it without the herdr binary.
ENV HERDR_AGENT=${AGENT}

# herdr-entrypoint.sh is always copied in and always the entrypoint — but
# installed under an agent-specific name (${AGENT}-herdr, e.g. claude-herdr,
# codex-herdr) so each agent's spec.yaml.tpl can reference its own command,
# matching the claude-wrapper.sh/copilot-wrapper.sh naming convention. It
# still reads $HERDR_AGENT to know which CLI to drive, and falls back to
# that agent's classic direct launch at runtime if herdr isn't on PATH
# (i.e. INSTALL_HERDR=false).
COPY --chown=1000:1000 scripts/herdr-entrypoint.sh /home/agent/.local/bin/${AGENT}-herdr
RUN chmod +x /home/agent/.local/bin/${AGENT}-herdr

# ── 2. Install system tools ─────────────────────────────────────────────────
USER root
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends fd-find=10.3.0-2ubuntu1 \
 && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
 && rm -rf /var/lib/apt/lists/*

# Give agent access to the mounted docker socket (only present on the
# shell-docker base variant; no-op otherwise). Some sandbox runtimes pin an
# explicit uid:gid for the container process, which skips supplementary
# group resolution entirely — so agent's primary group is switched to
# docker rather than relying on a secondary membership.
RUN if getent group docker >/dev/null 2>&1; then usermod -g docker agent; fi

# ── 3. Optionally install AWS CLI v2 + write ~/.aws/config ──────────────────
# Pass --build-arg INSTALL_AWSCLI=true (or set it in docker-bake.hcl) to
# bake the CLI into the image; both scripts no-op when it's false. See the
# scripts themselves for the SSO_* build-arg contract.
COPY --chown=1000:1000 scripts/install-awscli.sh /tmp/install-awscli.sh
RUN chmod +x /tmp/install-awscli.sh \
 && INSTALL_AWSCLI=${INSTALL_AWSCLI} /tmp/install-awscli.sh \
 && rm /tmp/install-awscli.sh

USER agent

# Runs as the agent user so ~/.aws/config lands in their home dir.
COPY --chown=1000:1000 scripts/write-aws-config.sh /tmp/write-aws-config.sh
RUN chmod +x /tmp/write-aws-config.sh \
 && INSTALL_AWSCLI=${INSTALL_AWSCLI} \
    SSO_START_URL=${SSO_START_URL} SSO_REGION=${SSO_REGION} \
    SSO_ROLE_NAME=${SSO_ROLE_NAME} SSO_ACCOUNT_ID=${SSO_ACCOUNT_ID} \
    /tmp/write-aws-config.sh \
 && rm /tmp/write-aws-config.sh

# ── 4. Bake in agent-specific settings + hooks ───────────────────────────────
# All config trees land in /tmp/agent-configs/; apply-config.sh moves the
# right subtree to its agent home dir (~/.copilot/, ~/.pi/agent/, etc.).
# Splitting install from config keeps each layer cache-friendly.
COPY --chown=1000:1000 config/ /tmp/agent-configs/
RUN AGENT=${AGENT} PROVIDER=${PROVIDER} /tmp/agent-configs/apply-config.sh \
 && rm -rf /tmp/agent-configs

# ── 4.5 Install agent-specific extras (post-config) ─────────────────────────
# Statusline plugins, pre-installed packages, etc. — dispatched by $AGENT
# inside the script. Runs after apply-config.sh; see the script header for why.
COPY --chown=1000:1000 scripts/install-agent-extras.sh /tmp/install-agent-extras.sh
RUN chmod +x /tmp/install-agent-extras.sh \
 && AGENT=${AGENT} CLAUDE_HUD_VERSION=${CLAUDE_HUD_VERSION} /tmp/install-agent-extras.sh \
 && rm /tmp/install-agent-extras.sh

# ── 4.6 Register herdr's official agent integration hook (if installed) ────
# `herdr integration install <kind>` merges a SessionStart hook into
# settings.json — must run after step 4 has written it. No-ops when
# INSTALL_HERDR=false, same opt-in flag as step 1.5.
COPY --chown=1000:1000 scripts/install-herdr-integration.sh /tmp/install-herdr-integration.sh
RUN chmod +x /tmp/install-herdr-integration.sh \
 && INSTALL_HERDR=${INSTALL_HERDR} AGENT=${AGENT} /tmp/install-herdr-integration.sh \
 && rm /tmp/install-herdr-integration.sh
