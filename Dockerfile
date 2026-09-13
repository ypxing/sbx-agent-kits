# Universal agent sandbox template
#
# Starts from the minimal Docker sandbox base (shell or shell-docker) and
# installs exactly one agent CLI at build time — no runtime setup step needed.
#
# ARGs
#   AGENT         copilot | pi | codex | claude   (which CLI to install)
#   BASE_VARIANT  shell | shell-docker              (controls Docker-in-Docker support)
#
# Image naming: the repository name is the agent only (pi, codex, claude,
# copilot). BASE_VARIANT is encoded in the tag instead:
#   <agent>:latest    shell base
#   <agent>:docker     shell-docker base
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
#     -t claude:docker \
#     .
#
# Build the full matrix in parallel:
#   docker buildx bake

ARG BASE_VARIANT=shell-docker
FROM docker/sandbox-templates:${BASE_VARIANT}

# Re-declare ARGs after FROM (Docker requirement)
ARG AGENT=copilot

USER agent
# ── 1. Install the agent CLI ─────────────────────────────────────────────────
# claude-wrapper.sh is staged to /tmp so install-agent.sh can place it as
# the `claude` command (renaming the real binary to `claude.real`).
COPY --chown=1000:1000 scripts/install-agent.sh   /tmp/install-agent.sh
COPY --chown=1000:1000 scripts/claude-wrapper.sh  /tmp/claude-wrapper.sh
COPY --chown=1000:1000 scripts/copilot-wrapper.sh /tmp/copilot-wrapper.sh
RUN chmod +x /tmp/install-agent.sh /tmp/claude-wrapper.sh /tmp/copilot-wrapper.sh \
 && AGENT=${AGENT} /tmp/install-agent.sh \
 && rm /tmp/install-agent.sh /tmp/claude-wrapper.sh

# ── 2. Install system tools ─────────────────────────────────────────────────
USER root
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends fd-find=10.3.0-2ubuntu1 \
 && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
 && rm -rf /var/lib/apt/lists/*

USER agent

# ── 3. Bake in agent-specific settings + hooks ───────────────────────────────
# All config trees land in /tmp/agent-configs/; apply-config.sh moves the
# right subtree to its agent home dir (~/.copilot/, ~/.pi/agent/, etc.).
# Splitting install from config keeps each layer cache-friendly.
COPY --chown=1000:1000 config/ /tmp/agent-configs/
RUN AGENT=${AGENT} /tmp/agent-configs/apply-config.sh \
 && rm -rf /tmp/agent-configs
