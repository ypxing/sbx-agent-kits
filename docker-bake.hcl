# docker-bake.hcl — agent × base-variant build matrix
#   AGENT         ∈ { copilot, pi, codex, claude }
#   BASE_VARIANT  ∈ { shell, shell-docker }
#
# AWS Bedrock model-routing config is not part of this build matrix — it's
# applied at sandbox-creation time via the kits/mixins/aws/ mixin kit
# (`--kit-arg use_bedrock=true`), alongside the AWS credentials it needs to
# be useful. See README's "Optional: AWS / Bedrock auth" section.
#
# Image naming: all agents use the single image name sbx-agent, with the
# agent name and variant encoded in the tag:
#   sbx-agent:<agent>          shell base
#   sbx-agent:<agent>-docker    shell-docker base
#
# Usage:
#   docker buildx bake                                         # all targets in parallel
#   docker buildx bake pi                                       # every pi variant
#   docker buildx bake pi-docker                                # sbx-agent:pi-docker only
#
# coding-crew skills are no longer baked into the image — apply them at
# sandbox-creation time instead via the kits/mixins/coding-crew/ mixin kit
# (see README's "Optional: coding-crew" section).

# herdr.dev is no longer baked into the image — apply it at sandbox-creation
# time instead via the kits/mixins/herdr/ mixin kit (see README's
# "Optional: herdr" section).

# claude-hud (statusline plugin) and pi's extra npm packages are likewise
# applied at sandbox-creation time now, via the kits/mixins/agent-packages/
# mixin kit.

# ── Shared defaults ──────────────────────────────────────────────────────────
target "_common" {
  context    = "."
  dockerfile = "Dockerfile"
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  copilot  (image: sbx-agent)                                            ║
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

group "pi" {
  targets = ["pi", "pi-docker"]
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

group "codex" {
  targets = ["codex", "codex-docker"]
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

group "claude" {
  targets = ["claude", "claude-docker"]
}

# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  Default: build everything                                              ║
# ╚══════════════════════════════════════════════════════════════════════════╝
group "default" {
  targets = [
    "copilot",
    "pi",
    "codex",
    "claude",
  ]
}
# All targets produce sbx-agent:<tag> images:
#   pi / pi-docker
#   codex / codex-docker
#   claude / claude-docker
#   copilot / copilot-docker
