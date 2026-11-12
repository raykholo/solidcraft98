//! Clipped drawing primitives and the reference bitmap font.
use crate::{
    font,
    framebuffer::{Color, Framebuffer, PALETTE},
    icons,
};

pub const FACE: Color = Color::rgb(192, 192, 192);
pub const LIGHT: Color = Color::rgb(223, 223, 223);
pub const WHITE: Color = Color::rgb(255, 255, 255);
pub const SHADOW: Color = Color::rgb(128, 128, 128);
pub const BLACK: Color = Color::rgb(0, 0, 0);
pub const SELECT: Color = Color::rgb(0, 0, 128);

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
}
impl Rect {
    pub const fn new(x: i32, y: i32, w: i32, h: i32) -> Self {
        Self { x, y, w, h }
    }
    pub fn contains(self, x: i32, y: i32) -> bool {
        x >= self.x
            && y >= self.y
            && x < self.x.saturating_add(self.w)
            && y < self.y.saturating_add(self.h)
    }
    pub fn inset(self, n: i32) -> Self {
        Self::new(
            self.x + n,
            self.y + n,
            (self.w - 2 * n).max(0),
            (self.h - 2 * n).max(0),
        )
    }
    pub fn intersect(self, other: Self) -> Self {
        let x = self.x.max(other.x);
        let y = self.y.max(other.y);
        Self::new(
            x,
            y,
            (self
                .x
                .saturating_add(self.w)
                .min(other.x.saturating_add(other.w))
                - x)
                .max(0),
            (self
                .y
                .saturating_add(self.h)
                .min(other.y.saturating_add(other.h))
                - y)
                .max(0),
        )
    }
}
#[derive(Clone, Copy, Debug)]
pub enum Bevel {
    Raised,
    Button,
    Pressed,
    Sunken,
    ThinUp,
    ThinDown,
}

