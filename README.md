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
coding-crew skills, and a checksum-pinned [herdr](https://herdr.dev) binary
are layered on top the same way via `sbx` mixin kits.

New to `sbx`? [`docs/getting-started.md`](docs/getting-started.md) walks
through the one-off host setup and daily use.

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
| `examples/herdr.sbxenv.yaml`        | + herdr binary (run manually via `sbx exec`)                  |
| `examples/aws-external.sbxenv.yaml` | + AWS CLI, credentials left to the ambient chain              |
| `examples/aws-sso.sbxenv.yaml`      | + AWS CLI with SSO login, routed through Bedrock via env vars |

`aws-sso.sbxenv.yaml` doesn't declare `auth_mode`/`sso_*` as env-file args —
pass them straight through to the aws mixin with `--kit-arg` (sbx routes
each by arg name to whichever kit declares it):

```
sbx env run examples/aws-sso.sbxenv.yaml \
  --kit-arg auth_mode=sso \
  --kit-arg sso_start_url=https://YOUR_ORG.awsapps.com/start \
  --kit-arg sso_region=us-east-1 \
  --kit-arg sso_role_name=YourRoleName \
  --kit-arg sso_account_id=123456789012
```

The aws mixin defaults to `auth_mode=external`, and
`aws-external.sbxenv.yaml` also passes it explicitly.

`npm-auth.sbxenv.yaml` needs an `NPM_TOKEN` secret set first, sourced from
wherever you keep it — e.g. from the macOS Keychain:

```
security find-generic-password -s npm-token -w \
  | xargs -I {} sbx secret set-custom --host registry.npmjs.org --host registry.yarnpkg.com --env NPM_TOKEN --value {}
```

This repo's own `sbxenv.yaml` (at the root) is a fuller example: it lets you
pick any of the four agents (`--env-arg agent=codex`) and layers in every
mixin at once, bar the `example-org/` template — useful as a reference for
building your own, but the `examples/` above are the ones to start from.

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

## Mixin reference

Beyond the examples above, each mixin under `kits/mixins/` can help with:

- **`aws/`** — AWS CLI + credentials (SSO or ambient), optionally routing
  codex/pi through Bedrock.
- **`herdr/`** — installs a checksum-pinned [herdr](https://herdr.dev)
  binary only; nothing is wired up automatically, run it yourself via
  `sbx exec -it <sandbox> herdr ...`.
- **`coding-crew/`** — installs
  [coding-crew](https://github.com/ypxing/coding-crew) skills.
- **`agent-packages/`** — per-agent extras (claude-hud statusline for
  claude, extra npm packages for pi).
- **`npm-auth/`** — private npm/yarn registry auth via an `NPM_TOKEN`
  secret.
- **`apt-packages/`** — installs extra apt packages (e.g. a compiler, plus current `gh` from GitHub's apt repo) on
  top of the base image.
- **`domains-access/`** — standalone network allowlist for AWS, GitHub
  (incl. `*.github.io`), npm/yarn, Python/Go/Rust/JVM/Terraform registries,
  container registries, and common language/platform and
  claude/copilot/codex docs sites. No install step — permissions only.
  Holds general developer infrastructure only and names no organisation.
- **`example-org/`** — template for everything an org's engineers use on
  top of `domains-access`: the org's own domains, its tenants (e.g.
  `your-org.atlassian.net`, `your-org.slack.com`, commented out), the APIs
  of Atlassian, New Relic, Figma and Slack, and the Atlassian MCP server.
  Copy it as your own org's mixin with your own hosts; it isn't meant to be
  used as-is, and this repo's `sbxenv.yaml` doesn't. Permissions only.

A repo needing hosts beyond these (or fewer) can add its own local kit with
a `permissions.network.allow` list — `kits:` accepts local directories,
e.g. `- source: ./.sbx/extra-domains`, resolved from the `sbxenv.yaml`.

Each `spec.yaml` documents its own args in full.

## Contributing

### Layout

```
kits/agents/<agent>/
  spec.yaml          Ready-to-use sbx kit; `image` defaults to the public
                      docker/sandbox-templates base and can be overridden
                      per-run with `--kit-arg image=...`
  files/home/         Static files copied to the agent's home dir before
                      setup.install runs — base settings/config + guardrail
                      hooks. setup.install then just `npm install -g`s the
                      CLI (see the "Static files" section of Docker's
                      [kit spec reference](https://docs.docker.com/ai/sandboxes/customize/kit-reference/))

kits/mixins/          sbx mixin kits — applied at sandbox-creation time
  agent-packages/      per-agent extras: claude-hud for claude, npm packages for pi
  aws/                 AWS CLI/auth + optional Bedrock routing
  coding-crew/         coding-crew skills
  herdr/               checksum-pinned herdr binary install (run manually)
  npm-auth/            npm/yarn registry auth
  apt-packages/        extra apt packages on top of the base image
  domains-access/      standalone developer network allowlist (permissions only)
  example-org/         template org domains, tenants + SaaS tools allowlist (permissions only)

examples/             sbxenv.yaml per use case (see "Using with sbx" above)
docs/                 getting-started guide
tests/                bats tests for the shared pre-bash hook guardrails (`bats tests/`)
sbxenv.yaml           Local sbx environment for this repo (workspace = .)
LICENSE               MIT
```

There's no Dockerfile or image build/publish step — every kit installs its
agent CLI via `npm install -g` at sandbox-creation time, straight from npm,
so it always picks up whatever's newest.
