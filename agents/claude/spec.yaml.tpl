schemaVersion: "2"
kind: sandbox
name: claude-sbx
displayName: Claude Code
description: Claude Code agent.

# Image resolved by scripts/gen-specs.sh — set SBX_IMAGE_REGISTRY or
# SBX_CLAUDE_IMAGE before running it to use your own image.
sandbox:
  image: "${SBX_CLAUDE_IMAGE}"
  # claude-herdr (scripts/herdr-entrypoint.sh, installed under this
  # agent-specific name) boots a headless herdr server and starts claude in
  # a managed pane (as `main`) rather than exec'ing claude directly.
  # Attach/orchestrate afterward with `sbx exec -it <name> herdr ...`
  # against the same running server.
  entrypoint: [claude-herdr]

setup:
  install:
    - command: |
        echo '//registry.npmjs.org/:_authToken=${NPM_TOKEN}' > $HOME/.npmrc
        echo '//registry.yarnpkg.com/:_authToken=${NPM_TOKEN}' >> $HOME/.npmrc
      user: "1000"
      description: "Write npm registry auth tokens to $HOME/.npmrc"

environment:
  variables:
    # sandbox
    IS_SANDBOX: "1"
    SBX_NO_TELEMETRY: "1"

    # aws
    AWS_PROFILE: "sso-live"
    AWS_BEDROCK_FORCE_CACHE: "1"

    ANTHROPIC_DEFAULT_SONNET_MODEL: au.anthropic.claude-sonnet-5
    ANTHROPIC_DEFAULT_OPUS_MODEL: au.anthropic.claude-opus-5
    ANTHROPIC_DEFAULT_HAIKU_MODEL: au.anthropic.claude-haiku-4-5-20251001-v1:0
