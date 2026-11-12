Validation on 2026-11-12, rustc 1.90.0 (x86_64 Linux).

1. Done: Part, feature list, rectangle/circle sketches, extrude, Y revolve,
   straight-down holes, edit, dependent deletion and rebuild.
2. Done: version-5 .sc98 codec, version-3/4 conversion, every native and
   SolidCraft design in samples/, freebasic/tests/ and delphi/tests/;
   reference-compatible saves and the core_test.bas non-rendering checks.
3. Done: meshing and binary STL. Built and ran FreeBASIC 1.10.1's unchanged
   geometry/import/STL sources in a headless harness. All four reference STLs
   match every byte; public triangle coordinates, order and owners match
   reference hashes. The full FreeBASIC GUI was not built.
4. Done: documented pixel-facing Part, feature list, f32 vertices, normals,
   colours and ownership in README.md. Compatibility geometry retains f64
   intermediates to preserve the other editions' bytes; this is an explicit
   exception to using f32 throughout and costs extra mesh RAM.
5. Done: minimal rust/ workspace, release profile, lockfile and build-output
   ignore rule. CI runs the complete workspace after a push.

Completed local commands (from rust/, sequential Rust builds, limited to
sc98-core; Cargo build/test/check/clippy commands used `nice -n 10` and `-j 4`):

- `cargo check -p sc98-core --no-default-features`: passed.
- `cargo check -p sc98-core --features import`: passed.
- `cargo test -p sc98-core --test core`: 10 passed.
- `cargo test -p sc98-core --test import --features import`: 5 passed.
- `cargo test -p sc98-core --doc --all-features`: 1 passed.
- `cargo clippy -p sc98-core --all-targets --all-features -- -D warnings`:
  passed.
- `cargo fmt --all --check`: passed.
- `python3 sc98-core/tests/reference.py` with the cached FreeBASIC compiler and
  library paths: verified all 13 reference fixture files. The reference
  compiler emitted its existing mixed-boolean warnings; execution succeeded.

Passed: `cargo build -p sc98-core --release --no-default-features
--target riscv32imc-unknown-none-elf`. The resulting `libsc98_core.rlib` is
495,630 bytes (484.0 KiB), including Rust metadata and LTO bitcode. This is a
library archive size, not a linked firmware flash-size claim.

Passed: the same RISC-V release build with `--features import`, confirming
that import and its dependencies also compile without std. The resulting core
archive is 766,256 bytes (748.3 KiB); dependency archives are separate.

CI repeats the full workspace tests, the RISC-V cross-build and these size measurements on every push.
