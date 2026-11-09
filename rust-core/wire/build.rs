//! Derives the helper build ID from `remote-helper/COMPATIBILITY` and records the processtree
//! revision from the workspace lockfile.
use std::path::Path;

fn main() {
    let manifest = Path::new(env!("CARGO_MANIFEST_DIR"));
    let compatibility = manifest.join("../remote-helper/COMPATIBILITY");
    println!("cargo:rerun-if-changed={}", compatibility.display());
    let text = std::fs::read_to_string(&compatibility)
        .expect("remote-helper/COMPATIBILITY must be readable");
    let version: u64 = text
        .lines()
        .filter_map(|line| line.trim().strip_prefix("version "))
        .next()
        .and_then(|value| value.trim().parse().ok())
        .expect("remote-helper/COMPATIBILITY must declare a version");
    println!("cargo:rustc-env=PROCESSLAMA_REMOTE_HELPER_COMPATIBILITY={version}");
    println!("cargo:rustc-env=PROCESSLAMA_REMOTE_HELPER_ID={version:0>40}");

    let lockfile = manifest.join("../Cargo.lock");
    println!("cargo:rerun-if-changed={}", lockfile.display());
    let lock = std::fs::read_to_string(&lockfile).unwrap_or_default();
    let revision = lock
        .split("[[package]]")
        .find(|package| package.contains("name = \"processtree\""))
        .and_then(|package| package.lines().find(|line| line.starts_with("source = ")))
        .and_then(|source| source.rsplit('#').next())
        .map(|revision| revision.trim_end_matches('"').to_owned())
        .filter(|revision| revision.len() <= 40 && revision.bytes().all(|b| b.is_ascii_hexdigit()))
        .unwrap_or_default();
    println!("cargo:rustc-env=PROCESSLAMA_PROCESSTREE_REVISION={revision}");
}
