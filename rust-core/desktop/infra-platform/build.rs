fn main() {
    println!("cargo:rerun-if-changed=src/macos_bridge.m");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") {
        return;
    }
    cc::Build::new()
        .file("src/macos_bridge.m")
        .flag("-fobjc-arc")
        .flag("-fmodules")
        .compile("processlama-macos-bridge");
    println!("cargo:rustc-link-lib=framework=AppKit");
    println!("cargo:rustc-link-lib=framework=Foundation");
}
