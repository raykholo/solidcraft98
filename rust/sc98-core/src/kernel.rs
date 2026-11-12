use crate::{
    Colour, Dimension as D, Error, Feature, FeatureId, FeatureKind as K, Mesh, Part, Vec3,
};
use alloc::{vec, vec::Vec};
// The reference's decimal PI is deliberately shorter than the mathematical constant.
#[allow(clippy::approx_constant)]
pub(crate) const PI: D = 3.14159265358979;
pub const CIRCLE_SEGS: usize = 32;
pub const COL_SKETCH: Colour = 0xff0000c0;
pub const COL_SKETCH_USED: Colour = 0xff80a0c0;
pub const COL_SOLID: Colour = 0xff000000;
pub const COL_HOLE: Colour = 0xff800000;
pub const COL_AXIS: Colour = 0xff808080;
pub(crate) type Point = [D; 2];
pub(crate) type Point3 = [D; 3];
#[derive(Clone, Debug, PartialEq)]
pub struct Edge {
    pub vertices: [Vec3; 2],
    pub colour: Colour,
}
#[derive(Clone, Debug)]
pub struct Rebuild {
    pub edges: Vec<Edge>,
    pub mesh: Mesh,
    pub invalid_features: Vec<FeatureId>,
}

pub(crate) fn profile(f: &Feature, segments: usize) -> (Vec<Point>, Vec<bool>) {
    let mut points = Vec::new();
    let mut seam = Vec::new();
    if f.kind == K::Rectangle {
        let r = f.p3;
        if r <= 0.0 {
            return (
                vec![
                    [f.x, f.y],
                    [f.x + f.p1, f.y],
                    [f.x + f.p1, f.y + f.p2],
                    [f.x, f.y + f.p2],
                ],
                vec![true; 4],
            );
        }
        let k = (segments / 4).max(2);
        for c in 0..4 {
            let (cx, cy) = match c {
                0 => (f.x + f.p1 - r, f.y + r),
                1 => (f.x + f.p1 - r, f.y + f.p2 - r),
                2 => (f.x + r, f.y + f.p2 - r),
                _ => (f.x + r, f.y + r),
            };
            for j in 0..=k {
                let a = (c as D * 90.0 - 90.0 + 90.0 * j as D / k as D) * PI / 180.0;
                points.push([cx + r * libm::cos(a), cy + r * libm::sin(a)]);
                seam.push(j == 0 || j == k);
            }
        }
    } else {
        for i in 0..segments {
            let a = 2.0 * PI * i as D / segments as D;
            points.push([f.x + f.p1 * libm::cos(a), f.y + f.p1 * libm::sin(a)]);
            seam.push(i % 4 == 0);
        }
    }
    (points, seam)
}
pub fn profile_contains(s: &Feature, x: D, y: D, rr: D) -> bool {
    const EPS: D = 0.000001;
    if s.kind == K::Circle {
        return libm::sqrt((x - s.x) * (x - s.x) + (y - s.y) * (y - s.y)) + rr <= s.p1 + EPS;
    }
    if x - rr < s.x - EPS
        || x + rr > s.x + s.p1 + EPS
        || y - rr < s.y - EPS
        || y + rr > s.y + s.p2 + EPS
    {
        return false;
    }
    let r = s.p3;
    if r > 0.0 {
        let cx = x.max(s.x + r).min(s.x + s.p1 - r);
        let cy = y.max(s.y + r).min(s.y + s.p2 - r);
        if libm::sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) + rr > r + EPS
            && (x < s.x + r || x > s.x + s.p1 - r)
            && (y < s.y + r || y > s.y + s.p2 - r)
        {
            return false;
        }
    }
    true
}
impl Part {
    pub fn ref_ok(&self, id: FeatureId) -> bool {
        let Some(f) = self.feature(id) else {
            return false;
        };
        let parent = f
            .parent()
            .filter(|&r| r < id)
            .and_then(|r| self.feature(r).map(|p| (r, p)));
        match f.kind {
            K::Rectangle | K::Circle => {
                f.reference == 0
                    || parent.is_some_and(|(r, p)| p.kind == K::Extrude && self.ref_ok(r))
            }
            K::Extrude | K::Revolve => parent.is_some_and(|(_, p)| p.kind.is_sketch()),
            K::Foreign => true,
            K::Hole => parent.is_some_and(|(r, p)| {
                p.kind == K::Extrude
                    && self.ref_ok(r)
                    && p.parent()
                        .and_then(|r| self.feature(r))
                        .is_some_and(|s| profile_contains(s, f.x, f.y, f.p1 / 2.0))
            }),
            _ => false,
        }
    }
    pub fn sketch_z(&self, id: FeatureId) -> Option<D> {
        let f = self.feature(id)?;
        let mut z = f.z;
        if let Some(r) = f.parent().filter(|&r| r < id) {
            if self.feature(r)?.kind == K::Extrude {
                z += self.extrude_range(r)?.1;
            }
        }
        Some(z)
    }
    pub fn extrude_range(&self, id: FeatureId) -> Option<(D, D)> {
        let f = self.feature(id)?;
        let r = f.parent().filter(|&r| r < id)?;
        let z = self.sketch_z(r)?;
        Some((z, z + f.p1))
    }
    pub fn hole_span(&self, id: FeatureId) -> Option<(D, D)> {
        let f = self.feature(id)?;
        let r = f.parent().filter(|&r| r < id)?;
        let (mut bottom, top) = self.extrude_range(r)?;
        if f.p2 > 0.0 {
            return Some((top, top - f.p2));
        }
        loop {
            let mut moved = false;
            for j in 1..id {
                let g = self.feature(j)?;
                if g.kind == K::Extrude && g.suppressed == 0 && j != r && self.ref_ok(j) {
                    let (b0, b1) = self.extrude_range(j)?;
                    if b0 < bottom - 0.000001
                        && b1 >= bottom - 0.000001
                        && b1 <= top + 0.000001
                        && g.parent()
                            .and_then(|r| self.feature(r))
                            .is_some_and(|s| profile_contains(s, f.x, f.y, f.p1 / 2.0))
                    {
                        bottom = b0;
                        moved = true;
                    }
                }
            }
            if !moved {
                break;
            }
        }
        Some((top, bottom))
    }
    pub fn regenerate(&self) -> Result<Vec<Edge>, Error> {
        let mut edges = Vec::new();
        let mut used = vec![false; self.count + 1];
        for f in self.features() {
            if matches!(f.kind, K::Extrude | K::Revolve) {
                if let Some(r) = f.parent().filter(|&r| r <= self.count) {
                    used[r] = true;
                }
            }
        }
        let add = |e: &mut Vec<Edge>, a: Point3, b: Point3, c| {
            e.push(Edge {
                vertices: [a.map(|v| v as _), b.map(|v| v as _)],
                colour: c,
            });
        };
        let circle = |e: &mut Vec<Edge>, x: D, y: D, z: D, r: D, c| {
            for i in 0..CIRCLE_SEGS {
                let a = 2.0 * PI * i as D / CIRCLE_SEGS as D;
                let b = 2.0 * PI * (i + 1) as D / CIRCLE_SEGS as D;
                add(
                    e,
                    [x + r * libm::cos(a), y + r * libm::sin(a), z],
                    [x + r * libm::cos(b), y + r * libm::sin(b), z],
                    c,
                );
            }
        };
        for (i, &is_used) in used.iter().enumerate().skip(1) {
            let f = &self.records[i - 1];
            if f.suppressed != 0 || !self.ref_ok(i) {
                continue;
            }
            let col = if is_used { COL_SKETCH_USED } else { COL_SKETCH };
            match f.kind {
                K::Rectangle => {
                    let z = self.sketch_z(i).ok_or(Error::InvalidFeature)?;
                    let (p, _) = profile(f, CIRCLE_SEGS);
                    for j in 0..p.len() {
                        let k = (j + 1) % p.len();
                        add(
                            &mut edges,
                            [p[j][0], p[j][1], z],
                            [p[k][0], p[k][1], z],
                            col,
                        );
                    }
                }
                K::Circle => circle(
                    &mut edges,
                    f.x,
                    f.y,
                    self.sketch_z(i).ok_or(Error::InvalidFeature)?,
                    f.p1,
                    col,
                ),
                K::Extrude => {
                    let (z0, z1) = self.extrude_range(i).ok_or(Error::InvalidFeature)?;
                    let s = self
                        .feature(f.parent().ok_or(Error::InvalidFeature)?)
                        .ok_or(Error::InvalidFeature)?;
                    let (p, seam) = profile(s, CIRCLE_SEGS);
                    for j in 0..p.len() {
                        let k = (j + 1) % p.len();
                        add(
                            &mut edges,
                            [p[j][0], p[j][1], z0],
                            [p[k][0], p[k][1], z0],
                            COL_SOLID,
                        );
                        add(
                            &mut edges,
                            [p[j][0], p[j][1], z1],
                            [p[k][0], p[k][1], z1],
                            COL_SOLID,
                        );
                        if seam[j] {
                            add(
                                &mut edges,
                                [p[j][0], p[j][1], z0],
                                [p[j][0], p[j][1], z1],
                                COL_SOLID,
                            );
                        }
                    }
                }
                K::Revolve => {
                    if f.p1.abs() > 360.0 {
                        return Err(Error::MeshTooLarge);
                    }
                    let sk = f.parent().ok_or(Error::InvalidFeature)?;
                    let s = self.feature(sk).ok_or(Error::InvalidFeature)?;
                    let z = self.sketch_z(sk).ok_or(Error::InvalidFeature)?;
                    let (p, seam) = profile(s, CIRCLE_SEGS);
                    let steps = (libm::floor(f.p1.abs() / 15.0 + 0.5) as usize).max(1);
                    let spin =
                        |p: Point, a: D| [p[0] * libm::cos(a), p[1], z - p[0] * libm::sin(a)];
                    for k in 0..=steps {
                        let a = f.p1 * PI / 180.0 * k as D / steps as D;
                        if k == 0 || k == steps || k % 3 == 0 {
                            for j in 0..p.len() {
                                add(
                                    &mut edges,
                                    spin(p[j], a),
                                    spin(p[(j + 1) % p.len()], a),
                                    COL_SOLID,
                                );
                            }
                        }
                        if k < steps {
                            let b = f.p1 * PI / 180.0 * (k + 1) as D / steps as D;
                            for j in 0..p.len() {
                                if seam[j] && (p.len() <= 4 || s.kind == K::Rectangle || j % 8 == 0)
                                {
                                    add(&mut edges, spin(p[j], a), spin(p[j], b), COL_SOLID);
                                }
                            }
                        }
                    }
                    add(
                        &mut edges,
                        [0.0, -10.0, z],
                        [
                            0.0,
                            10.0 + p.iter().map(|p| p[1].abs()).fold(0.0, D::max),
                            z,
                        ],
                        COL_AXIS,
                    );
                }
                K::Hole => {
                    let (top, bot) = self.hole_span(i).ok_or(Error::InvalidFeature)?;
                    let r = f.p1 / 2.0;
                    circle(&mut edges, f.x, f.y, top, r, COL_HOLE);
                    circle(&mut edges, f.x, f.y, bot, r, COL_HOLE);
                    for j in 0..4 {
                        let a = j as D * PI / 2.0;
                        add(
                            &mut edges,
                            [f.x + r * libm::cos(a), f.y + r * libm::sin(a), top],
                            [f.x + r * libm::cos(a), f.y + r * libm::sin(a), bot],
                            COL_HOLE,
                        );
                    }
                }
                _ => {}
            }
        }
        if edges
            .iter()
            .flat_map(|e| e.vertices.iter().flatten())
            .any(|n| !n.is_finite())
        {
            return Err(Error::InvalidNumber);
        }
        Ok(edges)
    }
    pub fn rebuild(&self, segments: usize) -> Result<Rebuild, Error> {
        Ok(Rebuild {
            edges: self.regenerate()?,
            mesh: self.mesh(segments)?,
            invalid_features: (1..=self.count).filter(|&i| !self.ref_ok(i)).collect(),
        })
    }
}
