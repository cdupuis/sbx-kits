# doodle

A v3 **workload** kit that runs [`docker/doodle`](https://hub.docker.com/r/docker/doodle)
— a textured, mouse-controlled GLB viewer for the terminal, built with OpenTUI
and [Bun](https://bun.sh) — as the sandbox's interactive process. Attach to the
sandbox and Moby is spinning in your terminal.

There is no coding agent in this sandbox. The viewer *is* the agent, in the
`sbx@1` sense: the host launches the image's entrypoint as the agent process
rather than as PID 1.

## Usage

From a checkout of this repo:

```console
$ sbx run ./doodle .
```

Published OCI image:

```console
$ sbx run docker.io/cdupuis/sbx-kits:doodle .
```

Pin a different tag of the upstream image:

```console
$ sbx run ./doodle --arg tag=2026 .
```

### Arguments

| Arg   | Required | Default | Notes |
|-------|----------|---------|-------|
| `tag` | no       | `2026`  | `docker/doodle` tag to build from. Must be version-shaped — it is also the kit's `version:` and the version of its `doodle@…` provide, and a moving tag like `latest` is neither. |

### Controls

| Key | Action |
|---|---|
| Left mouse drag / arrow keys | Rotate the model |
| Scroll wheel, `+` / `-` | Zoom |
| `Space` | Pause or resume rotation and particles |
| `P` / `S` / `T` | Toggle particles / lighting and shadows / textures |
| `R` | Reset the view |
| `Q` or `Escape` | Quit |

The viewer needs a true-color interactive terminal — it refuses to start when
stdin or stdout is a pipe.

## How it works

The recipe ([`doodle.dockerfile`](doodle.dockerfile)) is `FROM
docker/doodle:<tag>` plus the **platform floor** a workload owes its runtime
(SPEC-v3 §12). The upstream image is Alpine + busybox and sits below it:

- **`bash`** — `sbx@1` launches the agent under bash so the file named by
  `BASH_ENV` is sourced; Alpine ships none. `git`, `curl` and a CA store are
  installed for the same reason, as floor content composed mixins may assume.
- **The `agent` user** — upstream's uid 1000 is named `bun`, with `/home/bun`
  as its home. It is renamed rather than duplicated, which keeps the uid and
  gid and so leaves `/app` owned by the user that runs the viewer. `shadow` is
  installed for `usermod`/`groupmod` and removed in the same layer.
- **`BASH_ENV`** — points at a shipped, agent-writable
  `/etc/sandbox-persistent.sh`, the sbx persistent-environment convention.
- **`WORKDIR`** is `/home/agent/workspace`, *not* the image's `/app`. `sbx@1`
  places the workspace at the declared working directory, so leaving it at
  `/app` would mount the workspace straight over the viewer. The entrypoint is
  rewritten to the absolute `/app/src/index.js` to match.

Beyond `sbx@1`, the only capability is `agent-context@1`: the workload owns
the context-file profile (`AGENTS.md`) that composed mixins write beside.

**No `network-policy@1`.** The model ships in the image and the viewer reaches
nothing, so the kit asks for no egress and stays at the host's deny-all.

## Building and verifying

```console
$ cd doodle

# descriptor-only check — fails in a second on a bad field
$ docker buildx build . -f doodle.yaml --output type=cacheonly

# build and check conformance
$ docker buildx build . -f doodle.yaml -t doodle:2026 \
    --output type=oci,dest=/tmp/doodle-layout,tar=false
$ kit-tck kit --layout /tmp/doodle-layout 2026
```

The upstream image is published for `linux/amd64` and `linux/arm64`, and this
kit builds for both — but only natively or under QEMU, since the recipe runs
`apk` in the target rootfs. Push both platforms in one `docker buildx build
--platform linux/amd64,linux/arm64 --push` so the tag resolves to one index.

## References

- [Kit descriptor](doodle.yaml)
- [v3 kit spec](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/SPEC-v3.md) — §8 launch modes, §12 runtime environment
- [`sbx@1`](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/capabilities/com.docker.sandbox/sbx@1.md), [`agent-context@1`](https://github.com/docker/sandbox-kit-spec/blob/main/docs/spec/capabilities/com.docker.sandbox/agent-context@1.md) — the capabilities this kit declares
