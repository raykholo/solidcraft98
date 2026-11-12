# Terminal transport measurements

Measured 2026-11-12 using rustc 1.98.0 (88d9e12ae), release `opt-level="z"`,
LTO, one codegen unit, aborting panics and stripped output. Builds, tests and
clippy ran in the release configuration.
The release demo's `--measure` mode counts bytes using the actual encoder.

## Wire cost

160 columns by 60 rows; nearest-neighbour sampling. The shaded framebuffer
is 160x120 RGB pixels; the wireframe framebuffer is 320x240. The cube starts
at 0.4 radians; each rotation step advances 0.03 radians. A typical step is
the arithmetic mean of 60 consecutive diffed steps (0.43 through 2.2 radians).
Full frames include reset, clear, cursor positioning, colour changes and
UTF-8 glyphs. One-time terminal/mouse setup and size probes are excluded.
An unchanged frame emits **0 bytes**.

Times below are transmission minima: 1 MB/s means 1,000,000 payload bytes/s;
115200 baud assumes 8N1, ten serial bits/byte, or 11,520 bytes/s. They exclude
rendering, terminal parsing, USB/driver overhead and transport stalls.

| Mode | Palette | Cube full bytes | Rotation mean bytes | 1 MB/s full / step | 115200 full / step |
|---|---|---:|---:|---:|---:|
| Shaded | 24-bit | 34,594 | 4,191.5 | 34.594 / 4.192 ms | 3.003 / 0.364 s |
| Shaded | 256 | 32,424 | 3,079.3 | 32.424 / 3.079 ms | 2.815 / 0.267 s |
| Shaded | 16 | 30,691 | 1,857.3 | 30.691 / 1.857 ms | 2.664 / 0.161 s |
| Braille | 24-bit | 35,133 | 6,134.6 | 35.133 / 6.135 ms | 3.050 / 0.533 s |
| Braille | 256 | 32,917 | 5,023.5 | 32.917 / 5.024 ms | 2.857 / 0.436 s |
| Braille | 16 | 31,069 | 4,097.6 | 31.069 / 4.098 ms | 2.697 / 0.356 s |

For true-colour cube rotation, the wire alone allows roughly 239 shaded or
163 Braille frames/s at 1 MB/s, versus 2.75 and 1.88 frames/s at 115200 baud.
These are bandwidth ceilings, not measured frame rates. Braille covers more
samples per cell, so moving a thin line can change more cells than a shaded
surface. The small static cube and its flat background are favourable to
diffing; a busy CAD view or an all-changing image will send more.

The colourful gradient/checker test card gives a less favourable full redraw:

| Mode | Palette | Full bytes | 1 MB/s | 115200 baud |
|---|---|---:|---:|---:|
| Shaded | 24-bit | 367,699 | 367.699 ms | 31.918 s |
| Shaded | 256 | 55,516 | 55.516 ms | 4.819 s |
| Shaded | 16 | 40,305 | 40.305 ms | 3.499 s |
| Braille | 24-bit | 199,272 | 199.272 ms | 17.298 s |
| Braille | 256 | 49,087 | 49.087 ms | 4.261 s |
| Braille | 16 | 37,484 | 37.484 ms | 3.254 s |

Reproduce by running the queued release build's `sc98-term-demo --measure`.
The mean is fractional because individual frames have different byte counts.

## RISC-V release size

Target: `riscv32imc-unknown-none-elf`, release profile above. Both the library
and the linked `size_probe` example cross-build successfully. The probe uses
both display modes, every palette, RGB565, filtering, diffing, resizing,
Ctrl-L handling and the input decoder, retained through `core::hint::black_box`.

| Artifact / section | Bytes |
|---|---:|
| Library `libsc98_term.rlib` | 215,990 |
| Linked stripped probe ELF on disk | 8,628 |
| `.text` | 6,600 |
| `.rodata` | 514 |
| `.eh_frame` | 764 |
| Total loadable content reported by GNU `size` | **7,878** |
| `.data` / `.bss` | 0 / 0 |

The `.rlib` includes Rust metadata and LTO IR, so it is not the flash cost.
The 7,878-byte linked fixture is a reproducible approximation of retained
transport code; board startup, serial driver and final monomorphizations can
change the result. Its previous-cell buffer is stack storage, not `.bss`:
**115,200 bytes for 160x60**, plus framebuffer storage and working stack.
The library borrows this buffer, letting real firmware place it appropriately.
The probe has no board initialization and is not runnable firmware.

Use GNU `size -A` and `stat -c %s` on the queued build's
`riscv32imc-unknown-none-elf/release/examples/size_probe` to reproduce the
section and file sizes. No hardware timing or USB throughput was measured.

## Validation

- `cargo test --manifest-path rust/Cargo.toml -p sc98-term --test terminal`:
  **14 passed**. Includes golden streams in both modes/all palettes, individual
  dot placement, diff/attribute suppression, retry after write failures,
  Ctrl-L/resize/configuration, scaling, input sequence/read-split coverage,
  mouse buttons/modifiers/drag/wheel and malformed input recovery.
- `cargo test --manifest-path rust/Cargo.toml -p sc98-term-demo --test scene`:
  **2 passed**. Repeatable test pattern/cube and rotating diff behaviour.
- Both crates' targeted `cargo clippy --all-targets -- -D warnings`: **passed**;
  the library check also enables all features to include the size example.
- `cargo fmt --manifest-path rust/Cargo.toml --all --check` and
  `git diff --check`: **passed**.
- Queued release demo build, RISC-V library and linked probe builds: **passed**.
- PTY smoke test: **6 configurations passed** (shaded, wireframe, 256 colours,
  16 colours, box filter and test pattern). Checks raw mode, split size probe,
  Ctrl-L, resize, mode changes, mouse reports, Ctrl-Q, exit sequences and exact
  restoration of the original termios settings.

Initial runs exposed a malformed-CPR decoding bug and clippy findings; these
were fixed and their targeted checks passed on rerun. No full local suite was
run. CI is configured for the full workspace, formatting, clippy, RISC-V
release builds and byte measurements after commit/push by the coordinator.
