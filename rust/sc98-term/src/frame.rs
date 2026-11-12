/// Terminal dimensions in character cells. Zero dimensions are rejected by Encoder.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Size {
    pub cols: u16,
    pub rows: u16,
}

impl Default for Size {
    fn default() -> Self {
        Self {
            cols: 160,
            rows: 60,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Rgb(pub u8, pub u8, pub u8);

impl Rgb {
    pub const BLACK: Self = Self(0, 0, 0);

    pub(crate) fn packed(self) -> u32 {
        (u32::from(self.0) << 16) | (u32::from(self.1) << 8) | u32::from(self.2)
    }

    pub(crate) fn distance(self, other: Self) -> u32 {
        let r = i32::from(self.0) - i32::from(other.0);
        let g = i32::from(self.1) - i32::from(other.1);
        let b = i32::from(self.2) - i32::from(other.2);
        (r * r + g * g + b * b) as u32
    }
}

/// Conventional ANSI order (red at index 1, blue at index 4), not VGA order.
pub const ANSI16: [Rgb; 16] = [
    Rgb(0, 0, 0),
    Rgb(128, 0, 0),
    Rgb(0, 128, 0),
    Rgb(128, 128, 0),
    Rgb(0, 0, 128),
    Rgb(128, 0, 128),
    Rgb(0, 128, 128),
    Rgb(192, 192, 192),
    Rgb(128, 128, 128),
    Rgb(255, 0, 0),
    Rgb(0, 255, 0),
    Rgb(255, 255, 0),
    Rgb(0, 0, 255),
    Rgb(255, 0, 255),
    Rgb(0, 255, 255),
    Rgb(255, 255, 255),
];

/// Supply another small Copy pixel type to adapt a different framebuffer format.
pub trait Pixel: Copy {
    fn rgb(self) -> Rgb;
}

impl Pixel for Rgb {
    fn rgb(self) -> Rgb {
        self
    }
}

/// A u16 slice is interpreted as RGB565, with replicated low bits.
impl Pixel for u16 {
    fn rgb(self) -> Rgb {
        let r = ((self >> 11) & 31) as u8;
        let g = ((self >> 5) & 63) as u8;
        let b = (self & 31) as u8;
        Rgb(
            (r << 3) | (r >> 2),
            (g << 2) | (g >> 4),
            (b << 3) | (b >> 2),
        )
    }
}

/// ANSI palette index; the low four bits are used.
#[derive(Clone, Copy, Debug)]
pub struct Palette16(pub u8);

impl Pixel for Palette16 {
    fn rgb(self) -> Rgb {
        ANSI16[usize::from(self.0 & 15)]
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FrameError {
    Empty,
    Length,
}

/// A tightly packed, row-major framebuffer. Dimensions are validated once.
pub struct Frame<'a, P> {
    pixels: &'a [P],
    pub(crate) width: u16,
    pub(crate) height: u16,
}

impl<'a, P: Pixel> Frame<'a, P> {
    pub fn new(pixels: &'a [P], width: u16, height: u16) -> Result<Self, FrameError> {
        if width == 0 || height == 0 {
            return Err(FrameError::Empty);
        }
        if usize::from(width).checked_mul(usize::from(height)) != Some(pixels.len()) {
            return Err(FrameError::Length);
        }
        Ok(Self {
            pixels,
            width,
            height,
        })
    }

    fn at(&self, x: u32, y: u32) -> Rgb {
        self.pixels[y as usize * usize::from(self.width) + x as usize].rgb()
    }

    pub(crate) fn sample(
        &self,
        x: u32,
        y: u32,
        raster: (u32, u32),
        filter: Filter,
        background: Rgb,
    ) -> Rgb {
        let (width, height) = raster;
        // Centre the aspect-preserving fitted image in the cell raster.
        let fw = u32::from(self.width);
        let fh = u32::from(self.height);
        let (w, h) = if u64::from(width) * u64::from(fh) <= u64::from(height) * u64::from(fw) {
            (
                width,
                ((u64::from(fh) * u64::from(width) / u64::from(fw)) as u32).max(1),
            )
        } else {
            (
                ((u64::from(fw) * u64::from(height) / u64::from(fh)) as u32).max(1),
                height,
            )
        };
        let left = (width - w) / 2;
        let top = (height - h) / 2;
        if x < left || y < top || x >= left + w || y >= top + h {
            return background;
        }
        let sx = (u64::from(x - left) * u64::from(fw) / u64::from(w)) as u32;
        let sy = (u64::from(y - top) * u64::from(fh) / u64::from(h)) as u32;
        if filter == Filter::Nearest {
            return self.at(sx, sy);
        }
        let samples = [
            self.at(sx, sy),
            self.at((sx + 1).min(fw - 1), sy),
            self.at(sx, (sy + 1).min(fh - 1)),
            self.at((sx + 1).min(fw - 1), (sy + 1).min(fh - 1)),
        ];
        let mut sums = [0_u16; 3];
        for Rgb(r, g, b) in samples {
            sums[0] += u16::from(r);
            sums[1] += u16::from(g);
            sums[2] += u16::from(b);
        }
        Rgb(
            (sums[0] / 4) as u8,
            (sums[1] / 4) as u8,
            (sums[2] / 4) as u8,
        )
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Filter {
    #[default]
    Nearest,
    /// Average a clamped 2x2 source neighbourhood at each mapped sample.
    Box2x2,
}
