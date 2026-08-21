# github-clone

A [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) **mixin kit** that clones a GitHub repository into the sandbox at create time, plus a declarative **environment file** that wires the kit, agent, and GitHub credentials together.

The clone runs via [`gh`](https://cli.github.com/) with a proxy-managed `GH_TOKEN`. The real token stays on the host; the container only ever sees a sentinel.

## Quick start

From this repo, with [`sbx`](https://docs.docker.com/ai/sandboxes/) and an authenticated `gh` on the host:

```bash
# Allow this publisher (once per machine) — only needed if you load the kit from GitHub
sbx settings set kit.allowedSources '["docker.io/","github.com/cdupuis/"]'

# Create the sandbox, clone the repo, attach the agent
sbx env run github-clone.env.yaml \
  --env-arg owner=cdupuis \
  --env-arg repo=frontend
```

That provisions a GitHub token from `gh auth token`, creates a sandbox named `cdupuis-frontend`, clones `cdupuis/frontend` to `/home/agent/workspace` inside it, and drops you into **Claude**. There is no host workspace bind: the working copy lives only in the sandbox.

```bash
sbx env run github-clone.env.yaml \
  --env-arg owner=cdupuis \
  --env-arg repo=frontend \
  --env-arg agent=codex
```

Tear it down (sandbox + scoped secrets):

```bash
sbx env rm github-clone.env.yaml \
  --env-arg owner=cdupuis \
  --env-arg repo=frontend
```

## Environment file

[`github-clone.env.yaml`](github-clone.env.yaml) is the recommended way to use the kit. It declares inputs, composes them into the sandbox name and clone path, and provisions host credentials.

| Arg | Required | Default | Used as |
|-----|----------|---------|---------|
| `owner` | yes | — | GitHub owner; sandbox name `owner-repo` |
| `repo` | yes | — | GitHub repo name (not `owner/name`) |
| `agent` | no | `claude` | Built-in agent (`claude`, `codex`, `gemini`, …) |

`owner` and `repo` are letters, digits, dots, and hyphens only — that keeps the derived sandbox name valid (`^[a-zA-Z0-9][A-Za-z0-9.-]+$`).

What the file sets up:

- **Kit** — `./github-clone` from this checkout (a git source is commented in the file for published use), with `repo=owner/repo` and `dir=/home/agent/workspace`
- **Env** — `OWNER`, `REPO`, and `REPO_SLUG` (`owner/repo`) inside the sandbox
- **Secret** — `github`, resolved by `gh auth token` on the host
- **Binding** — that credential may be used for `api.github.com` (the `gh` REST path) and `github.com` (the git HTTPS transport)

The env file does **not** mount a host workspace. Agent sessions and the cloned tree stay in the sandbox until you remove it.

Public clones work without a token; private repos and in-sandbox `git push` / `gh` writes need the host `gh` to already be logged in.

## Kit only

Skip the env file and pass kit args on the CLI:

```bash
sbx run \
  --kit git+https://github.com/cdupuis/sbx-kits.git#dir=github-clone \
  --arg repo=cdupuis/frontend \
  claude
```

From a checkout of this repo:

```bash
sbx run --kit ./github-clone --arg repo=cdupuis/frontend claude
```

Published OCI image (signed on push to `main`):

```bash
sbx run --kit docker.io/cdupuis/sbx-kits:github-clone --arg repo=cdupuis/frontend claude
```

| Arg | Required | Default | Notes |
|-----|----------|---------|-------|
| `repo` | yes | — | `owner/name`, or a full `https://github.com/…` / `git@github.com:…` URL |
| `ref` | no | default branch | Branch, tag, or commit SHA |
| `dir` | no | `/project` | Absolute path inside the sandbox |

Pin a ref or a different clone path:

```bash
sbx run \
  --kit ./github-clone \
  --arg repo=cdupuis/frontend \
  --arg ref=main \
  --arg dir=/workspace/src \
  claude
```

For private repos without the env file:

```bash
echo "$GITHUB_TOKEN" | sbx secret set -g github
```

## How the kit works

Two `setup.install` hooks run once as root, before the agent starts ([`github-clone/spec.yaml`](github-clone/spec.yaml)):

1. **Install `gh` / `git`** if the base image does not already have them (Debian/Ubuntu via apt).
2. **Clone** with `gh repo clone`, `chown` the tree to `agent`, and point git’s `github.com` credential helper at `gh auth git-credential`.

If `dir` already exists and is non-empty, the clone is skipped so retries do not clobber work.

Auth is proxy-mediated: the kit declares `credentials: - service: github` with `apiKey.name: GH_TOKEN`, `proxyManaged: true`, and inject entries for `api.github.com` and `github.com`. In-container `GH_TOKEN` is a synthetic sentinel (`gho_sbxproxymanaged000000000000000000000`). The sandbox proxy swaps in the host token on requests to those domains. The env file’s binding must list both hosts — a host list of only `api.github.com` silently drops git HTTPS injection.

## Layout

```
github-clone.env.yaml     declarative sandbox (agent + kit + secrets + env)
github-clone/
  spec.yaml               v2 mixin kit
  README.md               kit reference
.github/workflows/
  publish-kit.yml         validate, push, and sign to docker.io/cdupuis/sbx-kits:github-clone
```
