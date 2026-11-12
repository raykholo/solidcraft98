fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("none") {
        println!("cargo:rustc-link-arg=-Tlinkall.x");
    }
}
