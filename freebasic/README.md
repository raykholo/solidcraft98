# SolidCraft 98 for Linux and the Raspberry Pi

SolidCraft 98 1.2, ported to FreeBASIC. It runs on 64-bit PC Linux and on
an original Raspberry Pi from 2014 (ARMv6, 512 MB). There's no toolkit:
every window, menu and button is drawn by the program itself in the Windows
98 style, in its own pixel font, so it looks the same on every machine.
`.sc98` files are byte for byte the Windows version's, both ways.

Download `SolidCraft98-Linux-1.2.tar.gz` from the
[Releases page](https://github.com/raykholo/solidcraft98/releases): `sc98-pi` for the Pi, `sc98-x86_64` for
a PC. Its `README.TXT` says what a Pi without a desktop needs.

## What's in it

Everything the Windows version 1.2 does: parts with the feature tree,
view and timeline; sketch, extrude, revolve, hole; edit and delete with
dependents; wireframe and shaded views; Save and Open; opening SolidCraft
designs; Export for Rapid Prototyping (.stl); several part windows
(cascade, tile, minimise); Turbo and every egg (Cal, the floppies, DLL
Hell, the WIN98 credits, Y2K with `--y2ktest`, the blue screen, Konami,
Publish to Web), and the remote control, with `--remote` (see the main
README).

| File | What it does |
|---|---|
| `src/sc98.bas` | The program: includes the rest, in order |
| `src/gfx.bas`, `font.bi`, `icons.bi` | Drawing straight into pixel memory; the pixel font and the icons |
| `src/gui.bas`, `dialogs.bas` | Events, message boxes, the number dialog and the file dialog |
| `src/app.bas`, `part.bas` | The main window and every command; part windows |
| `src/model.bas`, `kernel.bas`, `mesh.bas`, `view.bas`, `shade.bas`, `stl.bas` | Features and the `.sc98` file, geometry, triangles, the view, shading, STL |
| `src/expr.bas` | Arithmetic in number boxes |
| `src/zip.bas`, `json.bas`, `import.bas` | Opening SolidCraft designs |
| `src/eggs.bas` | Turbo and the rest |
| `src/remote.bas`, `tutor.bas` | Remote control (`--remote`): commands on standard input, and the tutor |
| `tools/mkfont.py`, `mkicons.py` | Make `font.bi` and `icons.bi` from text pixel art |

## Building

Everything builds in two container images, made from `containers/` with
`containers/build.sh` (podman):

- `sc98-fb-x86`: FreeBASIC 1.10.1 on Ubuntu 22.04.
- `sc98-fb-arm`: a Raspberry Pi OS userland with FreeBASIC's runtime built
  from source for ARMv6 (`tools/arm-rtlib.sh`); FreeBASIC's own ARM
  packages are for ARMv7. Building it needs qemu-user-static on a PC.

Then:

- `./build.sh src/sc98.bas build/sc98` for x86-64
- `./build-arm.sh` for the Pi: fbc writes C for linux-arm, and gcc for
  ARMv6 compiles and links it. Output: `build/arm/sc98`
- `./mkdist.sh` builds both and packs `dist/SolidCraft98-Linux-<v>.tar.gz`

GitHub builds both on every change (`.github/workflows/editions.yml`), and
the release downloads come from there.

On a machine with FreeBASIC installed, `fbc -w all src/sc98.bas -x sc98` is
all it takes.

## Testing

- `./run.sh tests/<script>.txt` runs a UI script headless (x86-64) and turns
  its screenshots into PNGs in `tests/out/`; `./run-arm.sh` does the same
  with the ARM build. Script commands: click, dblclick, drag, move, key,
  type, wait, shot, log, quit.
- `tests/x11.sh` runs it in a virtual X display with real mouse and
  keyboard events (xdotool).
- `tests/core_test.bas` checks the geometry: mesh, STL, rendering, and a
  byte-identical resave.
- `sc98 --headless --bench <part>` times drawing.
