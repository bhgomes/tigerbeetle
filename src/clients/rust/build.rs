//! Rust Client Build Script

use std::env;
use std::path::PathBuf;

fn main() {
    // println!("cargo:rustc-link-search=/path/to/lib");
    // println!("cargo:rustc-link-lib=tigerbeetle");
    println!("cargo:rerun-if-changed=tb_client.h");
    bindgen::Builder::default()
        .header("tb_client.h")
        .parse_callbacks(Box::new(bindgen::CargoCallbacks))
        .generate()
        .expect("Unable to generate bindings")
        .write_to_file(
            PathBuf::from(
                env::var("OUT_DIR").expect("Unable to find the OUT_DIR environment variable."),
            )
            .join("tb_client.rs"),
        )
        .expect("Couldn't write bindings!");
}
