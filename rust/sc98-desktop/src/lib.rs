//! Desktop framebuffer conversion, screenshots and repeatable performance probe.
#![forbid(unsafe_code)]
use sc98_pixels::{
    app::{App, Layout},
    draw::Canvas,
    framebuffer::{Color, Indexed16, Rgb565, PALETTE},
    model::{DemoPart, Feature, Part, Triangle, Vec3},
    view::{self, Style, View, Visibility},
    Scalar,
};
use std::{
    error::Error,
    fs::File,
    io::{self, BufWriter},
    path::Path,
    time::{Duration, Instant},
};

pub type DesktopResult<T> = Result<T, Box<dyn Error>>;
fn drawing_error(e: impl std::fmt::Debug) -> io::Error {
    io::Error::other(format!("{e:?}"))
}

/// Persistent buffers; the frame loop does not allocate.
pub struct Screen {
    pub width: usize,
    pub height: usize,
    pub rgb: Vec<u16>,
    pub output: Vec<u32>,
    indexed: Vec<u8>,
    depth: Vec<Scalar>,
    faces: Vec<u16>,
    order: Vec<usize>,
}
impl Screen {
    pub fn new(layout: Layout, triangles: usize, painter: bool, indexed: bool) -> Self {
        let (width, height) = layout.size();
        let n = width * height;
        Self {
            width,
            height,
            rgb: vec![0; n],
            output: vec![0; n],
            indexed: if indexed { vec![0; n] } else { Vec::new() },
            depth: if painter { Vec::new() } else { vec![0.; n] },
            faces: if painter { Vec::new() } else { vec![0; n] },
            order: vec![0; triangles],
        }
    }
    pub fn draw<P: Part + ?Sized>(
        &mut self,
        app: &App,
        part: &P,
        painter: bool,
        indexed: bool,
    ) -> DesktopResult<()> {
        let visibility = if painter {
            Visibility::Painter {
                order: &mut self.order,
            }
        } else {
            Visibility::Depth {
                depth: &mut self.depth,
                faces: &mut self.faces,
            }
        };
        if indexed {
            let mut fb = Indexed16::new(&mut self.indexed, self.width, self.height)
                .map_err(drawing_error)?;
            app.render(&mut fb, part, visibility)
                .map_err(drawing_error)?;
            for ((rgb, out), &index) in self.rgb.iter_mut().zip(&mut self.output).zip(fb.pixels()) {
                let col = PALETTE[index as usize];
                *rgb = col.0;
                *out = col.xrgb();
            }
        } else {
            let mut fb =
                Rgb565::new(&mut self.rgb, self.width, self.height).map_err(drawing_error)?;
            app.render(&mut fb, part, visibility)
                .map_err(drawing_error)?;
            for (out, &rgb) in self.output.iter_mut().zip(fb.pixels()) {
                *out = Color(rgb).xrgb();
            }
        }
        Ok(())
    }
    pub fn save_png(&self, path: &Path) -> DesktopResult<()> {
        let mut encoder = png::Encoder::new(
            BufWriter::new(File::create(path)?),
            self.width as u32,
            self.height as u32,
        );
        encoder.set_color(png::ColorType::Rgb);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header()?;
        let bytes: Vec<u8> = self.rgb.iter().flat_map(|&p| Color(p).channels()).collect();
        writer.write_image_data(&bytes)?;
        Ok(())
    }
}
pub fn screenshot(layout: Layout, path: &Path, painter: bool, indexed: bool) -> DesktopResult<()> {
    let part = DemoPart;
    let app = App::new(layout, &part);
    let mut screen = Screen::new(layout, part.triangles().len(), painter, indexed);
    screen.draw(&app, &part, painter, indexed)?;
    screen.save_png(path)
}

struct BenchmarkPart {
    triangles: Vec<Triangle>,
}
impl Part for BenchmarkPart {
    fn name(&self) -> &str {
        "300 triangles"
    }
    fn features(&self) -> &[Feature<'_>] {
        &[]
    }
    fn triangles(&self) -> &[Triangle] {
        &self.triangles
    }
}
/// 100 cylinder sectors: 200 wall triangles and 100 top triangles. This uses
/// actual distinct visible geometry rather than repeating a tiny test mesh.
fn benchmark_part() -> BenchmarkPart {
    let mut triangles = Vec::with_capacity(300);
    for i in 0..100 {
        let a = i as Scalar * core::f32::consts::TAU / 100.;
        let b = (i + 1) as Scalar * core::f32::consts::TAU / 100.;
        let p = Vec3::new(30. * libm::cosf(a), 30. * libm::sinf(a), 0.);
        let q = Vec3::new(30. * libm::cosf(b), 30. * libm::sinf(b), 0.);
        let pp = Vec3::new(p.x, p.y, 35.);
        let qq = Vec3::new(q.x, q.y, 35.);
        let n = Vec3::new(libm::cosf((a + b) / 2.), libm::sinf((a + b) / 2.), 0.);
        for (vertices, normal, face) in [
            ([p, q, qq], n, 1),
            ([p, qq, pp], n, 1),
            ([Vec3::new(0., 0., 35.), pp, qq], Vec3::new(0., 0., 1.), 2),
        ] {
            triangles.push(Triangle {
                vertices,
                normal,
                face,
                color: Color::rgb(165, 178, 200),
            });
        }
    }
    BenchmarkPart { triangles }
}
#[derive(Debug)]
pub struct Timing {
    pub style: Style,
    pub painter: bool,
    pub frames: usize,
    pub per_frame: Duration,
}
pub fn benchmark(frames: usize) -> DesktopResult<Vec<Timing>> {
    if frames == 0 {
        return Err(io::Error::other("Frame count must be positive").into());
    }
    let part = benchmark_part();
    let r = sc98_pixels::draw::Rect::new(0, 0, 320, 240);
    let mut v = View::default();
    v.fit(r, &part);
    let mut rgb = vec![0; 320 * 240];
    let mut depth = vec![0.; 320 * 240];
    let mut faces = vec![0; 320 * 240];
    let mut order = vec![0; 300];
    let mut result = Vec::new();
    for (style, painter) in [
        (Style::Shaded, false),
        (Style::Shaded, true),
        (Style::Wireframe, true),
    ] {
        // A warm-up frame is excluded from the timing.
        let mut elapsed = Duration::ZERO;
        for i in 0..=frames {
            let start = Instant::now();
            let mut fb = Rgb565::new(&mut rgb, 320, 240).map_err(drawing_error)?;
            let visibility = if painter {
                Visibility::Painter { order: &mut order }
            } else {
                Visibility::Depth {
                    depth: &mut depth,
                    faces: &mut faces,
                }
            };
            view::render(&mut Canvas::new(&mut fb), r, &part, &v, style, visibility)
                .map_err(drawing_error)?;
            std::hint::black_box(fb.pixels());
            if i != 0 {
                elapsed += start.elapsed();
            }
        }
        result.push(Timing {
            style,
            painter,
            frames,
            per_frame: elapsed.div_f64(frames as f64),
        });
    }
    Ok(result)
}
