# Getting started with Docker Sandboxes (`sbx`) and these kits

Run a coding agent (Claude, Codex, Copilot, Pi) in a disposable, network-restricted
Docker sandbox, configured by the kits in this repo.

## One-off setup

### 1. Docker Hub account

Create a free [Docker Hub](https://hub.docker.com) account, then log in:

```
docker login
```

### 2. Install Docker Sandboxes

```
brew trust docker/tap
brew install docker/tap/sbx
```

### 3. Initialise the network policy

Sets the default network policy for sandboxes to the `balanced` preset:

```
sbx policy init balanced
```

### 4. Install the GitHub CLI

Used for the GitHub token, Copilot and other GitHub operations.

```
brew install gh
gh auth login
```

### 5. Store secrets

Secrets are injected by `sbx` into sandbox traffic for the listed hosts; they are
never written into the sandbox.

**npm token** (only needed for private npm/yarn packages) — source it from
wherever you keep it, e.g. the macOS Keychain:

```
security find-generic-password -s npm-token -w | xargs -I {} \
  sbx secret set-custom --host registry.npmjs.org \
                        --host registry.yarnpkg.com \
                        --env NPM_TOKEN \
                        --value {}
```

**GitHub token** (re-run when it expires)

```
sbx secret set github --command 'gh auth token'
```

### 6. Allow these kits

`sbx` only pulls kits from allowlisted sources:

```
sbx settings set kit.allowedSources '["docker.io/","github.com/ypxing/"]'
```

### 7. Get the environment file

Copy [`sbxenv.yaml`](../sbxenv.yaml) to `~/.sbx/sbxenv.yaml`.

## Daily use

### Start a sandbox

From the project folder you want the agent to work on:

```
sbx env run ~/.sbx --env-arg workspace=${PWD} --env-arg home_dir=${HOME}
```

Pick another agent with `--env-arg agent=codex` (`claude` is the default; also
`pi`, `copilot`). The sandbox is named `<agent>-sbx-<folder>`, e.g.
`claude-sbx-my-app`.

Agent session/memory state persists in `~/.sbx/.<agent>-sbx` on the host.

The AWS mixin defaults to `auth_mode=external` (ambient credentials). For AWS
SSO, pass your org's values with `--kit-arg` — see the
[README](../README.md#using-with-sbx):

```
sbx env run ~/.sbx --env-arg workspace=${PWD} --env-arg home_dir=${HOME} \
  --kit-arg auth_mode=sso \
  --kit-arg sso_start_url=https://YOUR_ORG.awsapps.com/start \
  --kit-arg sso_region=ap-southeast-2 \
  --kit-arg sso_role_name=YourRoleName \
  --kit-arg sso_account_id=123456789012
```

### List sandboxes

```
% sbx ls
SANDBOX             AGENT        STATUS    PORTS  WORKSPACE
claude-sbx-my-app   claude-sbx   running          /Users/me/repo/my-app, /Users/me/.sbx/sbxenv.yaml:ro, /Users/me/.sbx/.claude-sbx, /Users/me/.gitconfig:ro
```

### SSH into a sandbox

Set up the SSH client config once:

```
sbx setup ssh
```

The host name is `<sandbox name>.sbx`:

```
ssh claude-sbx-my-app.sbx -- echo hello
```

## What's in the sandbox

`sbxenv.yaml` layers these kits on top of the agent (see the
[README](../README.md#mixin-reference) for details): AWS CLI + Bedrock routing,
herdr, coding-crew skills, npm auth, extra apt packages, agent extras, and a
network allowlist for common developer domains.

Lighter-weight starting points are in [`examples/`](../examples).
