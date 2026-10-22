# SolidCraft 98 Delphi Edition

SolidCraft 98 1.1.1 in Object Pascal, built with Free Pascal and Lazarus:
the Delphi 4 way, with real widgets. One source for Windows (and ReactOS),
64-bit PC Linux and the Raspberry Pi 1 and up. Same features as the Visual
Basic version, and the same `.sc98` files byte for byte.

Download `SolidCraft98-Delphi-1.1.1.zip` from the
[Releases page](https://github.com/raykholo/solidcraft98/releases). It has `SolidCraft98.exe` for Windows,
`sc98-x86_64` for Linux and `sc98-pi` for the Pi. The Linux ones need GTK 2
(`sudo apt install libgtk2.0-0`).

Also in this edition: the splash says so, and the About box knows a word
that the Visual Basic version doesn't.

## What's where

| | |
|---|---|
| `SolidCraft98.lpr`, `.lpi` | the program and the Lazarus project |
| `src/umodel.pas` | features, designs, the `.sc98` file (packed records) |
| `src/ukernel.pas`, `umesh.pas`, `ushade.pas`, `uview.pas` | geometry, triangles, the shaded view, projection |
| `src/uexpr.pas` | arithmetic in number boxes, and VB's `Val` |
| `src/uzip.pas`, `ujson.pas`, `uimport.pas` | opening SolidCraft designs |
| `src/ustl.pas`, `ugif.pas` | STL export; GIFs for Publish to Web |
| `src/udocs.pas` | open parts, message boxes, Turbo, the clock |
| `src/ucommands.pas` | every command, one copy each |
| `src/fmain.pas`, `fpart.pas`, `fdialogs.pas` | the windows, built in code |
| `src/uart.pas`, `icondata.inc` | icons (from `tools/mkicons.py`), gradients, the logo |
| `tests/` | `coretest.pas` and the screen tests |

Part windows are panels with their own caption bars inside the main
window's grey area: Lazarus has MDI only on Windows, and these work on
every platform.

## Build

With Lazarus installed, on any of the three:

    lazbuild SolidCraft98.lpi                      # build/SolidCraft98
    lazbuild --build-mode=Debug SolidCraft98.lpi   # with range checks and line numbers

The release downloads are built by GitHub
(`.github/workflows/editions.yml`): Linux and Windows on its runners, the
Pi in an emulated Raspberry Pi OS. By hand:

- Linux: `./build.sh`, in the `sc98-lz-x86` image (Ubuntu 22.04, FPC 3.2.2,
  Lazarus 2.2).
- Raspberry Pi: `./build-arm.sh`, in the emulated `sc98-lz-arm` image
  (Raspberry Pi OS bullseye, Lazarus 2.0). Output: `build/arm/SolidCraft98`.
- Windows: Lazarus 3.6, 32-bit, `lazbuild SolidCraft98.lpi`. The EXE goes
  in `build/win/` for packing.
- `./mkdist.sh` packs all three into `dist/`.

The images are made from `containers/` with `containers/build.sh`
(podman; the ARM one needs qemu-user-static on a PC).

## Tests

    fpc -O2 -Fusrc -Fu<lazutils units> -FUbuild -obuild/coretest tests/coretest.pas && build/coretest
    podman run --rm -v "$PWD":/w:Z -w /w sc98-lz-x86 bash tests/x11.sh tests/ui-basic.sh

The screen tests run the program on a virtual screen and leave screenshots
in `tests/out`: `ui-basic` (a box with a hole, shaded), `ui-turbo` (type
mismatches, the blue screen, the solver), `ui-about` (WIN98, DELPHI, DLL
Hell, cascade and tile), `ui-files` (save, open, import, STL, Publish,
the floppy, quitting), `ui-misc` (edit, delete, revolve, undo, Konami;
run with `--y2ktest` and wait a minute for Y2K).
