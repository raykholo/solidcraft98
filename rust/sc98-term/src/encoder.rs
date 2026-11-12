use crate::{Event, Filter, Frame, Key, Modifiers, Pixel, Rgb, Size, ANSI16};

/// Write all bytes, or return an error. A serial adapter may block until sent.
pub trait Write {
    type Error;
    fn write_all(&mut self, bytes: &[u8]) -> Result<(), Self::Error>;
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ColourMode {
    #[default]
    TrueColour,
    Ansi256,
    Ansi16,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Mode {
    #[default]
    Shaded,
    Wireframe,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Config {
    pub mode: Mode,
    pub colours: ColourMode,
    pub filter: Filter,
    /// Wireframe dots are pixels different from this colour (normally black).
    pub wire_background: Rgb,
}

/// Opaque previous-frame storage. Twelve bytes per cell; usable in a static array.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cell {
    fg: u32,
    bg: u32,
    glyph: u16,
}

impl Cell {
    pub const EMPTY: Self = Self {
        fg: 0,
        bg: 0,
        glyph: 0,
    };
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    EmptySize,
    Capacity,
}

/// Borrows a fixed buffer: no framebuffer copy, heap or maximum-size stack frame.
pub struct Encoder<'a> {
    previous: &'a mut [Cell],
    size: Size,
    config: Config,
    dirty: bool,
    fg: Option<u32>,
    bg: Option<u32>,
}

impl<'a> Encoder<'a> {
    pub fn new(previous: &'a mut [Cell], size: Size, config: Config) -> Result<Self, Error> {
        validate(size, previous.len())?;
        Ok(Self {
            previous,
            size,
            config,
            dirty: true,
            fg: None,
            bg: None,
        })
    }

    pub fn size(&self) -> Size {
        self.size
    }
    pub fn config(&self) -> Config {
        self.config
    }

    /// Validate before changing state. A too-large resize leaves the old size intact.
    pub fn resize(&mut self, size: Size) -> Result<(), Error> {
        validate(size, self.previous.len())?;
        if size != self.size {
            self.size = size;
            self.redraw();
        }
        Ok(())
    }

    pub fn configure(&mut self, config: Config) {
        if config != self.config {
            self.config = config;
            self.redraw();
        }
    }

    pub fn redraw(&mut self) {
        self.dirty = true;
        self.fg = None;
        self.bg = None;
    }

    /// Pass decoded events here to handle Ctrl-L and cursor-position probe replies.
    pub fn handle_event(&mut self, event: Event) -> Result<(), Error> {
        match event {
            Event::Size(size) => self.resize(size),
            Event::Key(key)
                if key.key == Key::Char('l') && key.modifiers.contains(Modifiers::CTRL) =>
            {
                self.redraw();
                Ok(())
            }
            _ => Ok(()),
        }
    }

    /// Start/resize/Ctrl-L clears and redraws; unchanged frames write zero bytes.
    /// On an I/O error the next call retries a complete redraw, including attributes.
    pub fn render<P: Pixel, W: Write>(
        &mut self,
        frame: &Frame<'_, P>,
        out: &mut W,
    ) -> Result<(), W::Error> {
        let result = self.render_inner(frame, out);
        if result.is_err() {
            self.redraw();
        }
        result
    }

    fn render_inner<P: Pixel, W: Write>(
        &mut self,
        frame: &Frame<'_, P>,
        out: &mut W,
    ) -> Result<(), W::Error> {
        if self.dirty {
            out.write_all(b"\x1b[0m\x1b[2J")?;
            self.fg = None;
            self.bg = None;
        }
        let mut cursor = None;
        let cols = usize::from(self.size.cols);
        for y in 0..self.size.rows {
            for x in 0..self.size.cols {
                let cell = self.cell(frame, x, y);
                let i = usize::from(y) * cols + usize::from(x);
                if !self.dirty && self.previous[i] == cell {
                    continue;
                }
                if cursor != Some((x, y)) {
                    out.write_all(b"\x1b[")?;
                    number(out, u32::from(y) + 1)?;
                    out.write_all(b";")?;
                    number(out, u32::from(x) + 1)?;
                    out.write_all(b"H")?;
                }
                if self.fg != Some(cell.fg) {
                    colour(out, cell.fg, false, self.config.colours)?;
                    self.fg = Some(cell.fg);
                }
                if self.bg != Some(cell.bg) {
                    colour(out, cell.bg, true, self.config.colours)?;
                    self.bg = Some(cell.bg);
                }
                // All glyphs are in the BMP; encode_utf8 avoids any unsafe conversion.
                if let Some(glyph) = char::from_u32(u32::from(cell.glyph)) {
                    let mut bytes = [0; 4];
                    out.write_all(glyph.encode_utf8(&mut bytes).as_bytes())?;
                }
                self.previous[i] = cell;
                cursor = Some((x + 1, y));
            }
        }
        self.dirty = false;
        Ok(())
    }

