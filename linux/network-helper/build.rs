mod build_support;

use std::env;
use std::path::PathBuf;

use libbpf_cargo::SkeletonBuilder;

fn main() {
    let out = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR"));
    let clang = env::var_os("CLANG").unwrap_or_else(|| "clang".into());
    SkeletonBuilder::new()
        .source("bpf/network.bpf.c")
        .clang(PathBuf::from(&clang))
        .clang_args(build_support::kernel_header_args(&clang))
        .build_and_generate(out.join("network.skel.rs"))
        .expect("build Linux network eBPF program");
    println!("cargo:rerun-if-changed=bpf/network.bpf.c");
    println!("cargo:rerun-if-changed=build_support.rs");
    println!("cargo:rerun-if-env-changed=CLANG");
}