pub struct Canvas<'a, F: Framebuffer> {
    pub fb: &'a mut F,
    clip: Rect,
}
impl<'a, F: Framebuffer> Canvas<'a, F> {
    pub fn new(fb: &'a mut F) -> Self {
        let clip = Rect::new(0, 0, fb.width() as i32, fb.height() as i32);
        Self { fb, clip }
    }
    pub fn clip(&self) -> Rect {
        self.clip
    }
    /// Returns the old clip for restoration. Clips never escape the framebuffer.
    pub fn set_clip(&mut self, r: Rect) -> Rect {
        let old = self.clip;
        self.clip = r.intersect(Rect::new(
            0,
            0,
            self.fb.width() as i32,
            self.fb.height() as i32,
        ));
        old
    }
    pub fn pixel(&mut self, x: i32, y: i32, c: Color) {
        if self.clip.contains(x, y) {
            self.fb.set(x, y, c);
        }
    }
    pub fn fill(&mut self, r: Rect, c: Color) {
        let r = r.intersect(self.clip);
        if r.w > 0 && r.h > 0 {
            self.fb.fill(r.x, r.y, r.w as usize, r.h as usize, c);
        }
    }
    pub fn hline(&mut self, x: i32, y: i32, w: i32, c: Color) {
        self.fill(Rect::new(x, y, w, 1), c);
    }
    pub fn vline(&mut self, x: i32, y: i32, h: i32, c: Color) {
        self.fill(Rect::new(x, y, 1, h), c);
    }
    pub fn frame(&mut self, r: Rect, c: Color) {
        if r.w <= 0 || r.h <= 0 {
            return;
        }
        self.hline(r.x, r.y, r.w, c);
        self.hline(r.x, r.y + r.h - 1, r.w, c);
        self.vline(r.x, r.y, r.h, c);
        self.vline(r.x + r.w - 1, r.y, r.h, c);
    }
    pub fn line(&mut self, mut x: i32, mut y: i32, xx: i32, yy: i32, c: Color) {
        // Bound even corrupt model coordinates before Bresenham arithmetic.
        x = x.clamp(-32768, 32768);
        y = y.clamp(-32768, 32768);
        let xx = xx.clamp(-32768, 32768);
        let yy = yy.clamp(-32768, 32768);
        if (x < self.clip.x && xx < self.clip.x)
            || (y < self.clip.y && yy < self.clip.y)
            || (x >= self.clip.x + self.clip.w && xx >= self.clip.x + self.clip.w)
            || (y >= self.clip.y + self.clip.h && yy >= self.clip.y + self.clip.h)
        {
            return;
        }
        let dx = (xx - x).abs();
        let dy = -(yy - y).abs();
        let sx = if x < xx { 1 } else { -1 };
        let sy = if y < yy { 1 } else { -1 };
        let mut e = dx + dy;
        loop {
            self.pixel(x, y, c);
            if x == xx && y == yy {
                break;
            }
            let e2 = 2 * e;
            if e2 >= dy {
                e += dy;
                x += sx;
            }
            if e2 <= dx {
                e += dx;
                y += sy;
            }
        }
    }
    pub fn focus(&mut self, r: Rect) {
        for i in (0..r.w).step_by(2) {
            self.pixel(r.x + i, r.y, BLACK);
            self.pixel(r.x + i, r.y + r.h - 1, BLACK);
        }
        for i in (0..r.h).step_by(2) {
            self.pixel(r.x, r.y + i, BLACK);
            self.pixel(r.x + r.w - 1, r.y + i, BLACK);
        }
    }
    pub fn bevel(&mut self, r: Rect, kind: Bevel) {
        if r.w < 2 || r.h < 2 {
            return;
        }
        if matches!(kind, Bevel::Pressed) {
            self.frame(r, BLACK);
            self.frame(r.inset(1), SHADOW);
            return;
        }
        let (tl, br, inner) = match kind {
            Bevel::Raised => (LIGHT, BLACK, Some((WHITE, SHADOW))),
            Bevel::Button => (WHITE, BLACK, Some((LIGHT, SHADOW))),
            Bevel::Sunken => (SHADOW, WHITE, Some((BLACK, LIGHT))),
            Bevel::ThinUp => (WHITE, SHADOW, None),
            _ => (SHADOW, WHITE, None),
        };
        self.edge(r, tl, br);
        if let Some((tl, br)) = inner {
            self.edge(r.inset(1), tl, br);
        }
    }
    fn edge(&mut self, r: Rect, tl: Color, br: Color) {
        self.hline(r.x, r.y, r.w - 1, tl);
        self.vline(r.x, r.y, r.h - 1, tl);
        self.hline(r.x, r.y + r.h - 1, r.w, br);
        self.vline(r.x + r.w - 1, r.y, r.h, br);
    }
    pub fn gradient(&mut self, r: Rect, a: Color, b: Color) {
        let aa = a.channels();
        let bb = b.channels();
        let d = (r.w - 1).max(1);
        for i in 0..r.w {
            let mut c = [0; 3];
            for k in 0..3 {
                c[k] = ((i32::from(aa[k]) * (d - i) + i32::from(bb[k]) * i) / d) as u8;
            }
            self.vline(r.x + i, r.y, r.h, Color::rgb(c[0], c[1], c[2]));
        }
    }
    pub fn text(&mut self, mut x: i32, y: i32, text: &str, c: Color, bold: bool) -> i32 {
        for ch in text.bytes() {
            let w = font::WIDTHS[ch as usize];
            if w == 0 && ch != b' ' {
                self.frame(Rect::new(x, y + 2, 3, 7), c);
            } else {
                for (r, bits) in font::BITS[ch as usize].iter().enumerate() {
                    for col in 0..w {
                        if bits & (1 << col) != 0 {
                            self.pixel(x + i32::from(col), y + r as i32, c);
                            if bold {
                                self.pixel(x + i32::from(col) + 1, y + r as i32, c);
                            }
                        }
                    }
                }
            }
            x += char_width(ch, bold);
        }
        x
    }
    pub fn caption(&mut self, mut x: i32, y: i32, text: &str, c: Color, disabled: bool) {
        let mut chars = text.bytes();
        while let Some(mut ch) = chars.next() {
            let mut underline = false;
            if ch == b'&' {
                if let Some(next) = chars.next() {
                    ch = next;
                    underline = ch != b'&';
                }
            }
            let buf = [ch];
            if let Ok(t) = core::str::from_utf8(&buf) {
                if disabled {
                    self.text(x + 1, y + 1, t, WHITE, false);
                    self.text(x, y, t, SHADOW, false);
                } else {
                    self.text(x, y, t, c, false);
                }
                if underline {
                    self.hline(
                        x,
                        y + 10,
                        i32::from(font::WIDTHS[ch as usize]),
                        if disabled { SHADOW } else { c },
                    );
                }
                x += char_width(ch, false);
            }
        }
    }
    pub fn icon(&mut self, x: i32, y: i32, name: &str, disabled: bool) {
        if let Some(k) = icons::NAMES.iter().position(|n| *n == name) {
            for (p, &index) in icons::ART[k].iter().enumerate() {
                if index < 16 {
                    let xx = x + (p % 16) as i32;
                    let yy = y + (p / 16) as i32;
                    if disabled {
                        if index != 15 && index != 7 {
                            self.pixel(xx + 1, yy + 1, WHITE);
                            self.pixel(xx, yy, SHADOW);
                        }
                    } else {
                        self.pixel(xx, yy, PALETTE[index as usize]);
                    }
                }
            }
        }
    }
}
pub fn char_width(ch: u8, bold: bool) -> i32 {
    let w = font::WIDTHS[ch as usize];
    i32::from(if w == 0 && ch != b' ' { 4 } else { w }) + 1 + i32::from(bold)
}
pub fn text_width(t: &str, bold: bool) -> i32 {
    (t.bytes().map(|ch| char_width(ch, bold)).sum::<i32>() - 1).max(0)
}
pub fn caption_width(t: &str) -> i32 {
    let mut n = 0;
    let mut bytes = t.bytes();
    while let Some(ch) = bytes.next() {
        let c = if ch == b'&' {
            bytes.next().unwrap_or(b'&')
        } else {
            ch
        };
        n += char_width(c, false);
    }
    (n - 1).max(0)
}
