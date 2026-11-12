use crate::{
    kernel::{profile, profile_contains, Point, Point3, PI},
    Colour, Dimension as D, Error, FeatureId, FeatureKind as K, Part, Vec3,
};
use alloc::{format, string::String, vec, vec::Vec};
pub const MESH_SEGS: usize = 64;
const EPS: D = 0.000001;
pub const SOLID_COLOUR: Colour = 0xffa5b2c8;
pub const HOLE_COLOUR: Colour = 0xffcd877d;

#[derive(Clone, Debug, PartialEq)]
pub struct Triangle {
    pub vertices: [Vec3; 3],
    pub normal: Vec3,
    pub colour: Colour,
    pub feature: FeatureId,
    // Retained for STL: translating in f32 first would change its bytes.
    pub(crate) precise: [Point3; 3],
}
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Mesh {
    pub(crate) triangles: Vec<Triangle>,
    /// Bodies omitted because holes could not be capped, in feature order.
    pub warnings: String,
}
impl Mesh {
    pub fn triangles(&self) -> &[Triangle] {
        &self.triangles
    }
    fn add(&mut self, p: [Point3; 3], body: FeatureId, hole: bool) {
        if p[0] == p[1] || p[1] == p[2] || p[2] == p[0] {
            return;
        }
        self.triangles.push(Triangle {
            vertices: p.map(|v| v.map(|n| n as _)),
            normal: normal(p).map(|n| n as _),
            colour: if hole { HOLE_COLOUR } else { SOLID_COLOUR },
            feature: body,
            precise: p,
        });
    }
    fn outward(&mut self, first: usize) {
        let mut volume = 0.0;
        for t in &self.triangles[first..] {
            let [a, b, c] = t.precise;
            volume += a[0] * (b[1] * c[2] - c[1] * b[2]) - b[0] * (a[1] * c[2] - c[1] * a[2])
                + c[0] * (a[1] * b[2] - b[1] * a[2]);
        }
        if volume < 0.0 {
            for t in &mut self.triangles[first..] {
                t.precise.swap(1, 2);
                t.vertices.swap(1, 2);
                t.normal = normal(t.precise).map(|n| n as _);
            }
        }
    }
}
pub(crate) fn normal([a, b, c]: [Point3; 3]) -> Point3 {
    let u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
    let v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
    let n = [
        u[1] * v[2] - u[2] * v[1],
        u[2] * v[0] - u[0] * v[2],
        u[0] * v[1] - u[1] * v[0],
    ];
    let l = libm::sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
    let l = if l == 0.0 { 1.0 } else { l };
    n.map(|n| n / l)
}
fn orient(a: Point, b: Point, c: Point) -> D {
    (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
}
fn crosses(a: Point, b: Point, c: Point, d: Point) -> bool {
    if a == c || a == d || b == c || b == d {
        return false;
    }
    ((orient(c, d, a) > 0.0) != (orient(c, d, b) > 0.0))
        && ((orient(a, b, c) > 0.0) != (orient(a, b, d) > 0.0))
}
fn clean(points: Vec<Point>) -> Vec<Point> {
    let mut p: Vec<Point> = Vec::new();
    for v in points {
        if p.last()
            .is_none_or(|q| (v[0] - q[0]).abs() > 1e-9 || (v[1] - q[1]).abs() > 1e-9)
        {
            p.push(v);
        }
    }
    while p.len() > 1 {
        let q = p[p.len() - 1];
        if (q[0] - p[0][0]).abs() > 1e-9 || (q[1] - p[0][1]).abs() > 1e-9 {
            break;
        }
        p.pop();
    }
    let mut a = 0.0;
    for i in 0..p.len() {
        let j = (i + 1) % p.len();
        a += p[i][0] * p[j][1] - p[j][0] * p[i][1];
    }
    if a < 0.0 {
        p.reverse();
    }
    p
}
fn circle(x: D, y: D, r: D, n: usize) -> Vec<Point> {
    (0..n)
        .map(|k| {
            let a = 2.0 * PI * k as D / n as D;
            [x + r * libm::cos(a), y + r * libm::sin(a)]
        })
        .collect()
}
fn inside(p: &[Point], q: Point) -> i8 {
    let mut edge = false;
    for k in 0..p.len() {
        let o = orient(p[k], p[(k + 1) % p.len()], q);
        if o < -0.0000001 {
            return -1;
        }
        if o <= 0.0000001 {
            edge = true;
        }
    }
    if edge {
        0
    } else {
        1
    }
}
fn relation(a: &[Point], b: &[Point]) -> i8 {
    let mut all = true;
    let mut any = false;
    for &q in b {
        match inside(a, q) {
            1 => any = true,
            0 => {
                any = true;
                all = false;
            }
            _ => all = false,
        }
    }
    if all {
        return 1;
    }
    if any {
        return -1;
    }
    if a.iter().any(|&q| inside(b, q) >= 0) {
        return -1;
    }
    for i in 0..a.len() {
        for j in 0..b.len() {
            if crosses(a[i], a[(i + 1) % a.len()], b[j], b[(j + 1) % b.len()]) {
                return -1;
            }
        }
    }
    0
}
#[derive(Clone)]
struct Body {
    z0: D,
    z1: D,
    outline: Vec<Point>,
}
#[derive(Clone)]
struct Hole {
    x: D,
    y: D,
    r: D,
    top: D,
    bottom: D,
    feature: FeatureId,
}
fn body(d: &Part, i: usize, segs: usize) -> Option<Body> {
    let f = d.feature(i)?;
    if f.kind != K::Extrude || f.suppressed != 0 || !d.ref_ok(i) {
        return None;
    }
    let (mut z0, mut z1) = d.extrude_range(i)?;
    if z1 < z0 {
        core::mem::swap(&mut z0, &mut z1);
    }
    if z1 - z0 < EPS {
        return None;
    }
    let p = clean(profile(d.feature(f.parent()?)?, segs).0);
    if p.len() < 3 {
        return None;
    }
    Some(Body { z0, z1, outline: p })
}
fn holes(d: &Part, i: usize, z1: D) -> Vec<Hole> {
    let Some(s) = d
        .feature(i)
        .and_then(|f| f.parent())
        .and_then(|r| d.feature(r))
    else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for j in i + 1..=d.features().len() {
        let f = &d.features()[j - 1];
        if f.kind == K::Hole
            && f.suppressed == 0
            && d.ref_ok(j)
            && profile_contains(s, f.x, f.y, f.p1 / 2.0)
        {
            if let Some((top, bottom)) = d.hole_span(j) {
                if top >= z1 - EPS && bottom <= z1 + EPS {
                    out.push(Hole {
                        x: f.x,
                        y: f.y,
                        r: f.p1 / 2.0,
                        top,
                        bottom,
                        feature: j,
                    });
                }
            }
        }
    }
    out
}
fn joins(d: &Part, bodies: &[Option<Body>], segs: usize) -> Vec<usize> {
    let mut join = vec![0; bodies.len()];
    for j in 1..bodies.len() {
        let Some(b) = &bodies[j] else {
            continue;
        };
        for i in 1..bodies.len() {
            if i == j {
                continue;
            }
            let Some(a) = &bodies[i] else {
                continue;
            };
            if (a.z1 - b.z0).abs() < EPS && relation(&a.outline, &b.outline) == 1 {
                let ok = holes(d, i, a.z1)
                    .iter()
                    .all(|h| relation(&b.outline, &circle(h.x, h.y, h.r, segs)) != -1);
                let clear = (1..j).filter(|&k| join[k] == i).all(|k| {
                    bodies[k]
                        .as_ref()
                        .is_none_or(|c| relation(&c.outline, &b.outline) == 0)
                });
                if ok && clear {
                    join[j] = i;
                    break;
                }
            }
        }
    }
    join
}
fn edges_clear(a: Point, b: Point, p: &[Point]) -> bool {
    (0..p.len()).all(|k| !crosses(a, b, p[k], p[(k + 1) % p.len()]))
}
fn bridge(outline: &[Point], loops: &[Vec<Point>]) -> Option<Vec<Point>> {
    let mut p = outline.to_vec();
    let mut done = vec![false; loops.len()];
    for _ in 0..loops.len() {
        let mut best = -1e30;
        let mut pick = None;
        let mut start = 0;
        for (l, ring) in loops.iter().enumerate() {
            if !done[l] {
                for (k, q) in ring.iter().enumerate() {
                    if q[0] > best {
                        best = q[0];
                        pick = Some(l);
                        start = k;
                    }
                }
            }
        }
        let pick = pick?;
        done[pick] = true;
        let ring = &loops[pick];
        let n = ring.len();
        let c: Vec<Point> = (0..n).map(|k| ring[(start + n - k) % n]).collect();
        let m = c[0];
        let mut tried = vec![false; p.len()];
        let mut chosen = None;
        for _ in 0..p.len() {
            let mut best = 1e30;
            let mut at = None;
            for (k, q) in p.iter().enumerate() {
                if !tried[k] {
                    let dd = (q[0] - m[0]) * (q[0] - m[0]) + (q[1] - m[1]) * (q[1] - m[1]);
                    if dd < best {
                        best = dd;
                        at = Some(k);
                    }
                }
            }
            let at = at?;
            tried[at] = true;
            if edges_clear(m, p[at], &p)
                && edges_clear(m, p[at], &c)
                && loops
                    .iter()
                    .enumerate()
                    .all(|(l, ring)| done[l] || edges_clear(m, p[at], ring))
            {
                chosen = Some(at);
                break;
            }
        }
        let at = chosen?;
        let mut next = Vec::with_capacity(p.len() + c.len() + 2);
        next.extend_from_slice(&p[..=at]);
        next.extend_from_slice(&c);
        next.push(c[0]);
        next.extend_from_slice(&p[at..]);
        p = next;
    }
    Some(p)
}
fn ear_clip(p: &[Point]) -> Option<Vec<[usize; 3]>> {
    let n = p.len();
    if n < 3 {
        return None;
    }
    let mut next: Vec<usize> = (0..n).map(|i| (i + 1) % n).collect();
    let mut prev: Vec<usize> = (0..n).map(|i| (i + n - 1) % n).collect();
    let mut left = n;
    let mut b = 0;
    let mut triangles = Vec::with_capacity(n - 2);
    while left > 3 {
        let mut found = false;
        let attempts = left;
        for _ in 0..attempts {
            let a = prev[b];
            let c = next[b];
            if orient(p[a], p[b], p[c]) > 1e-9 {
                let mut ear = true;
                let mut q = next[c];
                while q != a {
                    if p[q] != p[a]
                        && p[q] != p[b]
                        && p[q] != p[c]
                        && orient(p[a], p[b], p[q]) >= 0.0
                        && orient(p[b], p[c], p[q]) >= 0.0
                        && orient(p[c], p[a], p[q]) >= 0.0
                    {
                        ear = false;
                        break;
                    }
                    q = next[q];
                }
                if ear {
                    triangles.push([a, b, c]);
                    next[a] = c;
                    prev[c] = a;
                    left -= 1;
                    b = c;
                    found = true;
                    break;
                }
            }
            b = next[b];
        }
        if !found {
            return None;
        }
    }
    triangles.push([prev[b], b, next[b]]);
    Some(triangles)
}
fn at(p: Point, z: D) -> Point3 {
    [p[0], p[1], z]
}
fn cap(
    mesh: &mut Mesh,
    outline: &[Point],
    loops: &[Vec<Point>],
    z: D,
    up: bool,
    body: usize,
) -> bool {
    let Some(p) = bridge(outline, loops) else {
        return false;
    };
    let Some(tris) = ear_clip(&p) else {
        return false;
    };
    for [a, b, c] in tris {
        let (b, c) = if up { (b, c) } else { (c, b) };
        mesh.add([at(p[a], z), at(p[b], z), at(p[c], z)], body, false);
    }
    true
}
fn hole_disc(mesh: &mut Mesh, h: &Hole, z: D, up: bool, segs: usize) {
    let p = circle(h.x, h.y, h.r, segs);
    for k in 0..segs {
        let j = (k + 1) % segs;
        let (a, b) = if up { (k, j) } else { (j, k) };
        mesh.add([[h.x, h.y, z], at(p[a], z), at(p[b], z)], h.feature, true);
    }
}
fn extrude(
    mesh: &mut Mesh,
    d: &Part,
    i: usize,
    bodies: &[Option<Body>],
    join: &[usize],
    segs: usize,
) {
    let Some(b) = &bodies[i] else {
        return;
    };
    let p = &b.outline;
    let h = holes(d, i, b.z1);
    let mut footprint = vec![false; h.len()];
    let mut loops = Vec::new();
    for j in 1..bodies.len() {
        if join[j] == i {
            if let Some(f) = &bodies[j] {
                loops.push(f.outline.clone());
                for (k, hole) in h.iter().enumerate() {
                    if relation(&f.outline, &circle(hole.x, hole.y, hole.r, segs)) == 1 {
                        footprint[k] = true;
                    }
                }
            }
        }
    }
    for (k, hole) in h.iter().enumerate() {
        if !footprint[k] && hole.bottom < b.z1 - EPS {
            loops.push(circle(hole.x, hole.y, hole.r, segs));
        }
    }
    if !cap(mesh, p, &loops, b.z1, true, i) {
        mesh.warnings += &format!(
            "{} (its holes are too close together to cap). ",
            d.feature_name(i)
        );
        return;
    }
    if join[i] == 0 {
        let loops: Vec<Vec<Point>> = h
            .iter()
            .filter(|h| h.bottom <= b.z0 + EPS)
            .map(|h| circle(h.x, h.y, h.r, segs))
            .collect();
        cap(mesh, p, &loops, b.z0, false, i);
    }
    for k in 0..p.len() {
        let j = (k + 1) % p.len();
        mesh.add([at(p[k], b.z0), at(p[j], b.z0), at(p[j], b.z1)], i, false);
        mesh.add([at(p[k], b.z0), at(p[j], b.z1), at(p[k], b.z1)], i, false);
    }
    for (k, hole) in h.iter().enumerate() {
        let zb = hole.bottom.max(b.z0);
        if zb < b.z1 - EPS {
            let ring = circle(hole.x, hole.y, hole.r, segs);
            for a in 0..segs {
                let c = (a + 1) % segs;
                mesh.add(
                    [at(ring[c], zb), at(ring[a], zb), at(ring[a], b.z1)],
                    hole.feature,
                    true,
                );
                mesh.add(
                    [at(ring[c], zb), at(ring[a], b.z1), at(ring[c], b.z1)],
                    hole.feature,
                    true,
                );
            }
            if zb > b.z0 + EPS {
                hole_disc(mesh, hole, zb, true, segs);
            }
            if footprint[k] && hole.top <= b.z1 + EPS {
                hole_disc(mesh, hole, b.z1, false, segs);
            }
        } else if footprint[k] {
            hole_disc(mesh, hole, b.z1, true, segs);
        }
    }
}
fn revolve(mesh: &mut Mesh, d: &Part, i: usize, segs: usize) -> Result<(), Error> {
    let f = d.feature(i).ok_or(Error::InvalidFeature)?;
    let sk = f.parent().ok_or(Error::InvalidFeature)?;
    let sz = d.sketch_z(sk).ok_or(Error::InvalidFeature)?;
    if f.p1.abs() > 360.0 {
        return Err(Error::MeshTooLarge);
    }
    let p = clean(profile(d.feature(sk).ok_or(Error::InvalidFeature)?, segs).0);
    if p.len() < 3 || f.p1.abs() < EPS {
        return Ok(());
    }
    let angle = f.p1 * PI / 180.0;
    let full = (f.p1.abs() - 360.0).abs() < EPS;
    let steps = (libm::floor(f.p1.abs() / 360.0 * segs as D + 0.5) as usize).max(2);
    let spin = |p: Point, a: D| [p[0] * libm::cos(a), p[1], sz - p[0] * libm::sin(a)];
    let first = mesh.triangles.len();
    for k in 0..steps {
        let a = angle * k as D / steps as D;
        let b = if full && k + 1 == steps {
            0.0
        } else {
            angle * (k + 1) as D / steps as D
        };
        for j in 0..p.len() {
            let q = (j + 1) % p.len();
            mesh.add([spin(p[j], a), spin(p[q], a), spin(p[q], b)], i, false);
            mesh.add([spin(p[j], a), spin(p[q], b), spin(p[j], b)], i, false);
        }
    }
    if !full {
        for j in 1..p.len() - 1 {
            mesh.add([at(p[0], sz), at(p[j + 1], sz), at(p[j], sz)], i, false);
            mesh.add(
                [spin(p[0], angle), spin(p[j], angle), spin(p[j + 1], angle)],
                i,
                false,
            );
        }
    }
    mesh.outward(first);
    Ok(())
}
impl Part {
    pub fn mesh(&self, segments: usize) -> Result<Mesh, Error> {
        if !(4..=4096).contains(&segments) {
            return Err(Error::InvalidSegments);
        }
        let bodies: Vec<Option<Body>> = (0..=self.features().len())
            .map(|i| body(self, i, segments))
            .collect();
        let join = joins(self, &bodies, segments);
        let mut mesh = Mesh::default();
        for i in 1..=self.features().len() {
            let f = &self.features()[i - 1];
            if f.suppressed == 0 && self.ref_ok(i) {
                match f.kind {
                    K::Extrude => extrude(&mut mesh, self, i, &bodies, &join, segments),
                    K::Revolve => revolve(&mut mesh, self, i, segments)?,
                    _ => {}
                }
            }
        }
        if mesh.triangles.iter().any(|t| {
            t.vertices
                .iter()
                .flatten()
                .chain(t.normal.iter())
                .any(|n| !n.is_finite())
        }) {
            return Err(Error::InvalidNumber);
        }
        Ok(mesh)
    }
}
