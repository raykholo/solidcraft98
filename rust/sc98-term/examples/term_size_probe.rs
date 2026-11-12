//! Linked size fixture, not board firmware. Exercises both modes, all palettes,
//! RGB565 input, scaling, diffing, resize, redraw and the streaming input decoder.
#![cfg_attr(target_arch = "riscv32", no_std)]
#![cfg_attr(target_arch = "riscv32", no_main)]

#[cfg(not(target_arch = "riscv32"))]
fn main() {
    println!("Build this size fixture for riscv32imc-unknown-none-elf.");
}

#[cfg(target_arch = "riscv32")]
mod embedded {
    use core::{convert::Infallible, hint::black_box};
    use sc98_term::*;

    struct Serial;
    impl Write for Serial {
        type Error = Infallible;
        fn write_all(&mut self, bytes: &[u8]) -> Result<(), Infallible> {
            black_box(bytes);
            Ok(())
        }
    }

    // The linker entry is the only exported ABI symbol; it needs no unsafe code.
    #[no_mangle]
    pub extern "C" fn _start() -> ! {
        let mut previous = [Cell::EMPTY; 160 * 60];
        let pixels = black_box([0xf800_u16, 0, 0, 0x07e0, 0, 0x001f, 0xffff, 0]);
        if let Ok(frame) = Frame::new(&pixels, 2, 4) {
            if let Ok(mut encoder) = Encoder::new(&mut previous, Size::default(), Config::default())
            {
                let mut decoder = Decoder::new();
                decoder.feed(black_box(b"\x1b[60;160R\x1b[<0;2;3M\x0c"), |event| {
                    black_box(encoder.handle_event(event)).ok();
                });
                let mut serial = Serial;
                for mode in [Mode::Shaded, Mode::Wireframe] {
                    for colours in [
                        ColourMode::TrueColour,
                        ColourMode::Ansi256,
                        ColourMode::Ansi16,
                    ] {
                        encoder.configure(black_box(Config {
                            mode,
                            colours,
                            filter: Filter::Box2x2,
                            ..Config::default()
                        }));
                        black_box(encoder.render(&frame, &mut serial)).ok();
                        black_box(encoder.render(&frame, &mut serial)).ok();
                    }
                }
            }
        }
        loop {
            core::hint::spin_loop();
        }
    }

    #[panic_handler]
    fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
        loop {
            core::hint::spin_loop();
        }
    }
}
