# SolidCraft 98 terminal application report

The shared program is in `sc98-app`. `sc98-term-app` supplies a raw terminal
and current-directory files; `sc98-esp32` supplies a serial terminal and a
bounded RAM store. The app uses actual core parts through a borrowed pixel
adapter, not DemoPart. No board was flashed.

## Program behavior

- Classic and compact desktop, real feature tree/timeline and geometry.
- Decoded keys/mouse, menu/toolbar dispatch, orbit/pan/zoom, shaded/wireframe.
- New part or bundled Mounting Plate, `.sc98` load/save by name.
- Rectangle/circle sketches, placement on a selected extrude, extrude,
  revolve, hole, editing every parameter and deletion with descendants.
- Arithmetic in number boxes, reference/containment/dimension checks.
- Binary STL export at the core's 64-segment resolution; display meshes use
  16 segments and reference wire edges use 32. Omitted-body mesh warnings
  prevent silent partial STL export.
- A tick owns all app work; no app or firmware threads. Idle ticks reuse the
  framebuffer and the terminal encoder sends no bytes for unchanged cells.

This is a single-document app. New/Close/Exit discard unsaved changes. Floppy,
Publish and Window menu entries retain messages/status rather than the
reference's floppy show, web page output or multiple windows. The separate
`sc98-desktop` and `sc98-term-demo` previews remain available.

## Verification

The shared app integration test file passes all 12 tests, including byte-exact
scripted STL, sample STL, save/open, all menu commands, edits/deletion, mouse
scaling, RGB332 and unchanged-frame diffing. The pixel graphics file passes
all 8 tests, including its existing goldens. Current-directory storage passes
its test; both firmware runner tests pass, including transport-error cleanup.
Clippy passes for all four changed crates with warnings denied. Workspace
format checking passes. The PC release build passes, and a real Unix PTY smoke
test checks probe handling, rectangle/extrude, save/STL, quit and exact termios
restoration. [The terminal capture](docs/terminal-app.png) is reconstructed from
the executable's actual ANSI output; its colour/cursor/PNG helper also passes a
small independent pixel/CRC check. Linked firmware sizes are recorded below. 
only targeted crate/test-file tests and crate clippy are authorized locally.
The full workspace suite is reserved for CI after push. Changes remain
unstaged, and `COMMIT_MSG.txt` contains the proposed commit message.

Direct rustfmt checks of every changed Rust file and `git diff --check` pass.
The PC host and app compile successfully. A direct request to static.crates.io
failed DNS resolution in the sandbox, but the remote builder downloaded the
ESP dependencies. Its first C3 check stopped because its Rust toolchain lacks
the RISC-V target; this was not a source-code compilation result. The local
builder has the target installed on stable release toolchains.

Commands run:

| Cargo arguments (all use `--manifest-path rust/Cargo.toml`) | Final result |
|---|---|
| `check -p sc98-app -p sc98-term-app` | Pass |
| `test -p sc98-app --test program` | 12 pass |
| `test -p sc98-pixels --test graphics` | 8 pass |
| `test -p sc98-term-app --test storage` | 1 pass |
| `test -p sc98-esp32 --test stream` | 2 pass |
| `clippy -p sc98-app --all-targets -- -D warnings` | Pass |
| `clippy -p sc98-pixels --all-targets -- -D warnings` | Pass |
| `clippy -p sc98-term-app --all-targets -- -D warnings` | Pass |
| `clippy -p sc98-esp32 --all-targets --all-features -- -D warnings` (host) | Pass |
| `fmt --all --check` | Pass |
| `build -p sc98-term-app --release` | Pass |

`python3 rust/tools/app_smoke.py <release-executable>` passes. The initial app
run caught missing keyboard orbit mapping; that was corrected and its complete
targeted file passed on rerun. A test-only clippy slice-size warning was also
corrected before the successful clippy rerun. No workspace test suite ran locally.

## RAM budget

Exact framebuffer and diff-buffer costs (independent of allocator overhead):

| Allocation | Bytes |
|---|---:|
| PC compact RGB565, 320 × 240 | 153,600 |
| PC classic RGB565, 640 × 480 | 614,400 |
| Firmware compact RGB332, 320 × 240 | 76,800 |
| Firmware terminal previous cells, 160 × 60 × 12 | 115,200 |
| PC maximum previous cells, 320 × 120 × 12 | 460,800 |
| Firmware framebuffer + previous cells | 192,000 |
| Firmware heap reservation | 307,200 |
| Firmware RAM file contents limit (allocated on demand) | 32,768 |

The sample display cache on the measured 64-bit host is 46,400 bytes:
512 pixel triangles (52 bytes each), 560 edges (28 bytes each) and 512 painter
indices (8 bytes each). On a 32-bit target these indices use 4 bytes each,
for an estimated 44,352-byte cache. The core Feature record measures 104 bytes
on the host (64 allocated records: 6,656 bytes, plus strings); the expected
32-bit layout is 80 bytes (5,120 bytes plus strings). At 16/32/64 segments,
the sample has 512/992/1,952 core triangles.

