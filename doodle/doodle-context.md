## doodle

This sandbox runs [`docker/doodle`](https://hub.docker.com/r/docker/doodle),
a textured GLB viewer for the terminal built with OpenTUI and Bun. It is the
sandbox's interactive process — there is no coding agent here.

The viewer is at `/app` and renders `/app/moby.glb` unless it is given a
path to another `.glb`. It needs a true-color interactive terminal and exits
with an error when stdin or stdout is a pipe.

| Key | Action |
|---|---|
| Left mouse drag / arrow keys | Rotate the model |
| Scroll wheel, `+` / `-` | Zoom |
| `Space` | Pause or resume rotation and particles |
| `P` / `S` / `T` | Toggle particles / lighting and shadows / textures |
| `R` | Reset the view |
| `Q` or `Escape` | Quit |

The sandbox reaches no network: the model ships in the image.
