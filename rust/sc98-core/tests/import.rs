#![cfg(feature = "import")]
use sc98_core::{import::open, mesh::MESH_SEGS, FeatureKind as K, Part};
use std::{fs, path::PathBuf};
fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}
#[test]
fn every_solidcraft_fixture_matches_freebasic_save_and_stl() {
    for dir in ["samples", "freebasic/tests", "delphi/tests"] {
        for (name, stem, count, edges, tris, foreign) in [
            ("Plate with holes", "import-plate", 10, 560, 1952, 1),
            ("Revolved parts", "import-revolved", 4, 466, 6780, 0),
            ("Flange", "import-flange", 8, 444, 1552, 1),
        ] {
            let path = root().join(dir).join(format!("{name}.solidcraft"));
            let bytes = fs::read(&path).unwrap();
            let imported = open(&bytes, name).unwrap();
            let part = imported.part;
            assert!(!imported.full);
            assert_eq!(part.features().len(), count, "{name}");
            assert_eq!(imported.notices.len(), foreign, "{name}");
            let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures");
            assert_eq!(
                part.to_sc98(),
                fs::read(fixture.join(format!("{stem}.sc98"))).unwrap(),
                "{name}"
            );
            let built = part.rebuild(MESH_SEGS).unwrap();
            let expected_hash: u64 = fs::read_to_string(fixture.join(format!("{stem}.mesh-fnv")))
                .unwrap()
                .trim()
                .parse()
                .unwrap();
            assert_eq!(
                mesh_hash(&built.mesh),
                expected_hash,
                "{name}: triangles and feature owners"
            );
            assert!(built.invalid_features.is_empty());
            assert!(built.mesh.warnings.is_empty());
            assert_eq!(built.edges.len(), edges, "{name}");
            assert_eq!(built.mesh.triangles().len(), tris, "{name}");
            let actual = built.mesh.to_stl(&part.title).unwrap();
            let expected = fs::read(fixture.join(format!("{stem}.stl"))).unwrap();
            // A concise failure identifies the first differing float/triangle.
            let mismatch = actual.iter().zip(&expected).position(|(a, b)| a != b);
            assert_eq!(mismatch, None, "{name}: first mismatched STL byte");
            assert_eq!(actual.len(), expected.len());
            let saved = part.to_sc98();
            assert_eq!(Part::from_sc98(&saved).unwrap().part.to_sc98(), saved);
        }
    }
}
#[test]
fn plain_json_units_parameters_unused_sketches_and_foreign_features() {
    let bytes=br#"{"format":"solidcraft/30","name":"","params":[{"name":"width","expr":"2 cm"},{"name":"r","expr":"width/4"}],"features":[{"id":1,"name":"Circle","type":"sketch","plane":{"type":"origin","name":"XY","offset":"1 in"},"sketch":{"points":[{"pos":[10,0]}],"curves":[{"type":"circle","c":0,"r":5}]}},{"id":2,"type":"extrude","name":"Body","sketch":1,"profiles":{"type":"all"},"extent":{"distance":"r","direction":"symmetric"}},{"id":3,"type":"fillet","name":"Fillet1"},{"id":4,"type":"sketch","name":"Unused","plane":{"type":"origin","name":"XY"},"sketch":{"points":[{"pos":[0,0]}],"curves":[{"type":"circle","c":0,"r":1}]}}]}"#;
    let i = open(bytes, "Untitled").unwrap();
    assert_eq!(i.part.title, "Untitled");
    assert_eq!(i.part.features().len(), 4);
    assert_eq!(i.part.feature(1).unwrap().z, 22.9);
    assert_eq!(i.part.feature(2).unwrap().p1, 5.0);
    assert_eq!(i.part.feature(3).unwrap().kind, K::Foreign);
    assert_eq!(i.part.feature(4).unwrap().name, "Unused");
    assert_eq!(i.notices[0].kind, "Fillet");
}
#[test]
fn unsupported_operations_are_atomic_and_retained_in_the_timeline() {
    for unsupported in [
        r#""taper":0,"profiles":{"type":"all"}"#,
        r#""profiles":{"type":"some"}"#,
    ] {
        let json = format!(
            r#"{{"format":"solidcraft/30","features":[{{"id":1,"type":"sketch","plane":{{"type":"origin","name":"XY"}},"sketch":{{"points":[{{"pos":[0,0]}}],"curves":[{{"type":"circle","c":0,"r":2}}]}}}},{{"type":"extrude","sketch":1,{unsupported},"extent":{{"distance":5}}}}]}}"#
        );
        let i = open(json.as_bytes(), "").unwrap();
        assert_eq!(i.notices.len(), 1);
        assert_eq!(i.part.features().len(), 2);
        assert_eq!(i.part.feature(1).unwrap().kind, K::Foreign);
        assert_eq!(i.part.feature(2).unwrap().kind, K::Circle);
        assert!(i.part.mesh(64).unwrap().triangles().is_empty());
    }
}
#[test]
fn full_history_reports_overflow() {
    let features = vec![r#"{"type":"fillet","name":"Fillet"}"#; 70].join(",");
    let json = format!(r#"{{"format":"solidcraft/30","features":[{features}]}}"#);
    let i = open(json.as_bytes(), "").unwrap();
    assert_eq!(i.part.features().len(), 64);
    assert!(i.full);
    assert_eq!(i.notices.len(), 70);
}
#[test]
fn malformed_and_damaged_imports_return_errors() {
    for bytes in [
        b"".as_slice(),
        b"{",
        b"{}",
        b"PK\x03\x04",
        b"{\"features\":[],\"format\":\"other/1\"}",
    ] {
        assert!(open(bytes, "").is_err());
    }
    let bytes = fs::read(root().join("samples/Flange.solidcraft")).unwrap();
    for end in [4, 30, bytes.len() / 2, bytes.len() - 20] {
        assert!(open(&bytes[..end], "").is_err());
    }
    let mut bad = bytes;
    let name = bad
        .windows(13)
        .rposition(|w| w == b"document.json")
        .unwrap();
    let directory = name - 46;
    bad[directory + 16] ^= 0x80; // document.json CRC in its directory entry
    assert!(open(&bad, "").is_err());
    let json=br#"{"format":"solidcraft/30","params":[{"name":"a","expr":"a"}],"features":[{"id":1,"type":"sketch","plane":{"type":"origin","name":"XY","offset":"a"}}]}"#;
    assert!(open(json, "").is_ok());
}

fn mesh_hash(mesh: &sc98_core::Mesh) -> u64 {
    let mut hash = 0xcbf29ce484222325u64;
    for triangle in mesh.triangles() {
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
    hash
}