The remaining 115,200 bytes inside the firmware heap must accommodate model
records/strings, cached display triangles/edges, painter indices, file data
and temporary meshes. There is no depth buffer. The 64-record core model
allocates all records even for a new part. Export drops the display cache
before building its double-precision 64-segment mesh, then restores the
cache. The STL byte vector also consumes RAM.

The Mounting Plate STL has 1,952 triangles and 97,684 output bytes. Its
triangle records alone use 265,472 bytes on a 64-bit host (136 each); even
without the output vector this exceeds the remaining C3 heap. Small parts
are the intended C3 starting point. Large-model allocation recovery and
streaming STL/geometry are still needed for reliable operation with all
samples on small chips. Larger ESP32 variants with PSRAM need explicit heap
configuration; it is not silently assumed here.

For the other reference samples, the core's validated converted fixtures give
these STL-stage estimates. This counts triangle records and output bytes, not
scratch vectors, strings, framebuffer or terminal storage. The 32-bit estimate
uses a 128-byte core triangle layout; the measured 64-bit layout is 136 bytes.
The app currently opens native `.sc98`; `.solidcraft` import is not exposed.

| Sample | Features | STL triangles | Triangle bytes, host | Triangle bytes, 32-bit estimate | STL bytes |
|---|---:|---:|---:|---:|---:|
| Mounting Plate | 9 | 1,952 | 265,472 | 249,856 | 97,684 |
| Plate with holes | 10 | 1,952 | 265,472 | 249,856 | 97,684 |
| Flange | 8 | 1,552 | 211,072 | 198,656 | 77,684 |
| Revolved parts | 4 | 6,780 | 922,080 | 867,840 | 339,084 |

## Hardware and size status

Measured on 2026-11-12 with **stable rustc 1.98.0** (88d9e12ae), release
`opt-level = "z"`, LTO, one codegen unit, panic abort and stripping:

| Linked C3 image measure | Bytes | Fraction of a 1,474,560-byte floppy |
|---|---:|---:|
| ELF file | 165,752 | 11.24% |
| Sum of nonempty PT_LOAD file contents | 133,472 | 9.05% |

The ELF fits with **1,308,808 bytes to spare**. These are linked firmware
measurements, not rlib archive sizes. Flash image headers/padding and a board's
bootloader/partition table are additional; no image was flashed.

`size -A` gives the retained loadable sections:

| Section | Bytes |
|---|---:|
| `.trap` | 1,040 |
| `.rwtext` | 920 |
| `.text` | 103,900 |
| `.data` | 264 |
| `.rodata` | 27,348 |
| **Loadable section payload** | **133,472** |
| `.bss` (RAM; includes the 307,200-byte heap) | 307,400 |

The linker also reports `.rwdata_dummy` (1,960) and `.text_dummy` (130,840),
both NOBITS address-space reservations, plus non-loadable `.eh_frame` (14,188),
`.comment` (139) and `.riscv.attributes` (54). They must not be added to the
flash payload. The raw `size -A` total, 588,053, includes these reservations
and BSS and therefore is not flash usage. IRAM code, data and BSS reserve
approximately **309,624 bytes of physical SRAM**, counting the IRAM/DRAM alias
reservation once; stack headroom and hardware high-water usage are unmeasured.
The app framebuffer/model/diff buffers are allocated inside the reserved heap,
not additional static SRAM to add on top of it.

Per-crate attribution is unavailable: cargo-bloat is not installed, and the
release symbols are stripped. The section breakdown above supplies the linked
measurement. ELF SHA-256: `dac3a2a0d5efa1a5d10cfd34697e02fb8d645cd4b44e7f840e3e07666411a133`.

The completed commands:

- `cargo +1.98.0 build -p sc98-esp32 --release --target riscv32imc-unknown-none-elf`: pass.
- `cargo +1.98.0 clippy -p sc98-esp32 --bin sc98-esp32 --release --target riscv32imc-unknown-none-elf -- -D warnings`: pass.

The first build caught the esp-alloc 0.6 macro's positional argument;
that was fixed before the passing release build. The gated original-ESP32
UART path uses the HAL's nonblocking `read_buffered_bytes` API. Cargo reports
a dependency future-compatibility advisory for proc-macro-error2 2.0.1; current
builds and clippy pass.

Chip features select esp-hal's C3/C6/S3/original ESP32 support. C3/C6/S3 use
native USB Serial/JTAG; original ESP32 uses UART0 on GPIO1/GPIO3. The C3
release build and target clippy pass. C6 requires another Rust
target. Xtensa builds require the separately installed Espressif toolchain;
that toolchain is absent here. These variants must remain feature-gated.

Physical USB/UART reception, boot/heap headroom, sustained input while a full
frame is transmitted, terminal reconnects and pin routing require a board.
File contents are volatile. There is no flash filesystem or hardware test,
and no claim of a completed hardware run.
