# Pixel layer: measurements and checks

Measured on an AMD Ryzen 7 3700X PC with Rust 1.90.0.
## Rendering time

Release (`opt-level = "z"`, LTO, one codegen unit), 320 × 240, a cylinder
with 100 top triangles and 200 wall triangles. Mean of 120 fixed-view
frames after one warm-up, excluding allocation, PNG encoding and window
presentation. Buffers are reused. This is a host CPU guide, not an MCU
performance claim.

| Mode | Mean frame time |
|---|---:|
| Flat shading with depth and face buffers | 8.839 ms |
| Flat shading with painter sorting | 8.806 ms |
| Wireframe | 1.293 ms |

Command: `cargo test -p sc98-desktop --test render frame_time_300_triangles --release -j 4 -- --nocapture`
(or the desktop executable's `--benchmark`).

## RV32 release size

`sc98-pixels` and its linked `pixels_size_probe` example built successfully for
`riscv32imc-unknown-none-elf`, using the workspace's size-oriented release
settings. The target was initially unavailable; it became available during
this session, and both cross-builds subsequently passed.

| Artifact | Bytes |
|---|---:|
| Library archive `libsc98_pixels.rlib` | 561,942 |
| Stripped linked `pixels_size_probe` ELF file | 87,460 |
| Linked text/read-only data reported by `size` | 86,716 |
| Linked initialized data / BSS | 0 / 0 |

The archive includes compiler metadata and bitcode, so its size is not a
flash requirement. The linked probe retains both layouts, both framebuffer
formats, wireframe and painter shading, and input/widgets. It supplies its
large buffers on the stack; these are not represented by BSS. It has no
board startup, linker memory map or display driver. Actual firmware size
and RAM use depend on retained features and caller-owned buffers.

## Checks

- `cargo test -p sc98-pixels`: the graphics tests against the checked-in RGB565 goldens pass.
- `cargo test -p sc98-desktop`: the render tests pass (framebuffer PNGs, 300-triangle timing).
- `cargo clippy -p sc98-pixels -p sc98-desktop --all-targets -- -D warnings` and `cargo fmt --check` pass.
- `sc98-pixels` and its size probe build for `riscv32imc-unknown-none-elf` (sizes above).
