use sc98_core::{
    expr::{evaluate, ExprError},
    file::{Conversion, FILE_BYTES},
    kernel::profile_contains,
    mesh::{HOLE_COLOUR, MESH_SEGS, SOLID_COLOUR},
    model::fmt_number,
    Error, Feature, FeatureKind as K, Part,
};
use std::{collections::BTreeMap, fs, path::PathBuf};
fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}
fn plate() -> Part {
    Part::from_sc98(&fs::read(root().join("samples/Mounting Plate.sc98")).unwrap())
        .unwrap()
        .part
}
fn box_part() -> Part {
    let mut p = Part::new("Box");
    p.add_feature(Feature {
        kind: K::Rectangle,
        x: -2.0,
        y: -3.0,
        p1: 4.0,
        p2: 6.0,
        ..Feature::default()
    })
    .unwrap();
    p.add_feature(Feature {
        kind: K::Extrude,
        reference: 1,
        p1: 8.0,
        ..Feature::default()
    })
    .unwrap();
    p
}
fn volume(m: &sc98_core::Mesh) -> f64 {
    m.triangles()
        .iter()
        .map(|t| {
            let [a, b, c] = t.vertices.map(|v| v.map(f64::from));
            (a[0] * (b[1] * c[2] - b[2] * c[1]) - b[0] * (a[1] * c[2] - a[2] * c[1])
                + c[0] * (a[1] * b[2] - a[2] * b[1]))
                / 6.0
        })
        .sum()
}
fn assert_closed(m: &sc98_core::Mesh) {
    // Compare f32 endpoints: the public mesh must have two opposite uses of every edge.
    let key = |p: [f32; 3]| p.map(|v| if v == 0.0 { 0 } else { v.to_bits() });
    let mut edges = BTreeMap::new();
    for t in m.triangles() {
        for k in 0..3 {
            let a = key(t.vertices[k]);
            let b = key(t.vertices[(k + 1) % 3]);
            if a != b {
                let (pair, dir) = if a < b { ((a, b), 1) } else { ((b, a), -1) };
                let e = edges.entry(pair).or_insert((0, 0));
                e.0 += 1;
                e.1 += dir;
            }
        }
    }
    for (edge, (count, dir)) in edges {
        assert_eq!((count, dir), (2, 0), "edge {edge:?}");
    }
}
#[test]
fn all_native_fixtures_open_rebuild_and_resave_byte_identically() {
    for dir in ["samples", "freebasic/tests", "delphi/tests"] {
        for file in fs::read_dir(root().join(dir)).unwrap() {
            let path = file.unwrap().path();
            if path.extension().is_some_and(|s| s == "sc98") {
                let bytes = fs::read(&path).unwrap();
                let load = Part::from_sc98(&bytes).unwrap();
                assert_eq!(load.conversion, Conversion::None);
                let d = load.part;
                assert_eq!(d.title, "Mounting Plate");
                assert_eq!(d.features().len(), 9);
                assert_eq!(d.to_sc98(), bytes, "{}", path.display());
                let built = d.rebuild(MESH_SEGS).unwrap();
                assert!(built.invalid_features.is_empty());
                assert_eq!(built.edges.len(), 560);
                assert_eq!(built.mesh.triangles().len(), 1952);
                let mut hash = 0xcbf29ce484222325u64;
                for triangle in built.mesh.triangles() {
                    for byte in triangle
                        .vertices
                        .iter()
                        .flatten()
                        .flat_map(|n| n.to_le_bytes())
                        .chain((triangle.feature as u32).to_le_bytes())
                    {
                        hash = (hash ^ u64::from(byte)).wrapping_mul(0x100000001b3);
                    }
                }
                assert_eq!(
                    hash,
                    include_str!("fixtures/plate.mesh-fnv")
                        .trim()
                        .parse::<u64>()
                        .unwrap()
                );
                assert!(built.mesh.warnings.is_empty());
                assert_closed(&built.mesh);
                assert!(volume(&built.mesh) > 0.0);
                assert_eq!(
                    built.mesh.to_stl(&d.title).unwrap(),
                    include_bytes!("fixtures/plate.stl")
                );
                let shaded = d.mesh(32).unwrap();
                assert!(shaded.warnings.is_empty());
                assert_closed(&shaded);
            }
        }
    }
}
#[test]
fn expression_checks_from_freebasic_core_test() {
    for (s, n) in [
        ("40/2+5", 25.0),
        ("(10+2)*3", 36.0),
        ("-8", -8.0),
        (" 2 + 3 * 4 ", 14.0),
        ("--8", 8.0),
        ("1.2.3", 1.2),
        (".", 0.0),
    ] {
        assert_eq!(evaluate(s), Ok(n), "{s}");
    }
    for s in ["20mm", "", "+2", "1e3", "(2", "2)", "2\t+3"] {
        assert_eq!(evaluate(s), Err(ExprError::TypeMismatch), "{s}");
    }
    assert_eq!(evaluate("40/0"), Err(ExprError::DivisionByZero));
    assert_eq!(ExprError::DivisionByZero.code(), 11);
    assert_eq!(ExprError::TypeMismatch.code(), 13);
    assert_eq!(evaluate(&"(".repeat(100)), Err(ExprError::TooDeep));
    for (n, s) in [
        (12.5, "12.5"),
        (3.0, "3"),
        (-0.001, "0"),
        (-12.345, "-12.35"),
    ] {
        assert_eq!(fmt_number(n, 2), s);
    }
}
#[test]
fn old_versions_convert_like_the_other_editions() {
    let p = plate();
    let bytes = p.to_sc98();
    for (version, conversion) in [(3i16, Conversion::Version3), (4, Conversion::Version4)] {
        let mut old = bytes[..72].to_vec();
        old[4..6].copy_from_slice(&version.to_le_bytes());
        for f in bytes[72..].chunks_exact(134) {
            old.extend_from_slice(&f[..70]);
            if version == 4 {
                old.extend_from_slice(&f[70..78]);
                old.extend_from_slice(&f[110..134]);
            }
        }
        let load = Part::from_sc98(&old).unwrap();
        assert_eq!(load.conversion, conversion);
        assert_eq!(load.part.features().len(), 9);
        let mut expected = bytes.clone();
        if version == 3 {
            for f in expected[72..].chunks_exact_mut(134) {
                f[70..78].fill(0);
            }
        }
        assert_eq!(load.part.to_sc98(), expected);
        assert!(!load.part.rebuild(64).unwrap().mesh.triangles().is_empty());
    }
}
#[test]
fn file_boundaries_and_fixed_fields() {
    let bytes = plate().to_sc98();
    assert_eq!(bytes.len(), FILE_BYTES);
    for end in [0, 1, 3, 5, 71, 72, 100, FILE_BYTES - 1] {
        assert!(Part::from_sc98(&bytes[..end]).is_err());
    }
    let mut bad = bytes.clone();
    bad[0] = 0;
    assert_eq!(Part::from_sc98(&bad).unwrap_err(), Error::NotAPart);
    bad = bytes.clone();
    bad[4..6].copy_from_slice(&6i16.to_le_bytes());
    assert_eq!(Part::from_sc98(&bad).unwrap_err(), Error::TooNew);
    bad[4..6].copy_from_slice(&2i16.to_le_bytes());
    assert_eq!(Part::from_sc98(&bad).unwrap_err(), Error::TooOld);
    bad = bytes.clone();
    bad[70..72].copy_from_slice(&65i16.to_le_bytes());
    assert!(Part::from_sc98(&bad).unwrap().part.features().is_empty());
    bad = bytes.clone();
    bad[98..106].copy_from_slice(&f64::NAN.to_le_bytes());
    assert_eq!(Part::from_sc98(&bad).unwrap_err(), Error::InvalidNumber);
    let mut preview = bytes.clone();
    preview.extend([1, 2, 3, 4]);
    assert_eq!(Part::from_sc98(&preview).unwrap().part.to_sc98(), bytes);
    let mut p = Part::new("Café");
    p.add_named_feature(Feature {
        kind: K::Foreign,
        name: "é".into(),
        info: "fillet".into(),
        ..Feature::default()
    })
    .unwrap();
    let b = p.to_sc98();
    assert_eq!(&b[6..10], b"Caf\xe9");
    assert_eq!(b[74], 0xe9);
    assert_eq!(Part::from_sc98(&b).unwrap().part, p);
    // Noncanonical padding and reserved doubles are normalized, matching SaveDesign.
    let mut b = Part::new("").to_sc98();
    b[6..70].fill(b' ');
    b[72 + 110..72 + 134].fill(7);
    assert_eq!(
        Part::from_sc98(&b).unwrap().part.to_sc98(),
        Part::new("").to_sc98()
    );
}
#[test]
fn tree_edit_delete_dependents_and_renumber() {
    let mut p = plate();
    assert_eq!(p.last_solid(), Some(8));
    assert_eq!(p.last_free_sketch(), None);
    assert_eq!(p.dependents(2).unwrap(), vec![2, 3, 4, 5, 6, 7, 8, 9]);
    assert_eq!(p.sketch_z(7), Some(10.0));
    assert_eq!(p.hole_span(9), Some((25.0, 0.0)));
    let mut f = p.feature(2).unwrap().clone();
    f.p1 = 8.0;
    p.edit_feature(2, f).unwrap();
    assert_eq!(p.sketch_z(7), Some(8.0));
    assert_eq!(p.hole_span(9), Some((23.0, 0.0)));
    assert_closed(&p.mesh(64).unwrap());
    assert_eq!(p.delete_with_dependents(3).unwrap(), vec![3]);
    assert_eq!(p.feature(7).unwrap().reference, 6);
    assert_eq!(p.feature(8).unwrap().reference, 7);
    assert!(p.ref_ok(8));
    assert_eq!(p.feature(3).unwrap().name, "Hole2");
    assert_eq!(
        p.delete_with_dependents(2).unwrap(),
        vec![2, 3, 4, 5, 6, 7, 8]
    );
    assert_eq!(p.features().len(), 1);
    assert_eq!(p.last_free_sketch(), Some(1));
    assert!(p.mesh(64).unwrap().triangles().is_empty());
    assert_eq!(p.delete_with_dependents(0), Err(Error::InvalidFeature));
    for _ in 1..64 {
        p.add_feature(Feature::default()).unwrap();
    }
    assert_eq!(p.add_feature(Feature::default()), Err(Error::Full));
}
#[test]
fn box_stl_normals_colours_and_translation() {
    let p = box_part();
    let m = p.mesh(64).unwrap();
    assert_eq!(m.triangles().len(), 12);
    assert_closed(&m);
    assert_eq!(volume(&m), 192.0);
    for t in m.triangles() {
        assert_eq!(t.colour, SOLID_COLOUR);
        assert_eq!(t.feature, 2);
        let length = t.normal.iter().map(|n| n * n).sum::<f32>();
        assert!((length - 1.0).abs() < 1e-6);
    }
    let bytes = m.to_stl(&p.title).unwrap();
    assert_eq!(&bytes[..35], b"Binary STL from SolidCraft 98: Box,");
    assert_eq!(bytes.len(), 84 + 50 * 12);
    assert_eq!(u32::from_le_bytes(bytes[80..84].try_into().unwrap()), 12);
    for record in bytes[84..].chunks_exact(50) {
        for n in record[12..48].chunks_exact(4) {
            assert!(f32::from_le_bytes(n.try_into().unwrap()) >= 0.0);
        }
        assert_eq!(&record[48..], [0, 0]);
    }
    let empty = Part::new("").mesh(64).unwrap();
    assert_eq!(empty.to_stl(""), Err(Error::EmptyMesh));
    assert_eq!(p.mesh(0).unwrap_err(), Error::InvalidSegments);
    assert_eq!(p.mesh(4097).unwrap_err(), Error::InvalidSegments);
}
#[test]
fn blind_holes_negative_extrusion_suppression_and_invalid_refs() {
    let mut p = box_part();
    let hole = Feature {
        kind: K::Hole,
        reference: 2,
        p1: 2.0,
        p2: 3.0,
        ..Feature::default()
    };
    p.add_feature(hole).unwrap();
    let m = p.mesh(64).unwrap();
    assert!(m.warnings.is_empty());
    assert_closed(&m);
    assert!(m
        .triangles()
        .iter()
        .any(|t| t.feature == 3 && t.colour == HOLE_COLOUR));
    assert!(
        (volume(&m) - (192.0 - 3.0 * 64.0 * libm::sin(2.0 * std::f64::consts::PI / 64.0) / 2.0))
            .abs()
            < 1e-4
    );
    let mut f = p.feature(3).unwrap().clone();
    f.suppressed = 1;
    p.edit_feature(3, f).unwrap();
    assert_eq!(p.mesh(64).unwrap().triangles().len(), 12);
    let mut f = p.feature(2).unwrap().clone();
    f.p1 = -8.0;
    p.edit_feature(2, f).unwrap();
    assert_closed(&p.mesh(64).unwrap());
    assert_eq!(volume(&p.mesh(64).unwrap()), 192.0);
    let mut f = p.feature(2).unwrap().clone();
    f.reference = 64;
    p.edit_feature(2, f).unwrap();
    assert!(!p.ref_ok(2));
    assert!(p.rebuild(32).unwrap().invalid_features.contains(&2));
    let mut f = Feature {
        kind: K::Rectangle,
        p1: 10.0,
        p2: 10.0,
        p3: 2.0,
        ..Feature::default()
    };
    assert!(profile_contains(&f, 5.0, 5.0, 4.0));
    assert!(!profile_contains(&f, 0.0, 0.0, 1.0));
    f.kind = K::Circle;
    f.p1 = 10.0;
    assert!(profile_contains(&f, 0.0, 0.0, 10.0));
    assert!(!profile_contains(&f, 1.0, 0.0, 10.0));
}
#[test]
fn overlapping_holes_report_the_reference_meshing_error() {
    let mut p = box_part();
    for x in [0.0, 0.1] {
        p.add_feature(Feature {
            kind: K::Hole,
            reference: 2,
            x,
            p1: 2.0,
            ..Feature::default()
        })
        .unwrap();
    }
    let m = p.mesh(64).unwrap();
    assert!(m
        .warnings
        .contains("its holes are too close together to cap"));
    assert!(m.triangles().is_empty());
}
#[test]
fn full_and_partial_revolves_on_the_axis_are_closed_and_outward() {
    for (x, angle) in [(0.0, 360.0), (2.0, 270.0), (2.0, -270.0)] {
        let mut p = Part::new("Revolve");
        p.add_feature(Feature {
            kind: K::Rectangle,
            x,
            p1: 2.0,
            p2: 3.0,
            ..Feature::default()
        })
        .unwrap();
        p.add_feature(Feature {
            kind: K::Revolve,
            reference: 1,
            p1: angle,
            ..Feature::default()
        })
        .unwrap();
        let m = p.mesh(64).unwrap();
        assert_closed(&m);
        assert!(volume(&m) > 0.0);
        assert!(m.warnings.is_empty());
        assert!(!p.regenerate().unwrap().is_empty());
    }
}

#[test]
fn feature_descriptions_match_the_reference() {
    let p = plate();
    let descriptions = [
        "80 x 50 mm at (-40, -25), R6 corners",
        "Sketch1, 10 mm",
        "D 5 mm on Extrude1 top face, through all",
        "D 5 mm on Extrude1 top face, through all",
        "D 5 mm on Extrude1 top face, through all",
        "D 5 mm on Extrude1 top face, through all",
        "R 10 mm at (0, 0), on Extrude1",
        "Sketch2, 15 mm",
        "D 10 mm on Extrude2 top face, through all",
    ];
    for (i, expected) in descriptions.iter().enumerate() {
        assert_eq!(p.describe(i + 1).unwrap(), *expected);
    }
    assert_eq!(p.describe(0), Err(Error::InvalidFeature));
}
