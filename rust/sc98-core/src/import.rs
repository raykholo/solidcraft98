//! Optional, allocation-only ZIP/Deflate/JSON reader and feature-history importer.
//! No filesystem or UI dependency: callers supply bytes and receive notices.
use crate::{
    expr::evaluate,
    kernel::{profile_contains, PI},
    Dimension as D, Error, Feature, FeatureKind as K, Part, MAX_FEATURES,
};
use alloc::{
    format,
    string::{String, ToString},
    vec::Vec,
};
use serde_json::Value as V;

const EPS: D = 0.001;
const LIMIT: usize = 16 * 1024 * 1024;
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ImportNotice {
    pub name: String,
    pub kind: String,
    pub reason: String,
}
#[derive(Clone, Debug)]
pub struct ImportedPart {
    pub part: Part,
    pub notices: Vec<ImportNotice>,
    pub full: bool,
}
fn err(s: &str) -> Error {
    Error::Import(s.into())
}
fn word(v: &V) -> &str {
    v.as_str().unwrap_or_default()
}
fn num(v: &V) -> D {
    v.as_f64().unwrap_or_default()
}
fn yes(v: &V) -> bool {
    v.as_bool().unwrap_or_default()
}
fn arr(v: &V) -> &[V] {
    v.as_array().map_or(&[], |a| a.as_slice())
}
fn near(a: D, b: D) -> bool {
    (a - b).abs() < EPS
}
fn snap(v: D) -> D {
    let r = v.signum() * libm::floor(v.abs() * 1e6 + 0.5) / 1e6;
    if r.abs() < 1e-6 {
        0.0
    } else {
        r
    }
}
fn cut(s: &str, n: usize) -> String {
    s.chars().take(n).collect()
}
fn pretty(s: &str) -> String {
    let s = s.replace('_', " ");
    let mut chars = s.chars();
    match chars.next() {
        Some(c) => c.to_uppercase().chain(chars).collect(),
        None => String::new(),
    }
}
fn slice(b: &[u8], at: usize, count: usize) -> Result<&[u8], Error> {
    let end = at
        .checked_add(count)
        .ok_or_else(|| err("Invalid ZIP offset."))?;
    b.get(at..end).ok_or_else(|| err("Truncated ZIP archive."))
}
fn u16_at(b: &[u8], at: usize) -> Result<usize, Error> {
    let b = slice(b, at, 2)?;
    Ok(u16::from_le_bytes([b[0], b[1]]) as usize)
}
fn u32_at(b: &[u8], at: usize) -> Result<usize, Error> {
    let b = slice(b, at, 4)?;
    Ok(u32::from_le_bytes([b[0], b[1], b[2], b[3]]) as usize)
}
fn document(bytes: &[u8]) -> Result<Vec<u8>, Error> {
    if !bytes.starts_with(b"PK\x03\x04") {
        if bytes.len() > LIMIT {
            return Err(err("The design is too large."));
        }
        return Ok(bytes.to_vec());
    }
    let begin = bytes.len().saturating_sub(65557);
    let end = (begin..bytes.len().saturating_sub(21))
        .rev()
        .find(|&i| bytes.get(i..i + 4) == Some(b"PK\x05\x06"))
        .ok_or_else(|| err("Can't find the ZIP directory."))?;
    if u16_at(bytes, end + 4)? != 0 || u16_at(bytes, end + 6)? != 0 {
        return Err(err("Split ZIP archives are not supported."));
    }
    let count = u16_at(bytes, end + 10)?;
    let mut at = u32_at(bytes, end + 16)?;
    for _ in 0..count {
        if &slice(bytes, at, 46)?[..4] != b"PK\x01\x02" {
            return Err(err("Can't read the ZIP directory."));
        }
        let flags = u16_at(bytes, at + 8)?;
        let method = u16_at(bytes, at + 10)?;
        let crc = u32_at(bytes, at + 16)?;
        let compressed = u32_at(bytes, at + 20)?;
        let size = u32_at(bytes, at + 24)?;
        let name_len = u16_at(bytes, at + 28)?;
        let extra = u16_at(bytes, at + 30)?;
        let comment = u16_at(bytes, at + 32)?;
        let local = u32_at(bytes, at + 42)?;
        if slice(bytes, at + 46, name_len)? == b"document.json" {
            if flags & 1 != 0 {
                return Err(err("Encrypted designs are not supported."));
            }
            if size > LIMIT || compressed > LIMIT {
                return Err(err("The design is too large."));
            }
            if &slice(bytes, local, 30)?[..4] != b"PK\x03\x04" {
                return Err(err("Can't read the ZIP entry."));
            }
            let start = (local + 30)
                .checked_add(u16_at(bytes, local + 26)? + u16_at(bytes, local + 28)?)
                .ok_or_else(|| err("Invalid ZIP entry offset."))?;
            let data = slice(bytes, start, compressed)?;
            let out = match method {
                0 => data.to_vec(),
                8 => miniz_oxide::inflate::decompress_to_vec_with_limit(data, LIMIT)
                    .map_err(|_| err("Can't inflate document.json."))?,
                _ => return Err(err("That ZIP compression is not supported.")),
            };
            if out.len() != size || crc32fast::hash(&out) as usize != crc {
                return Err(err("The ZIP entry is damaged."));
            }
            return Ok(out);
        }
        at = at
            .checked_add(46 + name_len + extra + comment)
            .ok_or_else(|| err("Invalid ZIP directory."))?;
    }
    Err(err("There is no document.json in this design."))
}
#[derive(Clone)]
struct Profile {
    kind: K,
    x: D,
    y: D,
    w: D,
    h: D,
    r: D,
    parent: Option<usize>,
}
impl Profile {
    fn feature(&self) -> Feature {
        Feature {
            kind: self.kind,
            x: self.x,
            y: self.y,
            p1: self.w,
            p2: self.h,
            p3: self.r,
            ..Feature::default()
        }
    }
}
struct Sketch {
    id: i64,
    name: String,
    why: Option<String>,
    z: D,
    on_face: bool,
    ox: D,
    oy: D,
    used: bool,
    profiles: Vec<Profile>,
}
impl Sketch {
    fn not_ok(&mut self, s: impl Into<String>) {
        if self.why.is_none() {
            self.why = Some(s.into());
        }
    }
    fn add(&mut self, p: Profile) {
        if self.profiles.len() == MAX_FEATURES {
            self.not_ok("too many shapes");
        } else {
            self.profiles.push(p);
        }
    }
    fn outlines(&self) -> Vec<usize> {
        self.profiles
            .iter()
            .enumerate()
            .filter_map(|(i, p)| p.parent.is_none().then_some(i))
            .collect()
    }
}
struct Importer {
    out: ImportedPart,
    sketches: Vec<Sketch>,
    params: Vec<(String, String)>,
}
impl Importer {
    fn expr(&self, s: &str, depth: u8) -> Result<D, Error> {
        if depth > 20 {
            return Err(err("A parameter refers to itself."));
        }
        let mut out = String::new();
        let chars: Vec<char> = s.chars().collect();
        let mut i = 0;
        while i < chars.len() {
            let c = chars[i];
            if c == '°' {
                i += 1;
            } else if c.is_ascii_alphabetic() || c == '_' {
                let start = i;
                while i < chars.len() && (chars[i].is_ascii_alphanumeric() || chars[i] == '_') {
                    i += 1;
                }
                let w: String = chars[start..i].iter().collect();
                match w.to_ascii_lowercase().as_str() {
                    "mm" | "deg" | "degree" | "degrees" => {}
                    "cm" => out += "*10",
                    "m" => out += "*1000",
                    "in" | "inch" => out += "*25.4",
                    "rad" => out += "*57.2957795130823",
                    "pi" => out += &format!("{PI}"),
                    _ => {
                        let (_, expression) = self
                            .params
                            .iter()
                            .find(|(n, _)| *n == w)
                            .ok_or_else(|| err("Unknown parameter."))?;
                        let n = self.expr(expression, depth + 1)?;
                        out += &format!("({n})");
                    }
                }
            } else {
                out.push(c);
                i += 1;
            }
        }
        evaluate(&out).map_err(|_| err("Can't work out that dimension."))
    }
    fn value(&self, v: &V) -> Result<D, Error> {
        if let Some(n) = v.as_f64() {
            Ok(n)
        } else if let Some(s) = v.as_str() {
            self.expr(s, 0)
        } else {
            Err(err("Missing dimension."))
        }
    }
    fn add(&mut self, mut f: Feature, name: &str) -> Option<usize> {
        f.name = cut(name, 24);
        match self.out.part.add_named_feature(f) {
            Ok(id) => Some(id),
            Err(Error::Full) => {
                self.out.full = true;
                None
            }
            Err(_) => None,
        }
    }
    fn foreign(&mut self, f: &V, kind: &str, reason: &str) {
        let name = if word(&f["name"]).is_empty() {
            kind
        } else {
            word(&f["name"])
        };
        self.add(
            Feature {
                kind: K::Foreign,
                info: cut(kind, 32),
                ..Feature::default()
            },
            name,
        );
        self.out.notices.push(ImportNotice {
            name: name.into(),
            kind: kind.into(),
            reason: reason.into(),
        });
    }
    fn read_sketch(&mut self, f: &V) {
        let mut s = Sketch {
            id: f["id"].as_i64().unwrap_or_default(),
            name: word(&f["name"]).into(),
            why: None,
            z: 0.0,
            on_face: false,
            ox: 0.0,
            oy: 0.0,
            used: false,
            profiles: Vec::new(),
        };
        let plane = &f["plane"];
        match word(&plane["type"]) {
            "origin" => {
                if word(&plane["name"]) != "XY" {
                    s.not_ok(format!("drawn on the {} plane", word(&plane["name"])));
                } else if !plane["offset"].is_null() {
                    match self.value(&plane["offset"]) {
                        Ok(n) => s.z = n,
                        Err(_) => s.not_ok("an offset SolidCraft 98 can't work out"),
                    }
                }
            }
            "face" => {
                let p = &plane["plane"];
                if !near(num(&p["x_dir"][0]), 1.0) || !near(num(&p["y_dir"][1]), 1.0) {
                    s.not_ok("drawn on a face that doesn't point straight up");
                } else {
                    s.ox = num(&p["origin"][0]);
                    s.oy = num(&p["origin"][1]);
                    s.z = num(&p["origin"][2]);
                    s.on_face = true;
                }
            }
            _ => s.not_ok("drawn on a construction plane"),
        }
        if yes(&plane["flip"]) {
            s.not_ok("drawn on a flipped plane");
        }
        let points: Vec<[D; 2]> = arr(&f["sketch"]["points"])
            .iter()
            .map(|p| [s.ox + num(&p["pos"][0]), s.oy + num(&p["pos"][1])])
            .collect();
        let curves: Vec<&V> = arr(&f["sketch"]["curves"])
            .iter()
            .filter(|c| !yes(&c["construction"]) && c["link"].is_null())
            .collect();
        let point = |v: &V| {
            v.as_u64()
                .and_then(|n| usize::try_from(n).ok())
                .and_then(|n| points.get(n))
                .copied()
        };
        let (mut lines, mut arcs) = (0, 0);
        let mut radius: Option<D> = None;
        let mut min = [1e30, 1e30];
        let mut max = [-1e30, -1e30];
        let grow = |p: [D; 2], min: &mut [D; 2], max: &mut [D; 2]| {
            for k in 0..2 {
                min[k] = min[k].min(p[k]);
                max[k] = max[k].max(p[k]);
            }
        };
        for c in &curves {
            match word(&c["type"]) {
                "circle" => {
                    if let Some(p) = point(&c["c"]) {
                        s.add(Profile {
                            kind: K::Circle,
                            x: p[0],
                            y: p[1],
                            w: num(&c["r"]),
                            h: 0.0,
                            r: 0.0,
                            parent: None,
                        });
                    }
                }
                "line" => {
                    if let (Some(a), Some(b)) = (point(&c["a"]), point(&c["b"])) {
                        if !near(a[0], b[0]) && !near(a[1], b[1]) {
                            s.not_ok("a line that isn't horizontal or vertical");
                        }
                        grow(a, &mut min, &mut max);
                        grow(b, &mut min, &mut max);
                        lines += 1;
                    } else {
                        s.not_ok("a broken line");
                    }
                }
                "arc" => {
                    if let (Some(a), Some(b)) = (point(&c["a"]), point(&c["c"])) {
                        let v = libm::sqrt(
                            (a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]),
                        );
                        if radius.is_some_and(|r| !near(v, r)) {
                            s.not_ok("corners of different sizes");
                        }
                        radius = Some(v);
                        arcs += 1;
                    } else {
                        s.not_ok("a broken arc");
                    }
                }
                kind => s.not_ok(format!("a {kind}")),
            }
        }
        if lines > 0 || arcs > 0 {
            if lines == 4 && (arcs == 0 || arcs == 4) {
                let r = if arcs == 0 {
                    0.0
                } else {
                    radius.unwrap_or_default()
                };
                if r > 0.0 {
                    for c in &curves {
                        if word(&c["type"]) == "arc" {
                            if let (Some(a), Some(center)) = (point(&c["a"]), point(&c["c"])) {
                                let r = libm::sqrt(
                                    (a[0] - center[0]) * (a[0] - center[0])
                                        + (a[1] - center[1]) * (a[1] - center[1]),
                                );
                                grow([center[0] - r, center[1] - r], &mut min, &mut max);
                                grow([center[0] + r, center[1] + r], &mut min, &mut max);
                            }
                        }
                    }
                }
                s.add(Profile {
                    kind: K::Rectangle,
                    x: min[0],
                    y: min[1],
                    w: max[0] - min[0],
                    h: max[1] - min[1],
                    r,
                    parent: None,
                });
            } else {
                s.not_ok("a shape that isn't a rectangle or a circle");
            }
        }
        if s.profiles.is_empty() {
            s.not_ok("nothing SolidCraft 98 can draw");
        }
        if s.why.is_none() {
            for i in 0..s.profiles.len() {
                if s.profiles[i].kind == K::Circle {
                    for j in 0..s.profiles.len() {
                        let (a, b) = (&s.profiles[i], &s.profiles[j]);
                        if j != i
                            && b.parent.is_none()
                            && profile_contains(&b.feature(), a.x, a.y, a.w)
                            && !(b.kind == K::Circle && b.w <= a.w)
                        {
                            s.profiles[i].parent = Some(j);
                            break;
                        }
                    }
                }
            }
            for p in &s.profiles {
                if p.parent.is_some_and(|i| s.profiles[i].parent.is_some()) {
                    s.why = Some("islands inside holes".into());
                    break;
                }
            }
        }
        self.sketches.push(s);
    }
    fn target(&self, z: D, x: D, y: D, r: D) -> Option<usize> {
        (1..=self.out.part.features().len()).rev().find(|&i| {
            let f = &self.out.part.features()[i - 1];
            f.kind == K::Extrude
                && self.out.part.ref_ok(i)
                && self
                    .out
                    .part
                    .extrude_range(i)
                    .is_some_and(|(_, top)| near(top, z))
                && f.parent()
                    .and_then(|r| self.out.part.feature(r))
                    .is_some_and(|s| profile_contains(s, x, y, r))
        })
    }
    fn emit(&mut self, k: usize, z: D) -> Vec<Option<usize>> {
        self.sketches[k].used = true;
        let outlines = self.sketches[k].outlines();
        let multiple = outlines.len() > 1;
        let mut result = Vec::new();
        for (n, i) in outlines.into_iter().enumerate() {
            let s = &self.sketches[k];
            let mut f = s.profiles[i].feature();
            let target = if s.on_face && near(z, s.z) {
                self.target(z, f.x, f.y, 0.0)
            } else {
                None
            };
            if let Some(t) = target {
                f.reference = t as i16;
                f.z = snap(z - self.out.part.extrude_range(t).map_or(0.0, |(_, t)| t));
            } else {
                f.z = snap(z);
            }
            let name = if multiple {
                format!("{} {}", cut(&s.name, 20), n + 1)
            } else {
                s.name.clone()
            };
            result.push(self.add(f, &name));
        }
        result
    }
    fn sketch_for(&mut self, f: &V, kind: &str) -> Option<usize> {
        let id = f["sketch"].as_i64();
        let k = self.sketches.iter().position(|s| Some(s.id) == id);
        let Some(k) = k else {
            self.foreign(f, kind, "not from a sketch");
            return None;
        };
        if let Some(why) = self.sketches[k].why.clone() {
            self.sketches[k].used = true;
            self.foreign(f, kind, &format!("its sketch has {why}"));
            return None;
        }
        Some(k)
    }
    fn import_cut(&mut self, f: &V, k: usize, dist: D, through: bool) {
        let mut targets = Vec::new();
        for p in &self.sketches[k].profiles {
            if p.kind != K::Circle {
                self.sketches[k].used = true;
                self.foreign(f, "Extrude (cut)", "a cut that isn't round");
                return;
            }
            let Some(t) = self.target(self.sketches[k].z, p.x, p.y, p.w) else {
                self.sketches[k].used = true;
                self.foreign(f, "Extrude (cut)", "not into the top of a block");
                return;
            };
            targets.push(t);
        }
        self.sketches[k].used = true;
        for (i, t) in targets.iter().enumerate() {
            let p = &self.sketches[k].profiles[i];
            let h = Feature {
                kind: K::Hole,
                reference: *t as i16,
                x: p.x,
                y: p.y,
                p1: p.w * 2.0,
                p2: if through { 0.0 } else { dist },
                ..Feature::default()
            };
            let name = if targets.len() > 1 {
                format!("{} {}", cut(word(&f["name"]), 20), i + 1)
            } else {
                word(&f["name"]).into()
            };
            if self.add(h, &name).is_none() {
                return;
            }
        }
    }
    fn extrude(&mut self, f: &V) {
        let Some(k) = self.sketch_for(f, "Extrude") else {
            return;
        };
        let reason = if word(&f["profiles"]["type"]) != "all" {
            Some("only some of its sketch's profiles")
        } else if !f["taper"].is_null() {
            Some("tapered")
        } else if ["distance2", "to", "start_offset"]
            .iter()
            .any(|&s| !f["extent"][s].is_null())
        {
            Some("an extent SolidCraft 98 doesn't have")
        } else {
            None
        };
        if let Some(why) = reason {
            self.foreign(f, "Extrude", why);
            return;
        }
        let e = &f["extent"];
        let through = yes(&e["through_all"]);
        let dist = if through {
            0.0
        } else {
            match self.value(&e["distance"]) {
                Ok(n) if n > 0.0 => n,
                _ => {
                    self.foreign(f, "Extrude", "a distance SolidCraft 98 can't work out");
                    return;
                }
            }
        };
        match word(&f["operation"]) {
            "cut" => {
                self.import_cut(f, k, dist, through);
                return;
            }
            "new_body" | "new" | "join" | "auto" | "" => {}
            op => {
                self.foreign(f, "Extrude", &pretty(op));
                return;
            }
        }
        if through {
            self.foreign(f, "Extrude", "through all");
            return;
        }
        let z = self.sketches[k].z
            - match word(&e["direction"]) {
                "negative" => dist,
                "symmetric" => dist / 2.0,
                _ => 0.0,
            };
        let ids = self.emit(k, z);
        let outlines = self.sketches[k].outlines();
        let mut c = 0;
        for (i, id) in ids.iter().enumerate() {
            let Some(id) = id else {
                return;
            };
            let name = if ids.len() > 1 {
                format!("{} {}", cut(word(&f["name"]), 20), i + 1)
            } else {
                word(&f["name"]).into()
            };
            let Some(j) = self.add(
                Feature {
                    kind: K::Extrude,
                    reference: *id as i16,
                    p1: dist,
                    ..Feature::default()
                },
                &name,
            ) else {
                return;
            };
            let inner: Vec<Profile> = self.sketches[k]
                .profiles
                .iter()
                .filter(|p| p.parent == Some(outlines[i]))
                .cloned()
                .collect();
            for p in inner {
                c += 1;
                self.add(
                    Feature {
                        kind: K::Hole,
                        reference: j as i16,
                        x: p.x,
                        y: p.y,
                        p1: p.w * 2.0,
                        p2: dist,
                        ..Feature::default()
                    },
                    &format!("{} hole {c}", cut(word(&f["name"]), 17)),
                );
            }
        }
    }
    fn revolve(&mut self, f: &V) {
        let Some(k) = self.sketch_for(f, "Revolve") else {
            return;
        };
        let why = if word(&f["axis"]["type"]) != "sketch_axis" || word(&f["axis"]["axis"]) != "y" {
            Some("about an axis other than the sketch's Y".to_string())
        } else if !near(self.sketches[k].ox, 0.0) {
            Some("about an axis off the origin".into())
        } else if matches!(word(&f["operation"]), "cut" | "intersect") {
            Some(pretty(word(&f["operation"])))
        } else if word(&f["direction"]) == "symmetric"
            || !f["angle2"].is_null()
            || !f["to"].is_null()
        {
            Some("a two-sided or symmetric angle".into())
        } else if word(&f["profiles"]["type"]) != "all" {
            Some("only some of its sketch's profiles".into())
        } else {
            None
        };
        if let Some(why) = why {
            self.foreign(f, "Revolve", &why);
            return;
        }
        let angle = if f["angle"].is_null() {
            360.0
        } else {
            match self.value(&f["angle"]) {
                Ok(n) => n,
                Err(_) => {
                    self.foreign(f, "Revolve", "an angle SolidCraft 98 can't work out");
                    return;
                }
            }
        };
        if angle == 0.0 || angle.abs() > 360.0 {
            self.foreign(f, "Revolve", "an angle over 360 degrees");
            return;
        }
        for p in &self.sketches[k].profiles {
            let why = if p.parent.is_some() {
                Some("a profile with a hole in it")
            } else if if p.kind == K::Circle {
                p.x - p.w < -EPS && p.x + p.w > EPS
            } else {
                p.x < -EPS && p.x + p.w > EPS
            } {
                Some("a profile across the axis")
            } else {
                None
            };
            if let Some(why) = why {
                self.foreign(f, "Revolve", why);
                return;
            }
        }
        let ids = self.emit(k, self.sketches[k].z);
        for (i, id) in ids.iter().enumerate() {
            let Some(id) = id else {
                return;
            };
            let name = if ids.len() > 1 {
                format!("{} {}", cut(word(&f["name"]), 20), i + 1)
            } else {
                word(&f["name"]).into()
            };
            if self
                .add(
                    Feature {
                        kind: K::Revolve,
                        reference: *id as i16,
                        p1: -angle,
                        ..Feature::default()
                    },
                    &name,
                )
                .is_none()
            {
                return;
            }
        }
    }
    fn hole(&mut self, f: &V) {
        let dir = &f["direction"];
        let kind = word(&f["hole"]["type"]);
        let why = if !f["position"].is_array() {
            Some("placed on sketch points".into())
        } else if !(dir.is_null()
            || (near(num(&dir[0]), 0.0) && near(num(&dir[1]), 0.0) && num(&dir[2]) < 0.0))
        {
            Some("not straight down".into())
        } else if !matches!(kind, "" | "simple" | "drilled") {
            Some(pretty(kind))
        } else if f["diameter"].is_null() {
            Some("a clearance or tapped size".into())
        } else if !f["to"].is_null() {
            Some("drilled to an object".into())
        } else {
            None
        };
        if let Some(why) = why {
            self.foreign(f, "Hole", &why);
            return;
        }
        let dia = match self.value(&f["diameter"]) {
            Ok(n) if n > 0.0 => n,
            _ => {
                self.foreign(f, "Hole", "a diameter SolidCraft 98 can't work out");
                return;
            }
        };
        let depth = if f["depth"].is_null() {
            0.0
        } else {
            match self.value(&f["depth"]) {
                Ok(n) if n > 0.0 => n,
                _ => {
                    self.foreign(f, "Hole", "a depth SolidCraft 98 can't work out");
                    return;
                }
            }
        };
        let pos: Result<Vec<D>, _> = arr(&f["position"]).iter().map(|v| self.value(v)).collect();
        let Ok(pos) = pos else {
            self.foreign(f, "Hole", "a position SolidCraft 98 can't work out");
            return;
        };
        if pos.len() != 3 {
            self.foreign(f, "Hole", "a broken position");
            return;
        }
        let Some(t) = self.target(pos[2], pos[0], pos[1], dia / 2.0) else {
            self.foreign(f, "Hole", "not on the top of a block SolidCraft 98 built");
            return;
        };
        self.add(
            Feature {
                kind: K::Hole,
                reference: t as i16,
                x: pos[0],
                y: pos[1],
                p1: dia,
                p2: depth,
                ..Feature::default()
            },
            word(&f["name"]),
        );
    }
}
/// Open a zipped .solidcraft or plain JSON design. `fallback_title` replaces a blank name.
pub fn open(bytes: &[u8], fallback_title: &str) -> Result<ImportedPart, Error> {
    let doc = document(bytes)?;
    let doc = doc.strip_prefix(b"\xef\xbb\xbf").unwrap_or(&doc);
    let root: V = serde_json::from_slice(doc)
        .map_err(|e| Error::Import(format!("Can't read this design: {e}")))?;
    let format = word(&root["format"]);
    if !root["features"].is_array()
        || !(format.starts_with("solidcraft/") || format.starts_with("solvecraft/"))
    {
        return Err(err(
            "This isn't a SolidCraft design that SolidCraft 98 can read.",
        ));
    }
    let title = cut(word(&root["name"]), 64);
    let title = if title.trim().is_empty() {
        fallback_title.into()
    } else {
        title
    };
    let mut i = Importer {
        out: ImportedPart {
            part: Part::new(title),
            notices: Vec::new(),
            full: false,
        },
        sketches: Vec::new(),
        params: arr(&root["params"])
            .iter()
            .map(|p| (word(&p["name"]).into(), word(&p["expr"]).into()))
            .collect(),
    };
    for f in arr(&root["features"]) {
        match word(&f["type"]) {
            "sketch" => i.read_sketch(f),
            "extrude" => i.extrude(f),
            "revolve" => i.revolve(f),
            "hole" => i.hole(f),
            kind => i.foreign(f, &pretty(kind), ""),
        }
    }
    for k in 0..i.sketches.len() {
        if i.sketches[k].why.is_none() && !i.sketches[k].used {
            i.emit(k, i.sketches[k].z);
        }
    }
    Ok(i.out)
}
