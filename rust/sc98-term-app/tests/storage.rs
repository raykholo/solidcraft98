use sc98_app::Storage;
use sc98_term_app::Directory;
#[test]
fn current_directory_storage_round_trip() {
    let dir = std::env::temp_dir().join(format!("sc98-host-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let mut storage = Directory::new(&dir);
    storage.save("part.sc98", b"part").unwrap();
    assert_eq!(storage.load("part.sc98").unwrap(), b"part");
    assert!(storage.save("../outside", b"no").is_err());
    assert!(storage.load("/etc/passwd").is_err());
    std::fs::remove_dir_all(dir).unwrap();
}
