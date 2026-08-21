# github-clone

A v2 mixin that clones a GitHub repository into the sandbox at
sandbox-create time, at a directory you choose (`/project` by default),
using the [`gh` CLI](https://cli.github.com/) with a **proxy-managed
`GH_TOKEN` sentinel** so private repos and authenticated writes work
without ever handing the real token to the container.

The recommended way to run this kit is the repo-root
[`github-clone.env.yaml`](../github-clone.env.yaml) environment file, which
clones into `/home/agent/workspace` with no host workspace bind. See the
[root README](../README.md) for that flow. The rest of this page is the
kit-only `sbx run --kit` interface.

## Usage

Public repo — no host-side setup required:

```console
$ sbx run \
    --kit "git+https://github.com/cdupuis/sbx-kits.git#dir=github-clone" \
    --arg repo=cdupuis/sbx-kits \
    claude
```

Private repo (or if you want authenticated pushes/pulls from inside the
sandbox) — bind a GitHub token on the host once:

```console
$ echo "$GITHUB_TOKEN" | sbx secret set -g github
```

then run the same `sbx run …` command. The sandbox proxy substitutes the
real token onto every outbound request to `api.github.com` and `github.com`;
`gh` and `git` only ever see a synthetic sentinel — for GitHub that is
`GH_TOKEN=gho_sbxproxymanaged000000000000000000000`, never the real token.

### Arguments

| Arg    | Required | Default    | Notes |
|--------|----------|------------|-------|
| `repo` | yes      | —          | `owner/name` shorthand, or a full `https://github.com/…` or `git@github.com:…` URL. |
| `ref`  | no       | *(default branch)* | Branch, tag, or 7–40 hex commit SHA to check out. |
| `dir`  | no       | `/project` | Absolute path inside the sandbox to clone into. |

Examples:

```console
# Clone a specific ref into /workspace/src instead of /project
$ sbx run \
    --kit "git+https://github.com/cdupuis/sbx-kits.git#dir=github-clone" \
    --arg repo=cdupuis/sbx-kits \
    --arg ref=main \
    --arg dir=/workspace/src \
    claude

# Clone a full HTTPS URL — same result as the shorthand above
$ sbx run \
    --kit "git+https://github.com/cdupuis/sbx-kits.git#dir=github-clone" \
    --arg repo=https://github.com/cdupuis/sbx-kits.git \
    claude
```

## How it works

- **When**: two `setup.install` hooks run once, as `root`, before the agent
  launches. The first ensures `gh` (and `git`) are installed; the second
  runs `gh repo clone`, `chown`s the resulting tree to the `agent` user,
  and writes a `--system` git credential-helper entry pointing at
  `gh auth git-credential` (so any later `git push` / `git pull` from the
  sandbox picks up the same proxy-managed `GH_TOKEN` sentinel).
- **Auto-install**: if `gh` is missing from the base image, the mixin adds
  GitHub's official apt source (`cli.github.com`) and
  `apt-get install`s it. Skipped entirely on bases that already carry
  `gh`, so the apt-get network cost is paid only when needed. On
  non-Debian bases the mixin fails with an actionable error pointing at
  layering a companion install mixin instead.
- **Auth**: `credentials: - service: github` with `apiKey.name: GH_TOKEN`,
  `proxyManaged: true`, and `inject` entries for `api.github.com` (the
  `gh` REST path) and `github.com` (the git HTTPS transport). The
  in-container `GH_TOKEN` is a synthetic sentinel
  (`gho_sbxproxymanaged000000000000000000000`); the sandbox proxy swaps in
  the real token on outbound requests. This is the same convention the
  built-in `claude-acp` / `codex-acp` kits document.

  The host side must allow both domains too — a binding is intersected
  with what the kit requests, so a host list of only `api.github.com`
  silently drops the `github.com` injection.
- **Re-run safety**: if `dir` already exists and is non-empty (e.g. on
  `sbx create` retries), the clone is skipped rather than failing or
  clobbering.
- **`ref` handling**: branches and tags use `--depth 1 --branch`; if that
  fails (commit SHAs aren't valid `--branch` args) it falls back to a full
  clone + `git checkout`.
- **Network contract**: two groups, both listed in
  `permissions.network.allow`:
  - **Runtime** (`gh` + `git`): `api.github.com`, `github.com`,
    `codeload.github.com`, `raw.githubusercontent.com`.
  - **apt-install path** (only used when the base lacks `gh`):
    `cli.github.com`, `archive.ubuntu.com`, `security.ubuntu.com`,
    `ports.ubuntu.com`, `download.docker.com`. The Ubuntu + Docker hosts
    are the usual `apt-get update` cascade — `apt-get update` refreshes
    every configured source, so all four must be reachable even though
    we only fetch from `cli.github.com`. That is the complete outbound
    contract — under a `deny-all` host policy nothing else is reachable.

## SSH clones

Pass `repo=git@github.com:owner/name.git` and layer the
[`github-ssh`](https://github.com/docker/sbx-kits-contrib/tree/main/github-ssh) mixin so GitHub's host keys are
pre-populated and the host's `ssh-agent` is forwarded. In that mode the
`GH_TOKEN` sentinel is unused for the clone itself, though `gh api`
inside the sandbox still routes through the proxy.

## References

- [Kit spec](spec.yaml)
- [v2 spec grammar](https://github.com/docker/sbx-kits-contrib/blob/main/spec/SPEC-v2.md) — `args:` (§2.1), `credentials:` (§5.4), `setup:` (§5.6)
- [Kit-author bindings guide](https://github.com/docker/sbx-kits-contrib/blob/main/skills/kit-author/topics/bindings.md) — how the `github` credential binding is discovered on the host
- [`github-ssh`](https://github.com/docker/sbx-kits-contrib/tree/main/github-ssh) — companion mixin for SSH-based clones
