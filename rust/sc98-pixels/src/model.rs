//! Adapter boundary: implement `Part` for the core design, without coupling
//! the drawing crate to file formats, feature storage, or a geometry kernel.
use crate::{framebuffer::Color, Scalar};

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Vec3 {
    pub x: Scalar,
    pub y: Scalar,
    pub z: Scalar,
}
impl Vec3 {
    pub const fn new(x: Scalar, y: Scalar, z: Scalar) -> Self {
        Self { x, y, z }
    }
    pub fn dot(self, b: Self) -> Scalar {
        self.x * b.x + self.y * b.y + self.z * b.z
    }
    pub fn normalized(self) -> Self {
        let l = libm::sqrtf(self.dot(self));
        if l > 0.0 && l.is_finite() {
            Self::new(self.x / l, self.y / l, self.z / l)
        } else {
            Self::default()
        }
    }
    pub fn finite(self) -> bool {
        self.x.is_finite() && self.y.is_finite() && self.z.is_finite()
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FeatureKind {
    Rectangle,
    Circle,
    Extrude,
    Revolve,
    Hole,
    Unsupported,
}
impl FeatureKind {
    pub const fn name(self) -> &'static str {
        match self {
            Self::Rectangle => "Rectangle",
            Self::Circle => "Circle",
            Self::Extrude => "Extrude",
            Self::Revolve => "Revolve",
            Self::Hole => "Hole",
            Self::Unsupported => "Requires SolidCraft 2000",
        }
    }
    pub const fn icon(self) -> &'static str {
        match self {
            Self::Rectangle => "SketchRect",
            Self::Circle => "SketchCircle",
            Self::Extrude => "Extrude",
            Self::Revolve => "Revolve",
            Self::Hole => "Hole",
            Self::Unsupported => "Construction",
        }
    }
}
#[derive(Clone, Copy, Debug)]
pub struct Feature<'a> {
    pub name: &'a str,
    pub kind: FeatureKind,
}
#[derive(Clone, Copy, Debug)]
pub struct Triangle {
    pub vertices: [Vec3; 3],
    /// Outward normal, normalized by the renderer.
    pub normal: Vec3,
    pub color: Color,
    /// Shared by triangles on one face; zero is reserved for background.
    pub face: u16,
}
impl Triangle {
    pub fn finite(&self) -> bool {
        self.normal.finite() && self.vertices.iter().all(|p| p.finite())
    }
}
pub trait Part {
    fn name(&self) -> &str;
    fn features(&self) -> &[Feature<'_>];
    fn triangles(&self) -> &[Triangle];
}

pub const DEMO_FEATURES: [Feature<'static>; 4] = [
    Feature {
        name: "Sketch1",
        kind: FeatureKind::Rectangle,
    },
    Feature {
        name: "Extrude1",
        kind: FeatureKind::Extrude,
    },
    Feature {
        name: "Sketch2",
        kind: FeatureKind::Rectangle,
    },
    Feature {
        name: "Extrude2",
        kind: FeatureKind::Extrude,
    },
];
/// Tiny, independent model for the desktop and board bring-up.
pub struct DemoPart;
impl Part for DemoPart {
    fn name(&self) -> &str {
        "Mounting Plate"
    }
    fn features(&self) -> &[Feature<'_>] {
        &DEMO_FEATURES
    }
    fn triangles(&self) -> &[Triangle] {
        &DEMO_MESH
    }
}
const fn box_mesh(min: Vec3, max: Vec3, face: u16) -> [Triangle; 12] {
    let p = [
        Vec3::new(min.x, min.y, min.z),
        Vec3::new(max.x, min.y, min.z),
        Vec3::new(max.x, max.y, min.z),
        Vec3::new(min.x, max.y, min.z),
        Vec3::new(min.x, min.y, max.z),
        Vec3::new(max.x, min.y, max.z),
        Vec3::new(max.x, max.y, max.z),
        Vec3::new(min.x, max.y, max.z),
    ];
    let ids = [
        [0, 2, 1],
        [0, 3, 2],
        [4, 5, 6],
        [4, 6, 7],
        [0, 1, 5],
        [0, 5, 4],
        [1, 2, 6],
        [1, 6, 5],
        [2, 3, 7],
        [2, 7, 6],
        [3, 0, 4],
        [3, 4, 7],
    ];
    let normals = [
        Vec3::new(0., 0., -1.),
        Vec3::new(0., 0., 1.),
        Vec3::new(0., -1., 0.),
        Vec3::new(1., 0., 0.),
        Vec3::new(0., 1., 0.),
        Vec3::new(-1., 0., 0.),
    ];
    let empty = Triangle {
        vertices: [Vec3::new(0., 0., 0.); 3],
        normal: Vec3::new(0., 0., 0.),
        color: Color::rgb(165, 178, 200),
        face: 1,
    };
    let mut tris = [empty; 12];
    let mut i = 0;
    while i < 12 {
        tris[i] = Triangle {
            vertices: [p[ids[i][0]], p[ids[i][1]], p[ids[i][2]]],
            normal: normals[i / 2],
            color: empty.color,
            face: face + (i / 2) as u16,
        };
        i += 1;
    }
    tris
}
const fn demo_mesh() -> [Triangle; 24] {
    let a = box_mesh(Vec3::new(-40., -25., 0.), Vec3::new(40., 25., 6.), 1);
    let b = box_mesh(Vec3::new(-12., -10., 6.), Vec3::new(12., 10., 23.), 7);
    let mut out = [a[0]; 24];
    let mut i = 0;
    while i < 12 {
        out[i] = a[i];
        out[i + 12] = b[i];
        i += 1;
    }
    out
}
pub const DEMO_MESH: [Triangle; 24] = demo_mesh();
