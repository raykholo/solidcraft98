//! Orthographic projection and flat software shading ported from view.bas and
//! shade.bas. Scratch memory is supplied by the caller; no allocation occurs.
use crate::{
    draw::{Canvas, Rect},
    framebuffer::{Color, Framebuffer},
    model::{Part, Triangle, Vec3},
    Scalar,
};

#[derive(Clone, Copy, Debug)]
pub struct View {
    pub yaw: Scalar,
    pub pitch: Scalar,
    pub zoom: Scalar,
    pub pan_x: Scalar,
    pub pan_y: Scalar,
}
impl Default for View {
    fn default() -> Self {
        Self {
            yaw: 135.,
            pitch: 35.264,
            zoom: 3.,
            pan_x: 0.,
            pan_y: 0.,
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Style {
    Wireframe,
    Shaded,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RenderError {
    InvalidViewport,
    DepthTooShort,
    OrderTooShort,
    InvalidView,
}
/// Depth and face arrays need viewport.w * viewport.h entries. Painter needs
/// one usize per triangle, and trades exact intersections for less RAM.
pub enum Visibility<'a> {
    Depth {
        depth: &'a mut [Scalar],
        faces: &'a mut [u16],
    },
    Painter {
        order: &'a mut [usize],
    },
}

#[derive(Clone, Copy)]
struct Axes {
    eye: Vec3,
    right: Vec3,
    up: Vec3,
}
impl View {
    fn axes(&self) -> Axes {
        let yaw = self.yaw * core::f32::consts::PI / 180.;
        let pitch = self.pitch * core::f32::consts::PI / 180.;
        let cy = libm::cosf(yaw);
        let sy = libm::sinf(yaw);
        let cp = libm::cosf(pitch);
        let sp = libm::sinf(pitch);
        Axes {
            eye: Vec3::new(sy * cp, cy * cp, sp),
            right: Vec3::new(-cy, sy, 0.),
            up: Vec3::new(-sy * sp, -cy * sp, cp),
        }
    }
    pub fn project(&self, r: Rect, p: Vec3) -> Vec3 {
        self.project_axes(r, p, self.axes())
    }
    fn project_axes(&self, r: Rect, p: Vec3, a: Axes) -> Vec3 {
        Vec3::new(
            r.x as Scalar + r.w as Scalar / 2. + self.pan_x + p.dot(a.right) * self.zoom,
            r.y as Scalar + r.h as Scalar / 2. + self.pan_y - p.dot(a.up) * self.zoom,
            p.dot(a.eye),
        )
    }
    pub fn fit<P: Part + ?Sized>(&mut self, r: Rect, p: &P) {
        let a = self.axes();
        let mut min_x = Scalar::INFINITY;
        let mut min_y = Scalar::INFINITY;
        let mut max_x = Scalar::NEG_INFINITY;
        let mut max_y = Scalar::NEG_INFINITY;
        for t in p.triangles().iter().filter(|t| t.finite()) {
            for v in t.vertices {
                let x = v.dot(a.right);
                let y = v.dot(a.up);
                min_x = min_x.min(x);
                max_x = max_x.max(x);
                min_y = min_y.min(y);
                max_y = max_y.max(y);
            }
        }
        if min_x.is_finite() && r.w > 0 && r.h > 0 {
            self.zoom = (0.8 * r.w as Scalar / (max_x - min_x).max(1.))
                .min(0.8 * r.h as Scalar / (max_y - min_y).max(1.));
            self.pan_x = -(min_x + max_x) / 2. * self.zoom;
            self.pan_y = (min_y + max_y) / 2. * self.zoom;
        } else {
            self.zoom = 3.;
            self.pan_x = 0.;
            self.pan_y = 0.;
        }
    }
    pub fn orbit(&mut self, dx: Scalar, dy: Scalar) {
        self.yaw = (self.yaw + dx * 0.6) % 360.;
        self.pitch = (self.pitch + dy * 0.6).clamp(-89., 89.);
    }
    pub fn zoom_by(&mut self, factor: Scalar) {
        if factor.is_finite() && factor > 0. {
            self.zoom = (self.zoom * factor).clamp(0.001, 1000.);
            self.pan_x *= factor;
            self.pan_y *= factor;
        }
    }
    fn valid(&self) -> bool {
        self.yaw.is_finite()
            && self.pitch.is_finite()
            && self.zoom.is_finite()
            && self.zoom > 0.
            && self.pan_x.is_finite()
            && self.pan_y.is_finite()
    }
}

pub fn render<F: Framebuffer, P: Part + ?Sized>(
    c: &mut Canvas<'_, F>,
    r: Rect,
    part: &P,
    v: &View,
    style: Style,
    mut visibility: Visibility<'_>,
) -> Result<(), RenderError> {
    if r.w <= 0
        || r.h <= 0
        || r.x < 0
        || r.y < 0
        || r.x.saturating_add(r.w) > c.fb.width() as i32
        || r.y.saturating_add(r.h) > c.fb.height() as i32
    {
        return Err(RenderError::InvalidViewport);
    }
    if !v.valid() {
        return Err(RenderError::InvalidView);
    }
    let count = r.w as usize * r.h as usize;
    if style == Style::Shaded {
        match &mut visibility {
            Visibility::Depth { depth, faces } => {
                if depth.len() < count || faces.len() < count {
                    return Err(RenderError::DepthTooShort);
                }
                depth[..count].fill(Scalar::NEG_INFINITY);
                faces[..count].fill(0);
            }
            Visibility::Painter { order } => {
                if order.len() < part.triangles().len() {
                    return Err(RenderError::OrderTooShort);
                }
            }
        }
    }
    let old = c.set_clip(c.clip().intersect(r));
    c.fill(r, Color::rgb(224, 224, 224));
    let axes = v.axes();
    for i in -5..=5 {
        let f = (i * 10) as Scalar;
        segment(
            c,
            v,
            r,
            axes,
            Vec3::new(f, -50., 0.),
            Vec3::new(f, 50., 0.),
            Color::rgb(184, 184, 184),
        );
        segment(
            c,
            v,
            r,
            axes,
            Vec3::new(-50., f, 0.),
            Vec3::new(50., f, 0.),
            Color::rgb(184, 184, 184),
        );
    }
    let tris = part.triangles();
    if style == Style::Wireframe {
        for t in tris.iter().filter(|t| t.finite()) {
            for k in 0..3 {
                if boundary_edge(tris, t, k) {
                    segment(
                        c,
                        v,
                        r,
                        axes,
                        t.vertices[k],
                        t.vertices[(k + 1) % 3],
                        Color::rgb(0, 0, 128),
                    );
                }
            }
        }
    } else {
        let light = Vec3::new(
            axes.eye.x + 0.6 * axes.up.x - 0.4 * axes.right.x,
            axes.eye.y + 0.6 * axes.up.y - 0.4 * axes.right.y,
            axes.eye.z + 0.6 * axes.up.z - 0.4 * axes.right.z,
        )
        .normalized();
        match visibility {
            Visibility::Depth { depth, faces } => {
                for t in tris {
                    if visible(t, axes) {
                        let points = t.vertices.map(|p| v.project_axes(r, p, axes));
                        raster(
                            c,
                            r,
                            points,
                            shade(t, light),
                            Some((&mut *depth, &mut *faces, t.face.max(1))),
                        );
                    }
                }
                let edge = Color::rgb(32, 32, 32);
                for y in 0..r.h {
                    for x in 0..r.w {
                        let p = (y * r.w + x) as usize;
                        for (nx, ny) in [(x + 1, y), (x, y + 1)] {
                            if nx < r.w && ny < r.h {
                                let q = (ny * r.w + nx) as usize;
                                if faces[p] != faces[q] {
                                    if faces[p] != 0 {
                                        c.pixel(r.x + x, r.y + y, edge);
                                    } else {
                                        c.pixel(r.x + nx, r.y + ny, edge);
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Visibility::Painter { order } => {
                let order = &mut order[..tris.len()];
                for (i, p) in order.iter_mut().enumerate() {
                    *p = i;
                }
                order.sort_unstable_by(|&a, &b| {
                    triangle_depth(&tris[a], axes).total_cmp(&triangle_depth(&tris[b], axes))
                });
                for &i in order.iter() {
                    let t = &tris[i];
                    if visible(t, axes) {
                        raster(
                            c,
                            r,
                            t.vertices.map(|p| v.project_axes(r, p, axes)),
                            shade(t, light),
                            None,
                        );
                        for k in 0..3 {
                            if boundary_edge(tris, t, k) {
                                segment(
                                    c,
                                    v,
                                    r,
                                    axes,
                                    t.vertices[k],
                                    t.vertices[(k + 1) % 3],
                                    Color::rgb(32, 32, 32),
                                );
                            }
                        }
                    }
                }
            }
        }
    }
    let origin = (r.x + 40, r.y + r.h - 32);
    for (p, label, col) in [
        (Vec3::new(25., 0., 0.), "X", Color::rgb(255, 0, 0)),
        (Vec3::new(0., 25., 0.), "Y", Color::rgb(0, 128, 0)),
        (Vec3::new(0., 0., 25.), "Z", Color::rgb(0, 0, 255)),
    ] {
        let x = origin.0 + (p.dot(axes.right)) as i32;
        let y = origin.1 - (p.dot(axes.up)) as i32;
        c.line(origin.0, origin.1, x, y, col);
        c.text(x + 2, y - 6, label, col, false);
    }
    c.set_clip(old);
    Ok(())
}
fn visible(t: &Triangle, a: Axes) -> bool {
    t.finite() && t.normal.dot(a.eye) > 0.000001
}
fn triangle_depth(t: &Triangle, a: Axes) -> Scalar {
    t.vertices.iter().map(|p| p.dot(a.eye)).sum::<Scalar>() / 3.
}
fn shade(t: &Triangle, light: Vec3) -> Color {
    let k = 0.3 + 0.7 * t.normal.normalized().dot(light).clamp(0., 1.);
    let [r, g, b] = t.color.channels();
    Color::rgb(
        (r as Scalar * k) as u8,
        (g as Scalar * k) as u8,
        (b as Scalar * k) as u8,
    )
}
fn segment<F: Framebuffer>(
    c: &mut Canvas<'_, F>,
    v: &View,
    r: Rect,
    a: Axes,
    p: Vec3,
    q: Vec3,
    col: Color,
) {
    let p = v.project_axes(r, p, a);
    let q = v.project_axes(r, q, a);
    if p.finite() && q.finite() {
        c.line(p.x as i32, p.y as i32, q.x as i32, q.y as i32, col);
    }
}
// Suppress shared coplanar diagonals. The adapter supplies stable face groups.
fn boundary_edge(tris: &[Triangle], t: &Triangle, k: usize) -> bool {
    let a = t.vertices[k];
    let b = t.vertices[(k + 1) % 3];
    !tris.iter().any(|other| {
        !core::ptr::eq(t, other)
            && t.face == other.face
            && (0..3).any(|j| other.vertices[j] == b && other.vertices[(j + 1) % 3] == a)
    })
}
fn edge(a: Vec3, b: Vec3, x: Scalar, y: Scalar) -> Scalar {
    (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x)
}
fn raster<F: Framebuffer>(
    c: &mut Canvas<'_, F>,
    r: Rect,
    p: [Vec3; 3],
    col: Color,
    mut depth: Option<(&mut [Scalar], &mut [u16], u16)>,
) {
    if !p
        .iter()
        .all(|p| p.finite() && p.x.abs() < 1e6 && p.y.abs() < 1e6)
    {
        return;
    }
    let area = edge(p[0], p[1], p[2].x, p[2].y);
    if area.abs() < 0.000001 {
        return;
    }
    let clip = c.clip().intersect(r);
    let min_x = (libm::floorf(p[0].x.min(p[1].x).min(p[2].x)) as i32).max(clip.x);
    let max_x = (libm::ceilf(p[0].x.max(p[1].x).max(p[2].x)) as i32).min(clip.x + clip.w - 1);
    let min_y = (libm::floorf(p[0].y.min(p[1].y).min(p[2].y)) as i32).max(clip.y);
    let max_y = (libm::ceilf(p[0].y.max(p[1].y).max(p[2].y)) as i32).min(clip.y + clip.h - 1);
    for y in min_y..=max_y {
        for x in min_x..=max_x {
            let xx = x as Scalar + 0.5;
            let yy = y as Scalar + 0.5;
            let w0 = edge(p[1], p[2], xx, yy) / area;
            let w1 = edge(p[2], p[0], xx, yy) / area;
            let w2 = 1. - w0 - w1;
            if w0 >= 0. && w1 >= 0. && w2 >= 0. {
                let d = w0 * p[0].z + w1 * p[1].z + w2 * p[2].z;
                if let Some((z, groups, face)) = &mut depth {
                    let i = ((y - r.y) * r.w + x - r.x) as usize;
                    if d <= z[i] {
                        continue;
                    }
                    z[i] = d;
                    groups[i] = *face;
                }
                c.pixel(x, y, col);
            }
        }
    }
}
