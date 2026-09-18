# sbx-agent-kits

Run **Claude Code**, **OpenAI Codex**, **GitHub Copilot**, or **Pi** in
full-autonomy mode — skip the approval prompts, but keep every agent boxed
in: a disposable [`sbx`](https://docs.docker.com/ai/sandboxes/) sandbox with
its own network allowlist and scoped credential injection, thrown away when
the session ends. There's no custom image to build or publish — each kit
starts from the public `docker/sandbox-templates` base and installs its
agent CLI at sandbox-creation time via `npm install -g`, so every sandbox
always runs whatever's newest on npm.

Each `kits/agents/<agent>/` kit installs exactly one agent CLI, plus its
config/hooks, at sandbox-creation time. AWS auth/Bedrock routing,
coding-crew skills, and [herdr](https://herdr.dev) terminal automation are
layered on top the same way via `sbx` mixin kits.

## Using with `sbx`

`sbx` only pulls kits from allowlisted sources, so allow this repo first:

```
sbx settings set kit.allowedSources '["docker.io/","github.com/ypxing/"]'
```

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
each by arg name to whichever kit declares it, no plumbing required):

```
sbx env run examples/aws-sso.sbxenv.yaml \
  --kit-arg auth_mode=sso \
  --kit-arg sso_start_url=https://YOUR_ORG.awsapps.com/start \
  --kit-arg sso_region=ap-southeast-2 \
  --kit-arg sso_role_name=YourRoleName \
  --kit-arg sso_account_id=123456789012
```

`--env-arg` is for args the env file itself declares (like this repo's own
root `sbxenv.yaml` declaring `agent`/`workspace`/`home_dir`) — `--kit-arg`
skips that and targets the underlying kits directly, which is simpler when
a value (like these SSO settings) has no reason to be an env-file-level
knob.

`npm-auth.sbxenv.yaml` needs an `NPM_TOKEN` secret set first, sourced from
wherever you keep it — e.g. from the macOS Keychain:

```
security find-generic-password -s npm-token -w \
  | xargs -I {} sbx secret set-custom --host registry.npmjs.org --host registry.yarnpkg.com --env NPM_TOKEN --value {}
```

This repo's own `sbxenv.yaml` (at the root) is a fuller example: it lets you
pick any of the four agents (`--env-arg agent=codex`) and layers in every
mixin at once — useful as a reference for building your own, but the
`examples/` above are the ones to start from. It also requires
`--env-arg home_dir=$HOME` (a host path it uses to persist each agent's
session/memory state across sandbox recreation — see "Persisting session
state" below).

## Config layering

Each `kits/agents/<agent>/files/home/` bundles that agent's base settings +
hooks as static files, landed in its home dir (`~/.claude`, `~/.codex`,
`~/.copilot`, `~/.pi/agent`) before `setup.install` runs — including a
shared `pre-bash.sh` guardrail hook; see the `pre-bash-common.sh` next to
it in each kit for the full list of blocked commands.

Each agent's base config also defaults to full-autonomy / auto-approve mode
(e.g. Claude's `bypassPermissionsModeAccepted`, Codex's
`approval_policy = "never"`) — no per-action confirmation prompts. This is
intentional, not an oversight: the sandbox's network allowlist and
`pre-bash.sh` guardrails are what keep an unattended agent boxed in, and
the disposable container/scoped credentials limit the blast radius if it
still goes off the rails.

## Persisting session state

Every `kits/agents/<agent>/spec.yaml` declares a `host_persist_dir` arg —
point it at a host directory (mounted separately, e.g. via
`additionalWorkspaces`) and that agent's session/resume/history state gets
symlinked into it, so it survives sandbox recreation. Everything else
stays sandbox-local. Each kit's `spec.yaml` documents exactly which paths
it persists. Leave the arg unset for a fully ephemeral sandbox.

The root `sbxenv.yaml` wires this up already (`home_dir` arg →
`${home_dir}/.sbx/.<agent>-sbx`); the `agent-packages` mixin's
`host_persist_dir` arg does the same for ECC's own session memory when
`install_ecc=true`.

## Mixin reference

Beyond the examples above, each mixin under `kits/mixins/` can help with:

- **`aws/`** — AWS CLI + credentials (SSO or ambient), optionally routing
  codex/pi through Bedrock.
- **`herdr/`** — checksum-pinned [herdr](https://herdr.dev) terminal
  automation, running the agent as a managed pane.
- **`coding-crew/`** — installs
  [coding-crew](https://github.com/ypxing/coding-crew) skills.
- **`agent-packages/`** — per-agent extras (claude-hud statusline for
  claude, extra npm packages for pi, and optionally
  [ECC](https://github.com/affaan-m/ECC) for claude/codex via
  `install_ecc=true`).
- **`npm-auth/`** — private npm/yarn registry auth via an `NPM_TOKEN`
  secret.
- **`domains-access/`** — standalone network allowlist for AWS, GitHub
  (incl. `*.github.io`), npm/yarn, Python/Go/Rust registries, container
  registries, and claude/copilot/codex docs sites — add your own org's
  domains to it. No install step — permissions only.

Each `spec.yaml` documents its own args in full.

## Contributing

### Layout

```
kits/agents/<agent>/
  spec.yaml          Ready-to-use sbx kit: installs the agent CLI at
                      sandbox-creation time (npm install -g), wraps its
                      binary to pre-accept the trust dialog, and links
                      persistent session state if host_persist_dir is set
  files/home/.<agent>/  Static base settings + guardrail hooks, landed in
                        the agent's home dir before setup.install runs

kits/mixins/          sbx mixin kits — applied at sandbox-creation time, layered on top
  agent-packages/      per-agent extras: claude-hud for claude, npm packages for pi, optional ECC
  aws/                 AWS CLI/auth + optional Bedrock routing
  coding-crew/         coding-crew skills
  domains-access/      standalone developer network allowlist
  herdr/               herdr terminal automation
  npm-auth/            npm/yarn registry auth

examples/             sbxenv.yaml per use case (see "Using with sbx" above)
sbxenv.yaml           Local sbx environment for this repo (workspace = .)
LICENSE               MIT
```

### Kit spec reference

Each `spec.yaml` follows Docker's [kit spec
reference](https://docs.docker.com/ai/sandboxes/configuration/kit-spec-reference/):
`args` declare overridable inputs (`--kit-arg <name>=<value>`), `setup.install`
runs once at sandbox-creation time (after `files/home/` has already landed),
`setup.startup` runs every time the sandbox starts, and `permissions.network.allow`
is the network allowlist a kit needs to actually function under
`sbx policy init deny-all`.

### Testing a kit locally

```
sbx run --kit ./kits/agents/claude claude
sbx policy log   # lists every network call a kit made, and whether it was allowed
```