    fn cell<P: Pixel>(&self, frame: &Frame<'_, P>, x: u16, y: u16) -> Cell {
        let config = self.config;
        let (dx, dy) = match config.mode {
            Mode::Shaded => (1, 2),
            Mode::Wireframe => (2, 4),
        };
        let width = u32::from(self.size.cols) * dx;
        let height = u32::from(self.size.rows) * dy;
        let background = if config.mode == Mode::Wireframe {
            config.wire_background
        } else {
            Rgb::BLACK
        };
        let sample = |sx, sy| {
            frame.sample(
                u32::from(x) * dx + sx,
                u32::from(y) * dy + sy,
                (width, height),
                config.filter,
                background,
            )
        };
        if config.mode == Mode::Shaded {
            return Cell {
                fg: quantize(sample(0, 0), config.colours),
                bg: quantize(sample(0, 1), config.colours),
                glyph: 0x2580,
            };
        }
        let mut mask = 0_u16;
        let mut sums = [0_u32; 3];
        let mut count = 0;
        // Unicode dot order: left 1,2,3,7; right 4,5,6,8.
        for (sy, bits) in [[0, 3], [1, 4], [2, 5], [6, 7]].iter().enumerate() {
            for (sx, bit) in bits.iter().enumerate() {
                let Rgb(r, g, b) = sample(sx as u32, sy as u32);
                if Rgb(r, g, b) != config.wire_background {
                    mask |= 1 << bit;
                    sums[0] += u32::from(r);
                    sums[1] += u32::from(g);
                    sums[2] += u32::from(b);
                    count += 1;
                }
            }
        }
        let divisor = count.max(1);
        let rgb = if mask == 0 {
            config.wire_background
        } else {
            Rgb(
                (sums[0] / divisor) as u8,
                (sums[1] / divisor) as u8,
                (sums[2] / divisor) as u8,
            )
        };
        Cell {
            fg: quantize(rgb, config.colours),
            bg: quantize(config.wire_background, config.colours),
            glyph: 0x2800 | mask,
        }
    }
}

fn validate(size: Size, capacity: usize) -> Result<(), Error> {
    if size.cols == 0 || size.rows == 0 {
        return Err(Error::EmptySize);
    }
    if usize::from(size.cols)
        .checked_mul(usize::from(size.rows))
        .is_none_or(|n| n > capacity)
    {
        return Err(Error::Capacity);
    }
    Ok(())
}

fn quantize(rgb: Rgb, mode: ColourMode) -> u32 {
    if mode == ColourMode::TrueColour {
        return rgb.packed();
    }
    let mut best = 0;
    let mut distance = u32::MAX;
    let count = if mode == ColourMode::Ansi16 { 16 } else { 256 };
    for i in 0..count {
        let candidate = if i < 16 {
            ANSI16[i as usize]
        } else if i < 232 {
            let n = i - 16;
            let levels = [0, 95, 135, 175, 215, 255];
            Rgb(
                levels[(n / 36) as usize],
                levels[((n / 6) % 6) as usize],
                levels[(n % 6) as usize],
            )
        } else {
            let gray = (8 + (i - 232) * 10) as u8;
            Rgb(gray, gray, gray)
        };
        let d = rgb.distance(candidate);
        if d < distance {
            best = i;
            distance = d;
        }
        if d == 0 {
            break;
        }
    }
    best
}

fn number<W: Write>(out: &mut W, mut value: u32) -> Result<(), W::Error> {
    let mut bytes = [0; 10];
    let mut start = bytes.len();
    loop {
        start -= 1;
        bytes[start] = b'0' + (value % 10) as u8;
        value /= 10;
        if value == 0 {
            break;
        }
    }
    out.write_all(&bytes[start..])
}

fn colour<W: Write>(
    out: &mut W,
    value: u32,
    background: bool,
    mode: ColourMode,
) -> Result<(), W::Error> {
    out.write_all(b"\x1b[")?;
    if mode == ColourMode::Ansi16 {
        number(
            out,
            (if background { 40 } else { 30 }) + value % 8 + if value >= 8 { 60 } else { 0 },
        )?;
    } else {
        out.write_all(if background { b"48;" } else { b"38;" })?;
        if mode == ColourMode::Ansi256 {
            out.write_all(b"5;")?;
            number(out, value)?;
        } else {
            out.write_all(b"2;")?;
            number(out, (value >> 16) & 255)?;
            out.write_all(b";")?;
            number(out, (value >> 8) & 255)?;
            out.write_all(b";")?;
            number(out, value & 255)?;
        }
    }
    out.write_all(b"m")
}
