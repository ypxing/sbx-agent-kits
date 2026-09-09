schemaVersion: "2"
kind: sandbox
name: copilot-sbx
displayName: Copilot Agent (GitHub)
description: GitHub Copilot agent with GITHUB_TOKEN auth.

# Image resolved by scripts/gen-specs.sh — set SBX_IMAGE_REGISTRY or
# SBX_COPILOT_IMAGE before running it to use your own image.
sandbox:
  image: "${SBX_COPILOT_IMAGE}"
  # copilot-herdr (scripts/herdr-entrypoint.sh, installed under this
  # agent-specific name) boots a headless herdr server and starts copilot in
  # a managed pane (as `main`) rather than exec'ing copilot directly.
  # Attach/orchestrate afterward with `sbx exec -it <name> herdr ...`
  # against the same running server.
  entrypoint: [copilot-herdr]

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

credentials:
  - service: github
    required: true
    apiKey:
      name: GH_TOKEN
      inject:
        - domain: api.github.com
          header: Authorization
          format: Bearer %s
        - domain: github.com
          header: Authorization
          format: Bearer %s
        - domain: api.business.githubcopilot.com # Copilot Business
          header: Authorization
          format: Bearer %s
        - domain: api.enterprise.githubcopilot.com # Copilot Enterprise
          header: Authorization
          format: Bearer %s
        - domain: api.githubcopilot.com
          header: Authorization
          format: Bearer %s
        - domain: api.individual.githubcopilot.com # Copilot Pro and Pro+
          header: Authorization
          format: Bearer %s
        - domain: copilot.github.com
          header: Authorization
          format: Bearer %s

permissions:
  network:
    allow:
      # Every domain either credential injects into — required here too, not
      # just above: this repo's e2e runs every kit under
      # `sbx policy init deny-all`, so a domain absent from this list is
      # unreachable regardless of what the credential block declares.
      - api.business.githubcopilot.com # Copilot Business
      - api.enterprise.githubcopilot.com # Copilot Enterprise
      - api.github.com
      - api.githubcopilot.com
      - api.individual.githubcopilot.com # Copilot Pro and Pro+
      - copilot.github.com
      - github.com
      # `apt-get update` (the startup hook below) refreshes metadata for every
      # configured apt source and returns exit 100 if any one of them fails.
      # The shell-docker base ships three sources, so all three must be
      # reachable. Ubuntu serves amd64 from archive/security and arm64 from
      # ports.ubuntu.com, so all three Ubuntu hosts are listed to keep the kit
      # working cross-arch.
      - archive.ubuntu.com # Ubuntu archive (amd64 main)
      - security.ubuntu.com # Ubuntu security updates (amd64)
      - ports.ubuntu.com # Ubuntu archive/security (arm64)
      - download.docker.com # Docker's apt repo, pre-added by shell-docker
      #
      # TODO(copilot-extraction): the domains above are the ones the
      # credential block already declared; they have not been verified
      # end-to-end under deny-all from this repo, and Copilot CLI may reach
      # further hosts (telemetry, self-update, extension registry). Confirm
      # or widen from a live run:
      #
      #   sbx run --kit ./copilot copilot   # then attempt a prompt
      #   sbx policy log                    # lists every blocked host + reason
