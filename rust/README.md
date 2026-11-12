# SolidCraft 98 — Embedded Edition

The first screen is the computer at the other end of the USB cable. Open a
UTF-8 ANSI terminal on the serial port: the board sends the picture and the
terminal sends keys and mouse reports back. No companion program is needed.

This part supplies the terminal transport and a PC demonstration. The model,
CAD commands, board firmware and pixel renderer are separate work. There is
no dependency on their crates, and the demonstration draws its own test card
and cube rather than loading a part.

## Try the demonstration

From the repository root:

```sh
cargo build --manifest-path rust/Cargo.toml --release -p sc98-term-demo
```

Run the resulting `sc98-term-demo` binary in a terminal. Cargo puts the binary under `rust/target/release/`. With an
ordinary checkout outside the shared build environment, `cargo run --release
--manifest-path rust/Cargo.toml -p sc98-term-demo` also launches it.

Options: `--wireframe`, `--pattern`, `--256`, `--16`, `--box`, `--help`.
True colour and nearest-neighbour sampling are the defaults. `--measure`
prints deterministic byte counts without entering raw mode. It measures both
display modes and all three colour choices.

Ctrl-Q exits and restores the screen, cursor, mouse modes, wrapping and raw
mode. S switches shading, P switches the test card, B switches filtering,
Space pauses, Left/Right turns the cube, mouse drag turns it and the wheel
zooms. Ctrl-L redraws. Native size changes are polled every 250 ms; startup
also sends a cursor-position probe. The demo supports up to 320x120 cells.

## Board integration

`sc98-term` is `no_std`, has no dependencies and uses no allocation or unsafe
code. Supply a tightly packed framebuffer slice, dimensions and a `Write`
adapter whose `write_all` sends every byte or returns an error. A slice of
`u16` is RGB565; `Rgb` is RGB888; `Palette16` indexes the conventional ANSI
palette. Implement the small `Pixel` trait for another pixel representation
or palette order. There is no dependency on a particular framebuffer library.

```rust
use sc98_term::{Cell, Config, Encoder, Frame, Size, Write};

fn picture<W: Write>(serial: &mut W, pixels: &[u16; 8]) -> Result<(), W::Error> {
    // Keep this array and Encoder alive between frames. An embedded application
    // can place the array in its static memory using its normal safe allocator.
    let mut previous = [Cell::EMPTY; 1];
    let mut encoder = match Encoder::new(
        &mut previous, Size { cols: 1, rows: 1 }, Config::default(),
    ) {
        Ok(encoder) => encoder,
        Err(_) => return Ok(()),
    };
    if let Ok(frame) = Frame::new(pixels, 2, 4) {
        encoder.render(&frame, serial)?;
    }
    Ok(())
}
```

Send `ENTER` once and `EXIT` on exit, including error exits. These enter an
alternate screen, hide the cursor, disable wrapping (including at the bottom
right), and enable mouse modes 1000, 1002 and 1006. They restore those modes
on exit. They assume the usual initial state: mouse off, cursor visible,
wrapping on. Buffer small writes in the serial adapter if that is cheaper
than sending them individually. After a transport error the encoder marks
the whole screen dirty and resets its attribute cache for a complete retry.

Send `SIZE_PROBE` and feed the reply through `Decoder`; forward `Event::Size`
to `Encoder::handle_event`. If no reply arrives, use `Size::default()`:
160x60. Resize validates the previous-cell buffer capacity before changing
state. Allocate a larger buffer if larger terminals are supported; a rejected
resize leaves the old dimensions intact. `handle_event` also handles Ctrl-L.
Use `redraw()` after any external screen writes or reconnect, and `configure()`
to change display mode, palette or sampling.

`Decoder::feed` accepts arbitrary fragments, including UTF-8. It calls a
callback for each event, so no event queue is allocated. Escape is inherently
ambiguous with an escape-sequence prefix: call `escape_timeout()` after an
idle interval (the demo uses 60 ms) to emit a lone Escape. It retains partial
CSI/SS3/UTF-8 sequences across that timeout. `reset()` explicitly cancels an
unfinished sequence. Oversized or unsupported sequences are discarded through
their final byte. Mouse coordinates are zero-based terminal cells; a viewport
adapter must map them to its own pixels. Supported keys include printable
Unicode, control keys, Alt characters, arrows/navigation, F1–F12 using CSI
tilde or CSI/SS3 letter forms, and xterm modifier parameters. Two-parameter
CSI `R` is interpreted as a cursor-position reply; use SS3 F3 if a terminal
otherwise sends the same bytes for modified F3.

Shaded cells use `▀`, with top pixel foreground and bottom pixel background.
Braille uses the standard 2x4 dot order, sets dots for pixels different from
`wire_background` and averages the lit pixels into one foreground colour.
Black is the default wire background; white backgrounds and black lines are
supported too. Braille conveys line coverage, not eight independent colours.

The framebuffer fits the terminal's pixel raster while preserving aspect
ratio and centring unused space. Each terminal cell has physical aspect 1:2:
the raster is cols x (2*rows) for shaded and (2*cols) x (4*rows) for Braille.
Nearest sampling maps integer source coordinates. `Box2x2` averages a clamped
2x2 source neighbourhood at each mapped coordinate; it is a cheap filter,
not a full area resampler. Use a framebuffer near the destination size to
keep very thin wireframe lines when reducing the image.

Colour selection happens at startup/configuration, with nearest RGB distance
to the conventional xterm 256-colour or ANSI 16-colour palette. Terminal
themes may change the actual first 16 colours. Cells store the quantized
result, so invisible changes in a reduced palette send no bytes. Contiguous
changed cells share cursor positioning and attributes; unchanged frames emit
zero bytes. Full redraws clear the screen, including old resize margins.

Previous-frame storage costs 12 bytes/cell: **115,200 bytes at 160x60**, plus
the caller's framebuffer and a small encoder/decoder. Use fewer cells on a
smaller board. The encoder never keeps a second framebuffer or cell array.

## Checks and measurements

Run checks one crate at a time:

```sh
cargo test --manifest-path rust/Cargo.toml -p sc98-term --test terminal
cargo test --manifest-path rust/Cargo.toml -p sc98-term-demo --test scene
cargo clippy --manifest-path rust/Cargo.toml -p sc98-term --all-targets --all-features -- -D warnings
cargo clippy --manifest-path rust/Cargo.toml -p sc98-term-demo --all-targets -- -D warnings
cargo fmt --manifest-path rust/Cargo.toml --all --check
```

CI runs the complete workspace on every push, along with a release cross-build.
`tools/terminal_smoke.py /path/to/sc98-term-demo` exercises a real Unix PTY:
startup, split probe reply, Ctrl-L, resize, display mode change, mouse input,
Ctrl-Q and exact restoration of termios state in six configurations.

For a linked size fixture, install the `riscv32imc-unknown-none-elf` Rust
target and run:

```sh
cargo build --manifest-path rust/Cargo.toml --release -p sc98-term --target riscv32imc-unknown-none-elf
cargo build --manifest-path rust/Cargo.toml --release -p sc98-term --features size-probe --example size_probe --target riscv32imc-unknown-none-elf
```

The fixture retains the encoder (both modes, all palettes), input decoder,
RGB565, filtering, diffing and resize through `black_box`. It is for size
measurement, without board startup or a real serial driver. It places the
previous cells on the stack, so it is not ready-to-flash board firmware.
See [MEASUREMENTS.md](MEASUREMENTS.md) for measured flash/storage and wire costs.
