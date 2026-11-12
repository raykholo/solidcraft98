//! Explicit little-endian encoding; never Rust structure layout.
use crate::{
    model::{Feature, FeatureKind, Part, MAX_FEATURES},
    Error,
};
use alloc::{string::String, vec::Vec};

pub const FILE_VERSION: i16 = 5;
pub const HEADER_BYTES: usize = 72;
pub const RECORD_BYTES: usize = 134;
pub const FILE_BYTES: usize = HEADER_BYTES + MAX_FEATURES * RECORD_BYTES;
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Conversion {
    None,
    Version3,
    Version4,
}
#[derive(Clone, Debug, PartialEq)]
pub struct LoadedPart {
    pub part: Part,
    pub conversion: Conversion,
}

pub(crate) struct Reader<'a> {
    bytes: &'a [u8],
    at: usize,
}
impl<'a> Reader<'a> {
    pub(crate) fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, at: 0 }
    }
    pub(crate) fn take(&mut self, n: usize) -> Result<&'a [u8], Error> {
        let end = self.at.checked_add(n).ok_or(Error::Truncated)?;
        let b = self.bytes.get(self.at..end).ok_or(Error::Truncated)?;
        self.at = end;
        Ok(b)
    }
    pub(crate) fn short(&mut self) -> Result<i16, Error> {
        let b = self.take(2)?;
        Ok(i16::from_le_bytes([b[0], b[1]]))
    }
    pub(crate) fn double(&mut self) -> Result<f64, Error> {
        let mut b = [0; 8];
        b.copy_from_slice(self.take(8)?);
        Ok(f64::from_le_bytes(b))
    }
    fn text(&mut self, n: usize) -> Result<String, Error> {
        let b = self.take(n)?;
        let end = b
            .iter()
            .rposition(|&c| c != 0 && c != b' ')
            .map_or(0, |n| n + 1);
        Ok(b[..end].iter().map(|&b| char::from(b)).collect())
    }
}
fn text(out: &mut Vec<u8>, s: &str, n: usize) {
    let start = out.len();
    out.extend(
        s.chars()
            .take(n)
            .map(|c| u8::try_from(c as u32).unwrap_or(b'?')),
    );
    out.resize(start + n, if s.is_empty() { 0 } else { b' ' });
}
impl Part {
    /// Load versions 3–5; trailing Turbo preview bytes are ignored, as in FreeBASIC.
    pub fn from_sc98(bytes: &[u8]) -> Result<LoadedPart, Error> {
        let mut r = Reader::new(bytes);
        if r.take(4)? != b"SC98" {
            return Err(Error::NotAPart);
        }
        let version = r.short()?;
        if version > FILE_VERSION {
            return Err(Error::TooNew);
        }
        if version < 3 {
            return Err(Error::TooOld);
        }
        let mut part = Part::new(r.text(64)?);
        let count = r.short()?;
        part.count = if (0..=64).contains(&count) {
            count as usize
        } else {
            0
        };
        for i in 0..MAX_FEATURES {
            let mut f = Feature {
                kind: FeatureKind::from_code(r.short()?),
                name: r.text(24)?,
                x: r.double()?,
                y: r.double()?,
                z: r.double()?,
                p1: r.double()?,
                p2: r.double()?,
                reference: r.short()?,
                suppressed: r.short()?,
                ..Feature::default()
            };
            if version >= 4 {
                f.p3 = r.double()?;
            }
            if version >= 5 {
                f.info = r.text(32)?;
            }
            if version >= 4 {
                r.take(24)?;
            }
            if !f.finite() {
                return Err(Error::InvalidNumber);
            }
            if i >= part.count {
                f.kind = FeatureKind::None;
            }
            part.records[i] = f;
        }
        Ok(LoadedPart {
            part,
            conversion: match version {
                3 => Conversion::Version3,
                4 => Conversion::Version4,
                _ => Conversion::None,
            },
        })
    }
    /// Save in version 5, including all 64 records and zeroed reserved doubles.
    pub fn to_sc98(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(FILE_BYTES);
        out.extend(b"SC98");
        out.extend(FILE_VERSION.to_le_bytes());
        text(&mut out, &self.title, 64);
        out.extend((self.count as i16).to_le_bytes());
        for f in &self.records {
            out.extend(f.kind.code().to_le_bytes());
            text(&mut out, &f.name, 24);
            for n in [f.x, f.y, f.z, f.p1, f.p2] {
                out.extend(n.to_le_bytes());
            }
            out.extend(f.reference.to_le_bytes());
            out.extend(f.suppressed.to_le_bytes());
            out.extend(f.p3.to_le_bytes());
            text(&mut out, &f.info, 32);
            out.extend([0; 24]);
        }
        out
    }
}
