# sbx-agent

Run **Claude Code**, **OpenAI Codex**, **GitHub Copilot**, or **Pi** in
full-autonomy mode — no approval prompts — boxed inside a disposable
[`sbx`](https://docs.docker.com/ai/sandboxes/) sandbox with its own network
allowlist and scoped credential injection. Pull a tag and go; nothing to
build.

Each image installs exactly **one** agent CLI at build time, plus that
agent's config and guardrail hooks — nothing else. AWS/Bedrock auth,
[coding-crew](https://github.com/ypxing/coding-crew) skills, and
[herdr](https://herdr.dev) terminal automation are applied later, at
sandbox-creation time, via `sbx` mixin kits — so these images stay
org-agnostic and are safe to pull publicly.

Source, mixins, and full docs: https://github.com/ypxing/sbx-agent-kits

## Tags

One repository, one tag per agent — all built on
`docker/sandbox-templates:shell-docker` (adds Docker-in-Docker support):

| Tag              | Agent CLI                                                                                          |
| ---------------- | -------------------------------------------------------------------------------------------------- |
| `claude-docker`  | [`@anthropic-ai/claude-code`](https://www.npmjs.com/package/@anthropic-ai/claude-code)             |
| `codex-docker`   | [`@openai/codex`](https://www.npmjs.com/package/@openai/codex)                                     |
| `copilot-docker` | [`@github/copilot`](https://www.npmjs.com/package/@github/copilot)                                 |
| `pi-docker`      | [`@earendil-works/pi-coding-agent`](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) |

All agent CLIs are installed at their **latest published npm version** as
of each image build — check `docker run --rm <tag> <agent> --version` for
the exact version baked into a given pull.

## Quick start

With [`sbx`](https://docs.docker.com/ai/sandboxes/), clone the source repo
and run its env file, picking the agent (defaults to `claude`; each kit
points `image:` at this repository):

```
git clone https://github.com/ypxing/sbx-agent-kits.git
cd sbx-agent-kits
sbx env run sbxenv.yaml --env-arg agent=claude
```

or plain Docker, for a quick look inside:

```
docker run --rm -it docker.io/ypxing/sbx-agent:codex-docker codex --version
```

`kits/agents/<agent>/spec.yaml` in the source repo is the ready-to-use
`sbx` kit for each tag — it already points `image:` at this repository by
default.

## What's baked in vs. applied later

- **Baked in (build time)**: the one agent CLI, its base config/hooks
  (auto-approve mode + a shared `pre-bash.sh` guardrail blocking risky
  commands like `rm -rf`, non-read-only `aws`, git push to `main`/`master`,
  and reads of `.env*`/`.npmrc*`), and `fd-find`.
- **Applied later, per sandbox** (via mixin kits, not baked into the
  image): AWS CLI/credentials and optional Bedrock model routing, herdr
  terminal automation, coding-crew skills, npm/yarn registry auth, and
  extras like the claude-hud statusline.

This split keeps one public image usable across any org's auth setup,
with nothing org-specific ever baked in.

## License

MIT — see the [source repo](https://github.com/ypxing/sbx-agent-kits) for
details.
