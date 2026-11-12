#![forbid(unsafe_code)]

//! The same deterministic little scene drives the live demonstration and measurements.
use sc98_term::{Mode, Rgb, Write};
use std::convert::Infallible;

pub type Scalar = f32;

pub struct Canvas {
    pub pixels: Vec<Rgb>,
    pub width: u16,
    pub height: u16,
}

impl Canvas {
    pub fn new(mode: Mode) -> Self {
        let (width, height) = match mode {
            Mode::Shaded => (160, 120),
            Mode::Wireframe => (320, 240),
        };
        Self {
            pixels: vec![Rgb::BLACK; usize::from(width) * usize::from(height)],
            width,
            height,
        }
    }

    pub fn pattern(&mut self) {
        for y in 0..self.height {
            for x in 0..self.width {
                self.pixels[usize::from(y) * usize::from(self.width) + usize::from(x)] = Rgb(
                    (u32::from(x) * 255 / u32::from(self.width - 1)) as u8,
                    (u32::from(y) * 255 / u32::from(self.height - 1)) as u8,
                    if (x / 10 + y / 10) % 2 == 0 { 220 } else { 32 },
                );
            }
        }
    }

    pub fn cube(&mut self, angle: Scalar, mode: Mode, zoom: Scalar) {
        self.pixels.fill(if mode == Mode::Shaded {
            Rgb(24, 24, 32)
        } else {
            Rgb::BLACK
        });
        let sn = libm::sinf(angle);
        let cs = libm::cosf(angle);
        let scale = Scalar::from(self.height) * 0.27 * zoom;
        let mut points = [(0_i32, 0_i32, 0.0); 8];
        for (i, point) in points.iter_mut().enumerate() {
            let x = if i & 1 == 0 { -1.0 } else { 1.0 };
            let y = if i & 2 == 0 { -1.0 } else { 1.0 };
            let z = if i & 4 == 0 { -1.0 } else { 1.0 };
            let rx = x * cs + z * sn;
            let rz = -x * sn + z * cs;
            let ry = y * 0.866_025_4 - rz * 0.5;
            let depth = y * 0.5 + rz * 0.866_025_4;
            *point = (
                (Scalar::from(self.width) * 0.5 + rx * scale) as i32,
                (Scalar::from(self.height) * 0.5 - ry * scale) as i32,
                depth,
            );
        }
        let faces = [
            [0, 1, 3, 2],
            [4, 6, 7, 5],
            [0, 4, 5, 1],
            [2, 3, 7, 6],
            [0, 2, 6, 4],
            [1, 5, 7, 3],
        ];
        if mode == Mode::Shaded {
            let colours = [
                Rgb(70, 88, 120),
                Rgb(165, 178, 200),
                Rgb(85, 100, 130),
                Rgb(205, 215, 235),
                Rgb(110, 128, 155),
                Rgb(140, 158, 185),
            ];
            let mut order = [0, 1, 2, 3, 4, 5];
            let depth = |i: usize| faces[i].iter().map(|&j| points[j].2).sum::<Scalar>();
            order.sort_by(|&a, &b| depth(a).total_cmp(&depth(b)));
            for i in order {
                let f = faces[i];
                self.triangle([points[f[0]], points[f[1]], points[f[2]]], colours[i]);
                self.triangle([points[f[0]], points[f[2]], points[f[3]]], colours[i]);
            }
        } else {
            for i in 0..8 {
                for bit in [1, 2, 4] {
                    if i & bit == 0 {
                        self.line(points[i], points[i | bit], Rgb(192, 220, 255));
                    }
                }
            }
        }
    }

    fn put(&mut self, x: i32, y: i32, colour: Rgb) {
        if x >= 0 && x < i32::from(self.width) && y >= 0 && y < i32::from(self.height) {
            self.pixels[y as usize * usize::from(self.width) + x as usize] = colour;
        }
    }

    fn line(&mut self, a: (i32, i32, Scalar), b: (i32, i32, Scalar), colour: Rgb) {
        let (mut x, mut y, _) = a;
        let (bx, by, _) = b;
        let dx = (bx - x).abs();
        let dy = -(by - y).abs();
        let sx = if x < bx { 1 } else { -1 };
        let sy = if y < by { 1 } else { -1 };
        let mut error = dx + dy;
        loop {
            self.put(x, y, colour);
            if x == bx && y == by {
                break;
            }
            let twice = error * 2;
            if twice >= dy {
                error += dy;
                x += sx;
            }
            if twice <= dx {
                error += dx;
                y += sy;
            }
        }
    }

    fn triangle(&mut self, p: [(i32, i32, Scalar); 3], colour: Rgb) {
        let min_x = p.iter().map(|p| p.0).min().unwrap_or(0).max(0);
        let max_x = p
            .iter()
            .map(|p| p.0)
            .max()
            .unwrap_or(0)
            .min(i32::from(self.width) - 1);
        let min_y = p.iter().map(|p| p.1).min().unwrap_or(0).max(0);
        let max_y = p
            .iter()
            .map(|p| p.1)
            .max()
            .unwrap_or(0)
            .min(i32::from(self.height) - 1);
        for y in min_y..=max_y {
            for x in min_x..=max_x {
                let mut edges = [0; 3];
                for i in 0..3 {
                    let a = p[i];
                    let b = p[(i + 1) % 3];
                    edges[i] = (b.0 - a.0) * (y - a.1) - (b.1 - a.1) * (x - a.0);
                }
                if edges.iter().all(|&e| e >= 0) || edges.iter().all(|&e| e <= 0) {
                    self.put(x, y, colour);
                }
            }
        }
    }
}

#[derive(Default)]
pub struct Counter(pub usize);
impl Write for Counter {
    type Error = Infallible;
    fn write_all(&mut self, bytes: &[u8]) -> Result<(), Self::Error> {
        self.0 += bytes.len();
        Ok(())
    }
}
