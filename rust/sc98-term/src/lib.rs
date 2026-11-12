#![no_std]
#![forbid(unsafe_code)]

//! A byte transport between a framebuffer and an ordinary UTF-8 ANSI terminal.
//! The caller owns the previous-cell buffer, the framebuffer and the serial I/O.
//! No heap, operating system, clock, or pixel-layer dependency is required.

mod encoder;
mod frame;
mod input;

pub use encoder::{Cell, ColourMode, Config, Encoder, Error, Mode, Write};
pub use frame::{Filter, Frame, FrameError, Palette16, Pixel, Rgb, Size, ANSI16};
pub use input::{Button, Decoder, Event, Key, KeyEvent, Modifiers, Mouse, MouseKind, Wheel};

/// Enter an alternate screen, hide the cursor, disable wrapping and enable SGR mouse.
pub const ENTER: &[u8] = b"\x1b[?1049h\x1b[?25l\x1b[?7l\x1b[?1000h\x1b[?1002h\x1b[?1006h";
/// Restore mouse, attributes, wrapping, cursor and the previous screen.
pub const EXIT: &[u8] = b"\x1b[?1006l\x1b[?1002l\x1b[?1000l\x1b[0m\x1b[?7h\x1b[?25h\x1b[?1049l";
/// Clamp a cursor move to the bottom right and request its position, preserving cursor.
/// A reply `CSI rows;cols R` becomes `Event::Size`; use 160x60 if no reply arrives.
pub const SIZE_PROBE: &[u8] = b"\x1b7\x1b[9999;9999H\x1b[6n\x1b8";
