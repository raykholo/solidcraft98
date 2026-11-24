#![cfg_attr(target_os = "none", no_std)]
#![cfg_attr(target_os = "none", no_main)]

#[cfg(not(target_os = "none"))]
fn main() {
    eprintln!("Select an ESP32 target; see rust/README.md.");
}

#[cfg(target_os = "none")]
mod firmware;
