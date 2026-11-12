use crate::{Dimension, Error};
use alloc::{
    format,
    string::{String, ToString},
    vec,
    vec::Vec,
};

pub const MAX_FEATURES: usize = 64;
/// Feature numbers are one based; zero means the ground plane.
pub type FeatureId = usize;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum FeatureKind {
    #[default]
    None,
    Rectangle,
    Circle,
    Extrude,
    Revolve,
    Hole,
    Foreign,
    Unknown(i16),
}
impl FeatureKind {
    pub fn code(self) -> i16 {
        match self {
            Self::None => 0,
            Self::Rectangle => 1,
            Self::Circle => 2,
            Self::Extrude => 3,
            Self::Revolve => 4,
            Self::Hole => 5,
            Self::Foreign => 9,
            Self::Unknown(n) => n,
        }
    }
    pub fn from_code(n: i16) -> Self {
        match n {
            0 => Self::None,
            1 => Self::Rectangle,
            2 => Self::Circle,
            3 => Self::Extrude,
            4 => Self::Revolve,
            5 => Self::Hole,
            9 => Self::Foreign,
            n => Self::Unknown(n),
        }
    }
    pub fn is_sketch(self) -> bool {
        matches!(self, Self::Rectangle | Self::Circle)
    }
    pub fn name(self) -> &'static str {
        match self {
            Self::Rectangle => "Sketch (Rectangle)",
            Self::Circle => "Sketch (Circle)",
            Self::Extrude => "Extrude",
            Self::Revolve => "Revolve",
            Self::Hole => "Hole",
            Self::Foreign => "SolidCraft",
            _ => "?",
        }
    }
    pub fn prefix(self) -> &'static str {
        match self {
            Self::Rectangle | Self::Circle => "Sketch",
            Self::Extrude => "Extrude",
            Self::Revolve => "Revolve",
            Self::Hole => "Hole",
            _ => "",
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Feature {
    pub kind: FeatureKind,
    pub name: String,
    pub x: Dimension,
    pub y: Dimension,
    /// Height above the ground, or above `reference`'s top face for a sketch.
    pub z: Dimension,
    /// Rectangle width, circle radius, extrude depth, revolve degrees, or hole diameter.
    pub p1: Dimension,
    /// Rectangle height or hole depth (zero means through all).
    pub p2: Dimension,
    pub reference: i16,
    pub suppressed: i16,
    /// Rectangle corner radius.
    pub p3: Dimension,
    pub info: String,
}
impl Feature {
    pub(crate) fn finite(&self) -> bool {
        [self.x, self.y, self.z, self.p1, self.p2, self.p3]
            .iter()
            .all(|x| x.is_finite())
    }
    pub fn parent(&self) -> Option<FeatureId> {
        usize::try_from(self.reference).ok().filter(|&n| n > 0)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Part {
    pub title: String,
    pub(crate) count: usize,
    // Keep inactive records too: the original editions resave their fields.
    pub(crate) records: Vec<Feature>,
}
impl Part {
    pub fn new(title: impl Into<String>) -> Self {
        Self {
            title: title.into(),
            count: 0,
            records: vec![Feature::default(); MAX_FEATURES],
        }
    }
    pub fn features(&self) -> &[Feature] {
        &self.records[..self.count]
    }
    pub fn feature(&self, id: FeatureId) -> Option<&Feature> {
        id.checked_sub(1).and_then(|n| self.features().get(n))
    }
    pub fn add_feature(&mut self, mut feature: Feature) -> Result<FeatureId, Error> {
        let n = self
            .features()
            .iter()
            .filter(|f| f.kind.prefix() == feature.kind.prefix())
            .count()
            + 1;
        feature.name = format!("{}{n}", feature.kind.prefix());
        self.add_named_feature(feature)
    }
    pub fn add_named_feature(&mut self, feature: Feature) -> Result<FeatureId, Error> {
        if self.count == MAX_FEATURES {
            return Err(Error::Full);
        }
        if !feature.finite() {
            return Err(Error::InvalidNumber);
        }
        self.records[self.count] = feature;
        self.count += 1;
        Ok(self.count)
    }
    pub fn edit_feature(&mut self, id: FeatureId, feature: Feature) -> Result<(), Error> {
        if self.feature(id).is_none() {
            return Err(Error::InvalidFeature);
        }
        if !feature.finite() {
            return Err(Error::InvalidNumber);
        }
        self.records[id - 1] = feature;
        Ok(())
    }
    pub fn last_free_sketch(&self) -> Option<FeatureId> {
        (1..=self.count).rev().find(|&i| {
            self.records[i - 1].kind.is_sketch()
                && !self.features()[i..].iter().any(|f| {
                    f.parent() == Some(i)
                        && matches!(f.kind, FeatureKind::Extrude | FeatureKind::Revolve)
                })
        })
    }
    pub fn last_solid(&self) -> Option<FeatureId> {
        (1..=self.count)
            .rev()
            .find(|&i| self.records[i - 1].kind == FeatureKind::Extrude)
    }
    pub fn dependents(&self, id: FeatureId) -> Result<Vec<FeatureId>, Error> {
        if self.feature(id).is_none() {
            return Err(Error::InvalidFeature);
        }
        let mut gone = [false; MAX_FEATURES + 1];
        gone[id] = true;
        for j in id + 1..=self.count {
            if let Some(r) = self.records[j - 1].parent().filter(|&r| r <= self.count) {
                if gone[r] {
                    gone[j] = true;
                }
            }
        }
        Ok((1..=self.count).filter(|&i| gone[i]).collect())
    }
    /// Delete a feature and all descendants, preserving names and remapping references.
    pub fn delete_with_dependents(&mut self, id: FeatureId) -> Result<Vec<FeatureId>, Error> {
        let gone = self.dependents(id)?;
        let mut map = [0i16; MAX_FEATURES + 1];
        let mut n = 0;
        for i in 1..=self.count {
            if !gone.contains(&i) {
                n += 1;
                map[i] = n as i16;
                self.records[n - 1] = self.records[i - 1].clone();
                if let Some(r) = self.records[n - 1].parent() {
                    self.records[n - 1].reference = map.get(r).copied().unwrap_or_default();
                }
            }
        }
        for f in &mut self.records[n..self.count] {
            *f = Feature::default();
        }
        self.count = n;
        Ok(gone)
    }
    pub fn feature_name(&self, id: FeatureId) -> &str {
        self.feature(id).map_or("", |f| f.name.as_str())
    }
    pub fn describe(&self, id: FeatureId) -> Result<String, Error> {
        let f = self.feature(id).ok_or(Error::InvalidFeature)?;
        let parent = self.feature_name(f.parent().unwrap_or_default());
        let place = if f.reference > 0 {
            format!(
                ", on {parent}{}",
                if f.z == 0.0 {
                    String::new()
                } else {
                    format!(
                        " {}{}",
                        if f.z > 0.0 { "+" } else { "" },
                        fmt_number(f.z, 2)
                    )
                }
            )
        } else if f.z != 0.0 {
            format!(", Z {}", fmt_number(f.z, 2))
        } else {
            String::new()
        };
        let p = fmt_number(f.p1, 2);
        Ok(match f.kind {
            FeatureKind::Rectangle => format!(
                "{p} x {} mm at ({}, {}){}{}",
                fmt_number(f.p2, 2),
                fmt_number(f.x, 2),
                fmt_number(f.y, 2),
                if f.p3 > 0.0 {
                    format!(", R{} corners", fmt_number(f.p3, 2))
                } else {
                    String::new()
                },
                place
            ),
            FeatureKind::Circle => format!(
                "R {p} mm at ({}, {}){place}",
                fmt_number(f.x, 2),
                fmt_number(f.y, 2)
            ),
            FeatureKind::Extrude => format!("{parent}, {p} mm"),
            FeatureKind::Revolve => format!("{parent}, {p}° about Y"),
            FeatureKind::Hole => format!(
                "D {p} mm on {parent} top face, {}",
                if f.p2 <= 0.0 {
                    "through all".to_string()
                } else {
                    format!("{} mm deep", fmt_number(f.p2, 2))
                }
            ),
            FeatureKind::Foreign => "From SolidCraft. Not in SolidCraft 98.".into(),
            _ => String::new(),
        })
    }
}

pub fn fmt_number(value: Dimension, places: u32) -> String {
    let places = places.min(9);
    let m = libm::pow(10.0, places as Dimension);
    let r = libm::floor(value.abs() * m + 0.5) / m;
    let mut s = format!("{:.*}", places as usize, r);
    if s.contains('.') {
        while s.ends_with('0') {
            s.pop();
        }
        if s.ends_with('.') {
            s.pop();
        }
    }
    if value < 0.0 && r != 0.0 {
        s.insert(0, '-');
    }
    s
}
