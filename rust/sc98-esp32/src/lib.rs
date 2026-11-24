//! Board-independent serial terminal runner. No board is accessed by host tests.
#![no_std]
#![forbid(unsafe_code)]
extern crate alloc;
use alloc::vec;
use sc98_app::{App, Layout, RamStorage, Rgb332};
use sc98_term::{Cell, Config, Decoder, Encoder, Event, Size, Write, ENTER, EXIT, SIZE_PROBE};

/// Nonblocking input, blocking output, and a ten-millisecond idle interval.
/// Drivers must not print logs into this byte stream while the app owns it.
pub trait Stream: Write {
    fn read_byte(&mut self) -> Result<Option<u8>, Self::Error>;
    fn idle(&mut self);
}
#[derive(Debug)]
pub enum Error<E> {
    Transport(E),
    Screen,
    App,
}

/// Compact screen, 160x60 cells, 32 KiB of volatile file data. Returns on Ctrl-Q.
/// The allocator and physical byte stream are supplied by the firmware host.
pub fn run<T: Stream>(serial: &mut T) -> Result<(), Error<T::Error>> {
    serial.write_all(ENTER).map_err(Error::Transport)?;
    let result = session(serial);
    let exit = serial.write_all(EXIT).map_err(Error::Transport);
    result.and(exit)
}
fn session<T: Stream>(serial: &mut T) -> Result<(), Error<T::Error>> {
    serial.write_all(SIZE_PROBE).map_err(Error::Transport)?;
    let mut app = App::<_, Rgb332>::new(
        Layout::Compact,
        RamStorage::new(32 * 1024),
        sc98_core::Part::new("Part1"),
    )
    .map_err(|_| Error::App)?;
    let size = Size {
        cols: 160,
        rows: 60,
    };
    let mut cells = vec![Cell::EMPTY; 160 * 60];
    let mut encoder =
        Encoder::new(&mut cells, size, Config::default()).map_err(|_| Error::Screen)?;
    app.tick(Some(Event::Size(size))).map_err(|_| Error::App)?;
    let mut decoder = Decoder::new();
    let mut idle = 0u8;
    loop {
        let frame = app.tick(None).map_err(|_| Error::App)?;
        encoder.render(&frame, serial).map_err(Error::Transport)?;
        // Process a bounded burst; encoder sends only the final changed cells.
        let mut received = false;
        for _ in 0..256 {
            let Some(byte) = serial.read_byte().map_err(Error::Transport)? else {
                break;
            };
            received = true;
            let mut failure = false;
            decoder.feed(&[byte], |event| {
                let event = match event {
                    Event::Size(s) => Event::Size(Size {
                        cols: s.cols.clamp(1, 160),
                        rows: s.rows.clamp(1, 60),
                    }),
                    e => e,
                };
                if encoder.handle_event(event).is_err() || app.tick(Some(event)).is_err() {
                    failure = true;
                }
            });
            if failure {
                return Err(Error::App);
            }
        }
        if app.quit {
            return Ok(());
        }
        if received {
            idle = 0;
        } else {
            idle = idle.saturating_add(1);
            if idle >= 6 {
                if let Some(event) = decoder.escape_timeout() {
                    app.tick(Some(event)).map_err(|_| Error::App)?;
                }
            }
            serial.idle();
        }
    }
}
