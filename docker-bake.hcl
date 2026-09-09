# docker-bake.hcl — agent × provider × base-variant build matrix
#   AGENT         ∈ { copilot, pi, codex, claude }
#   PROVIDER      ∈ { standard, bedrock }             (copilot: standard only)
#   BASE_VARIANT  ∈ { shell, shell-docker }
#
# Image naming: all agents use the single image name sbx-agent, with the
# agent name and variant encoded in the tag:
#   sbx-agent:<agent>                standard provider, shell base
#   sbx-agent:<agent>-docker          standard provider, shell-docker base
#   sbx-agent:<agent>-bedrock         bedrock provider,  shell base
#   sbx-agent:<agent>-docker-bedrock   bedrock provider,  shell-docker base
#
# Usage:
#   docker buildx bake                                         # all targets in parallel
#   docker buildx bake pi                                       # every pi variant
#   docker buildx bake pi-docker                                # sbx-agent:pi-docker only
#   docker buildx bake pi-docker-bedrock                        # sbx-agent:pi-docker-bedrock only
#
# Opt into coding-crew skills:
#   INSTALL_CODING_CREW=true docker buildx bake pi
#   INSTALL_CODING_CREW=true CODING_CREW_VERSION=1.2.3 docker buildx bake

variable "INSTALL_CODING_CREW" {
  default = "false"
}

variable "CODING_CREW_VERSION" {
  default = "latest"
}

# claude-hud (https://github.com/jarrodwatts/claude-hud) git tag baked into
# ~/.claude-hud for the claude agent's statusline. Ignored by other agents.
variable "CLAUDE_HUD_VERSION" {
  default = "v0.8.0"
}

# Opt-in: install herdr.dev and switch the sandbox entrypoint to boot it
# instead of launching the agent directly (see scripts/herdr-entrypoint.sh).
#   INSTALL_HERDR=true docker buildx bake claude
variable "INSTALL_HERDR" {
  default = "false"
}

# Pinned herdr.dev release (https://herdr.dev) — see scripts/install-herdr.sh
# to bump (updating its hardcoded per-arch sha256 checksums too).
variable "HERDR_VERSION" {
  default = "0.8.2"
}

# Toggle AWS CLI baking — override with INSTALL_AWSCLI=true on the CLI or
# by setting it inside a specific target below. Bedrock targets set this
# to "true" themselves.
variable "INSTALL_AWSCLI" {
  default = "false"
}

# AWS SSO config baked into ~/.aws/config when INSTALL_AWSCLI=true.
# All four vars are required for bedrock targets; the build fails if any is missing.
# Set them as environment variables before running bake:
#   export SSO_START_URL=https://myorg.awsapps.com/start
#   export SSO_REGION=ap-southeast-2
#   export SSO_ROLE_NAME=MyRole
#   export SSO_ACCOUNT_ID=123456789012
variable "SSO_START_URL"  { default = "" }   # e.g. https://myorg.awsapps.com/start
variable "SSO_REGION"     { default = "" }   # e.g. ap-southeast-2
variable "SSO_ROLE_NAME"  { default = "" }   # e.g. EngineeringPri-Elevated-NonProd
variable "SSO_ACCOUNT_ID" { default = "" }   # e.g. 0123456789

# ── Shared defaults ──────────────────────────────────────────────────────────
target "_common" {
  context    = "."
  dockerfile = "Dockerfile"
  args = {
    INSTALL_AWSCLI      = INSTALL_AWSCLI
    INSTALL_CODING_CREW = INSTALL_CODING_CREW
    CODING_CREW_VERSION = CODING_CREW_VERSION
    CLAUDE_HUD_VERSION  = CLAUDE_HUD_VERSION
    INSTALL_HERDR       = INSTALL_HERDR
    HERDR_VERSION       = HERDR_VERSION
    SSO_START_URL       = SSO_START_URL
    SSO_REGION          = SSO_REGION
    SSO_ROLE_NAME       = SSO_ROLE_NAME
    SSO_ACCOUNT_ID      = SSO_ACCOUNT_ID
  }
}

