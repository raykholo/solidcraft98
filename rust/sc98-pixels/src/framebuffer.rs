//! Borrowed RGB565 and one-byte-per-pixel, 16-colour framebuffers.

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Color(pub u16);
impl Color {
    pub const fn rgb(r: u8, g: u8, b: u8) -> Self {
        Self(((r as u16 & 248) << 8) | ((g as u16 & 252) << 3) | (b as u16 >> 3))
    }
    pub const fn channels(self) -> [u8; 3] {
        let r = (self.0 >> 11) as u8;
        let g = ((self.0 >> 5) & 63) as u8;
        let b = (self.0 & 31) as u8;
        [
            (r << 3) | (r >> 2),
            (g << 2) | (g >> 4),
            (b << 3) | (b >> 2),
        ]
    }
    pub const fn xrgb(self) -> u32 {
        let [r, g, b] = self.channels();
        (r as u32) << 16 | (g as u32) << 8 | b as u32
    }
}
pub const PALETTE: [Color; 16] = [
    Color::rgb(0, 0, 0),
    Color::rgb(0, 0, 128),
    Color::rgb(0, 128, 0),
    Color::rgb(0, 128, 128),
    Color::rgb(128, 0, 0),
    Color::rgb(128, 0, 128),
    Color::rgb(128, 128, 0),
    Color::rgb(192, 192, 192),
    Color::rgb(128, 128, 128),
    Color::rgb(0, 0, 255),
    Color::rgb(0, 255, 0),
    Color::rgb(0, 255, 255),
    Color::rgb(255, 0, 0),
    Color::rgb(255, 0, 255),
    Color::rgb(255, 255, 0),
    Color::rgb(255, 255, 255),
];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum BufferError {
    Dimensions,
    TooShort,
}

/// Drivers may override the default fill/blit to use DMA. Coordinates outside
/// the framebuffer must be ignored. Blit input is row-major, RGB565.
pub trait Framebuffer {
    fn width(&self) -> usize;
    fn height(&self) -> usize;
    fn set(&mut self, x: i32, y: i32, color: Color);
    fn fill(&mut self, x: i32, y: i32, width: usize, height: usize, color: Color) {
        let x0 = x.max(0) as usize;
        let y0 = y.max(0) as usize;
        let x1 = (i64::from(x) + width as i64).clamp(0, self.width() as i64) as usize;
        let y1 = (i64::from(y) + height as i64).clamp(0, self.height() as i64) as usize;
        for yy in y0..y1 {
            for xx in x0..x1 {
                self.set(xx as i32, yy as i32, color);
            }
        }
    }
    fn blit(
        &mut self,
        x: i32,
        y: i32,
        width: usize,
        height: usize,
        source: &[u16],
    ) -> Result<(), BufferError> {
        let len = width.checked_mul(height).ok_or(BufferError::Dimensions)?;
        if source.len() < len {
            return Err(BufferError::TooShort);
        }
        for row in 0..height {
            for col in 0..width {
                self.set(
                    x.saturating_add(col as i32),
                    y.saturating_add(row as i32),
                    Color(source[row * width + col]),
                );
            }
        }
        Ok(())
    }
}

fn validate(width: usize, height: usize, len: usize) -> Result<(), BufferError> {
    if width == 0 || height == 0 || width > 32768 || height > 32768 {
        return Err(BufferError::Dimensions);
    }
    if width.checked_mul(height).ok_or(BufferError::Dimensions)? > len {
        return Err(BufferError::TooShort);
    }
    Ok(())
}

pub struct Rgb565<'a> {
    pixels: &'a mut [u16],
    width: usize,
    height: usize,
}
impl<'a> Rgb565<'a> {
    pub fn new(pixels: &'a mut [u16], width: usize, height: usize) -> Result<Self, BufferError> {
        validate(width, height, pixels.len())?;
        Ok(Self {
            pixels,
            width,
            height,
        })
    }
    pub fn pixels(&self) -> &[u16] {
        &self.pixels[..self.width * self.height]
    }
}
impl Framebuffer for Rgb565<'_> {
    fn width(&self) -> usize {
        self.width
    }
    fn height(&self) -> usize {
        self.height
    }
    fn set(&mut self, x: i32, y: i32, color: Color) {
        if x >= 0 && y >= 0 && (x as usize) < self.width && (y as usize) < self.height {
            self.pixels[y as usize * self.width + x as usize] = color.0;
        }
    }
    fn fill(&mut self, x: i32, y: i32, width: usize, height: usize, color: Color) {
        let x0 = (x.max(0) as usize).min(self.width);
        let x1 = (i64::from(x) + width as i64).clamp(0, self.width as i64) as usize;
        let y0 = (y.max(0) as usize).min(self.height);
        let y1 = (i64::from(y) + height as i64).clamp(0, self.height as i64) as usize;
        if x1 <= x0 {
            return;
        }
        for yy in y0..y1 {
            self.pixels[yy * self.width + x0..yy * self.width + x1].fill(color.0);
        }
    }
}

pub struct Indexed16<'a> {
    pixels: &'a mut [u8],
    width: usize,
    height: usize,
}
impl<'a> Indexed16<'a> {
    pub fn new(pixels: &'a mut [u8], width: usize, height: usize) -> Result<Self, BufferError> {
        validate(width, height, pixels.len())?;
        Ok(Self {
            pixels,
            width,
            height,
        })
    }
    pub fn pixels(&self) -> &[u8] {
        &self.pixels[..self.width * self.height]
    }
}
/// Nearest QB colour in RGB space. Exact palette colours stay exact.
pub fn palette_index(color: Color) -> u8 {
    let [r, g, b] = color.channels();
    let mut best = 0;
    let mut distance = u32::MAX;
    for (i, c) in PALETTE.iter().enumerate() {
        let [rr, gg, bb] = c.channels();
        let dr = i32::from(r) - i32::from(rr);
        let dg = i32::from(g) - i32::from(gg);
        let db = i32::from(b) - i32::from(bb);
        let d = (dr * dr + dg * dg + db * db) as u32;
        if d < distance {
            best = i;
            distance = d;
        }
    }
    best as u8
}
impl Framebuffer for Indexed16<'_> {
    fn width(&self) -> usize {
        self.width
    }
    fn height(&self) -> usize {
        self.height
    }
    fn set(&mut self, x: i32, y: i32, color: Color) {
        if x >= 0 && y >= 0 && (x as usize) < self.width && (y as usize) < self.height {
            self.pixels[y as usize * self.width + x as usize] = palette_index(color);
        }
    }
    fn fill(&mut self, x: i32, y: i32, width: usize, height: usize, color: Color) {
        let x0 = (x.max(0) as usize).min(self.width);
        let x1 = (i64::from(x) + width as i64).clamp(0, self.width as i64) as usize;
        let y0 = (y.max(0) as usize).min(self.height);
        let y1 = (i64::from(y) + height as i64).clamp(0, self.height as i64) as usize;
        if x1 <= x0 {
            return;
        }
        let index = palette_index(color);
        for yy in y0..y1 {
            self.pixels[yy * self.width + x0..yy * self.width + x1].fill(index);
        }
    }
}
