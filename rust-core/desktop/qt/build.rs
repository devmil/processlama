//! On macOS, Qt's frameworks are linked by @rpath. This crate is a library,
//! so the path only reaches its own test binary: `cargo test` on macOS needs
//! Qt's library folder there. The app sets its own rpaths (app/build.rs).

use std::env;
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-env-changed=QMAKE");
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") {
        return;
    }
    if let Some(libs) = qt_query("QT_INSTALL_LIBS") {
        println!("cargo:rustc-link-arg=-Wl,-rpath,{libs}");
    }
}

fn qt_query(key: &str) -> Option<String> {
    let configured = env::var("QMAKE").ok();
    for qmake in configured
        .iter()
        .map(String::as_str)
        .chain(["qmake6", "qmake"])
    {
        if let Ok(output) = Command::new(qmake).args(["-query", key]).output()
            && output.status.success()
        {
            return Some(String::from_utf8_lossy(&output.stdout).trim().to_owned());
        }
    }
    None
}