# Bedrock targets always need the AWS CLI baked in, regardless of the
# INSTALL_AWSCLI variable's default.
target "_bedrock" {
  inherits = ["_common"]
  args = {
    PROVIDER       = "bedrock"
    INSTALL_AWSCLI = "true"
  }
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  copilot  (image: sbx-agent, no Bedrock backend)                       ║
# ╚══════════════════════════════════════════════════════════════════════════╝
target "copilot" {
  inherits = ["_common"]
  args = {
    BASE_VARIANT = "shell"
    AGENT        = "copilot"
  }
  tags = ["sbx-agent:copilot"]
}

target "copilot-docker" {
  inherits = ["_common"]
  args = {
    BASE_VARIANT = "shell-docker"
    AGENT        = "copilot"
  }
  tags = ["sbx-agent:copilot-docker"]
}

group "copilot" {
  targets = ["copilot", "copilot-docker"]
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  pi  (image: sbx-agent)                                                ║
# ╚══════════════════════════════════════════════════════════════════════════╝
target "pi" {
  inherits = ["_common"]
  args = {
    BASE_VARIANT = "shell"
    AGENT        = "pi"
  }
  tags = ["sbx-agent:pi"]
}

target "pi-docker" {
  inherits = ["_common"]
  args = {
    BASE_VARIANT = "shell-docker"
    AGENT        = "pi"
  }
  tags = ["sbx-agent:pi-docker"]
}

target "pi-bedrock" {
  inherits = ["_bedrock"]
  args = {
    BASE_VARIANT = "shell"
    AGENT        = "pi"
  }
  tags = ["sbx-agent:pi-bedrock"]
}

target "pi-docker-bedrock" {
  inherits = ["_bedrock"]
  args = {
    BASE_VARIANT = "shell-docker"
    AGENT        = "pi"
  }
  tags = ["sbx-agent:pi-docker-bedrock"]
}

group "pi" {
  targets = ["pi", "pi-docker", "pi-bedrock", "pi-docker-bedrock"]
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  codex  (image: sbx-agent)                                              ║
# ╚══════════════════════════════════════════════════════════════════════════╝
target "codex" {
  inherits = ["_common"]
  args = {
    BASE_VARIANT = "shell"
    AGENT        = "codex"
  }
  tags = ["sbx-agent:codex"]
}

target "codex-docker" {
  inherits = ["_common"]
  args = {
    BASE_VARIANT = "shell-docker"
    AGENT        = "codex"
  }
  tags = ["sbx-agent:codex-docker"]
}

target "codex-bedrock" {
  inherits = ["_bedrock"]
  args = {
    BASE_VARIANT = "shell"
    AGENT        = "codex"
  }
  tags = ["sbx-agent:codex-bedrock"]
}

target "codex-docker-bedrock" {
  inherits = ["_bedrock"]
  args = {
    BASE_VARIANT = "shell-docker"
    AGENT        = "codex"
  }
  tags = ["sbx-agent:codex-docker-bedrock"]
}

group "codex" {
  targets = ["codex", "codex-docker", "codex-bedrock", "codex-docker-bedrock"]
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  claude  (image: sbx-agent)                                             ║
# ╚══════════════════════════════════════════════════════════════════════════╝
target "claude" {
  inherits = ["_common"]
  args = {
    BASE_VARIANT = "shell"
    AGENT        = "claude"
  }
  tags = ["sbx-agent:claude"]
}

target "claude-docker" {
  inherits = ["_common"]
  args = {
    BASE_VARIANT = "shell-docker"
    AGENT        = "claude"
  }
  tags = ["sbx-agent:claude-docker"]
}

target "claude-bedrock" {
  inherits = ["_bedrock"]
  args = {
    BASE_VARIANT = "shell"
    AGENT        = "claude"
  }
  tags = ["sbx-agent:claude-bedrock"]
}

target "claude-docker-bedrock" {
  inherits = ["_bedrock"]
  args = {
    BASE_VARIANT = "shell-docker"
    AGENT        = "claude"
  }
  tags = ["sbx-agent:claude-docker-bedrock"]
}

group "claude" {
  targets = ["claude", "claude-docker", "claude-bedrock", "claude-docker-bedrock"]
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  Default: build everything                                              ║
# ╚══════════════════════════════════════════════════════════════════════════╝
group "default" {
  targets = [
    "copilot",
    "pi", "pi-bedrock",
    "codex", "codex-bedrock",
    "claude", "claude-bedrock",
  ]
}
# All targets produce sbx-agent:<tag> images:
#   pi / pi-docker / pi-bedrock / pi-docker-bedrock
#   codex / codex-docker / codex-bedrock / codex-docker-bedrock
#   claude / claude-docker / claude-bedrock / claude-docker-bedrock
#   copilot / copilot-docker
