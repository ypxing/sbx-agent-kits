# sbx-agent-kits

Run **Claude Code**, **OpenAI Codex**, **GitHub Copilot**, or **Pi** in
full-autonomy mode — skip the approval prompts, but keep every agent boxed
in: a disposable [`sbx`](https://docs.docker.com/ai/sandboxes/) sandbox with
its own network allowlist and scoped credential injection, thrown away when
the session ends. Pull the prebuilt public image and go — nothing to build.

Each image installs exactly one agent CLI at build time, plus its
config/hooks — nothing else. AWS auth/Bedrock routing, coding-crew skills,
and [herdr](https://herdr.dev) terminal automation are optional and applied
at sandbox-creation time instead, via `sbx` mixin kits — so the same public
image works across any org/auth setup, and nothing org-specific ever gets
baked in.

## Using with `sbx`

Point `sbx` at a single `sbxenv.yaml` — see Docker's [environment file
reference](https://docs.docker.com/ai/sandboxes/configuration/environment-files/)
for the full schema. `examples/` has one per use case; run whichever matches
yours directly, or copy it to `sbxenv.yaml` in your own workspace first:

```
sbx env run examples/minimal.sbxenv.yaml
```

| Example                             | What it adds                                                  |
| ----------------------------------- | ------------------------------------------------------------- |
| `examples/minimal.sbxenv.yaml`      | Just claude — no other setup required                         |
| `examples/npm-auth.sbxenv.yaml`     | + private npm/yarn registry auth                              |
| `examples/herdr.sbxenv.yaml`        | + herdr terminal automation                                   |
| `examples/aws-external.sbxenv.yaml` | + AWS CLI, credentials left to the ambient chain              |
| `examples/aws-sso.sbxenv.yaml`      | + AWS CLI with SSO login, routed through Bedrock via env vars |

`aws-sso.sbxenv.yaml` doesn't declare `auth_mode`/`sso_*` as env-file args —
pass them straight through to the aws mixin with `--kit-arg` (sbx routes
each by arg name to whichever kit declares it):

```
sbx env run examples/aws-sso.sbxenv.yaml \
  --kit-arg auth_mode=sso \
  --kit-arg sso_start_url=https://YOUR_ORG.awsapps.com/start \
  --kit-arg sso_region=ap-southeast-2 \
  --kit-arg sso_role_name=YourRoleName \
  --kit-arg sso_account_id=123456789012
```

`--env-arg` is for args the env file itself declares (like this repo's own
root `sbxenv.yaml` declaring `agent`/`workspace`) — `--kit-arg` skips that
and targets the underlying kits directly, which is simpler when a value
(like these SSO settings) has no reason to be an env-file-level knob.

`npm-auth.sbxenv.yaml` needs an `NPM_TOKEN` secret set first, sourced from
wherever you keep it — e.g. from the macOS Keychain:

```
security find-generic-password -s npm-token -w \
  | xargs -I {} sbx secret set-custom --host registry.npmjs.org --host registry.yarnpkg.com --env NPM_TOKEN --value {}
```

This repo's own `sbxenv.yaml` (at the root) is a fuller example: it lets you
pick any of the four agents (`--env-arg agent=codex`) and layers in every
mixin at once — useful as a reference for building your own, but the
`examples/` above are the ones to start from.

## Config layering

Every image copies `config/<agent>/` to the agent's home dir at build time
(`~/.claude`, `~/.codex`, `~/.copilot`, `~/.pi/agent`), including a shared
`pre-bash.sh` guardrail hook — see `config/common/pre-bash-common.sh` for
the full list of blocked commands.

Each agent's base config also defaults to full-autonomy / auto-approve mode
(e.g. Claude's `bypassPermissionsModeAccepted`, Codex's
`approval_policy = "never"`) — no per-action confirmation prompts. This is
intentional, not an oversight: the sandbox's network allowlist and
`pre-bash.sh` guardrails are what keep an unattended agent boxed in, and
the disposable container/scoped credentials limit the blast radius if it
still goes off the rails.

## Mixin reference

Beyond the examples above, each mixin under `kits/mixins/` can help with:

- **`aws/`** — AWS CLI + credentials (SSO or ambient), optionally routing
  codex/pi through Bedrock.
- **`herdr/`** — checksum-pinned [herdr](https://herdr.dev) terminal
  automation, running the agent as a managed pane.
- **`coding-crew/`** — installs
  [coding-crew](https://github.com/ypxing/coding-crew) skills.
- **`agent-packages/`** — per-agent extras (claude-hud statusline for
  claude, extra npm packages for pi).
- **`npm-auth/`** — private npm/yarn registry auth via an `NPM_TOKEN`
  secret.

Each `spec.yaml` documents its own args in full.

## Contributing

### Layout

```
Dockerfile          Universal template — one agent CLI per build (see ARGs below)
docker-bake.hcl      Build matrix: agent × base variant
Makefile             AWS SSO login, ECR build/tag/push, Docker Hub publish

kits/agents/<agent>/
  spec.yaml          Ready-to-use sbx kit; `image` defaults to the public Docker
                      Hub tag and can be overridden per-run with `--kit-arg image=...`

kits/mixins/          sbx mixin kits — applied at sandbox-creation time, not baked in
  agent-packages/      per-agent extras: claude-hud for claude, npm packages for pi
  aws/                 AWS CLI/auth + optional Bedrock routing
  coding-crew/         coding-crew skills
  herdr/               herdr terminal automation
  npm-auth/            npm/yarn registry auth

config/<agent>/       Base settings + hooks for each agent
config/common/        Shared guardrails (pre-bash.sh hook library)

scripts/              Install/config helpers invoked by the Dockerfile
examples/             sbxenv.yaml per use case (see "Using with sbx" above)
sbxenv.yaml           Local sbx environment for this repo (workspace = .)
LICENSE               MIT
```

### Building an image locally

```
docker build --build-arg AGENT=claude -t claude:latest .
```

or the full matrix with buildx bake:

```
docker buildx bake claude-docker      # sbx-agent:claude-docker
docker buildx bake                    # default group: copilot, pi, codex, claude (shell variant)
docker buildx bake claude claude-docker  # both variants for one agent
```

Key `Dockerfile` build args:

| ARG            | Values                                   | Default        | Effect                   |
| -------------- | ---------------------------------------- | -------------- | ------------------------ |
| `AGENT`        | `copilot` \| `pi` \| `codex` \| `claude` | `copilot`      | Which CLI to install     |
| `BASE_VARIANT` | `shell` \| `shell-docker`                | `shell-docker` | Docker-in-Docker support |

See the Dockerfile header comment for more build examples and image-naming
details.

### Publishing images

```
make sso-login            # aws sso login (host-side, for pushing to your ECR)
make ecr-login            # docker login to your ECR
make claude-docker
make tag push              # tag + push the Makefile's IMAGES to $ECR
```

`IMAGES` (in the Makefile) is `claude-docker copilot-docker pi-docker` by
default — codex isn't included in this private ECR flow; add it there if
you need it.

No image bakes in AWS credentials or Bedrock routing config, so all four
images are also safe to publish publicly:

```
export DOCKERHUB_USER=your-dockerhub-username

make docker-login          # once per session
make publish                # build → tag → push all four to docker.io/$DOCKERHUB_USER/sbx-agent
make publish-image IMAGE=claude-docker   # just one
```

Set `DOCKERHUB_TOKEN` to log in non-interactively (e.g. in CI). Override
`SSO_*`, `ECR`, or `DOCKERHUB_USER` in the Makefile to point at your own
registry.
