//! Parts, feature history, compatible .sc98 files, meshes and binary STL.
//!
//! The pixel boundary uses f32 vertices and face normals; file dimensions retain
//! double precision. See the crate README for feature parameters and import.
//!
//! ```
//! use sc98_core::{Error, Feature, FeatureKind, Part};
//!
//! let mut part = Part::new("Block");
//! let sketch = part.add_feature(Feature {
//!     kind: FeatureKind::Rectangle, p1: 20.0, p2: 10.0,
//!     ..Feature::default()
//! })?;
//! part.add_feature(Feature {
//!     kind: FeatureKind::Extrude, reference: sketch as i16, p1: 5.0,
//!     ..Feature::default()
//! })?;
//! let rebuilt = part.rebuild(32)?;
//! assert_eq!(rebuilt.mesh.triangles().len(), 12);
//! let saved = part.to_sc98();
//! assert_eq!(Part::from_sc98(&saved)?.part, part);
//! let stl = part.mesh(64)?.to_stl(&part.title)?;
//! assert_eq!(stl.len(), 84 + 12 * 50);
//! # Ok::<(), Error>(())
//! ```
#![no_std]
#![forbid(unsafe_code)]

extern crate alloc;

pub mod expr;
pub mod file;
#[cfg(feature = "import")]
pub mod import;
pub mod kernel;
pub mod mesh;
pub mod model;
pub mod stl;

pub use kernel::{Edge, Rebuild};
pub use mesh::{Mesh, Triangle};
pub use model::{Feature, FeatureId, FeatureKind, Part, MAX_FEATURES};

/// Coordinates used by the pixel layer. Change this alias for a future fixed-point renderer.
pub type Scalar = f32;
/// On-disk dimensions and reference geometry retain the editions' IEEE doubles.
pub type Dimension = f64;
pub type Vec3 = [Scalar; 3];
pub type Colour = u32;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Error {
    Full,
    InvalidFeature,
    InvalidNumber,
    NotAPart,
    TooNew,
    TooOld,
    Truncated,
    InvalidSegments,
    EmptyMesh,
    MeshTooLarge,
    Import(alloc::string::String),
}

impl core::fmt::Display for Error {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::Full => f.write_str("This part already has 64 features."),
            Self::InvalidFeature => f.write_str("That feature is not in this part."),
            Self::InvalidNumber => f.write_str("Type mismatch"),
            Self::NotAPart => f.write_str("This is not a SolidCraft 98 part."),
            Self::TooNew => f.write_str("Please upgrade to SolidCraft 98 Second Edition."),
            Self::TooOld => f.write_str("Versions before 3 are not supported. They never were."),
            Self::Truncated => f.write_str("Can't read the whole part."),
            Self::InvalidSegments => f.write_str("Circle segments must be between 4 and 4096."),
            Self::EmptyMesh => f.write_str("There is nothing to export."),
            Self::MeshTooLarge => f.write_str("This part is too large to mesh."),
            Self::Import(s) => f.write_str(s),
        }
    }
}

impl core::error::Error for Error {}
