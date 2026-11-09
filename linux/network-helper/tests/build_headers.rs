#[path = "../build_support.rs"]
mod build_support;

#[test]
fn selected_clang_finds_real_linux_uapi_headers() {
    let clang = std::env::var_os("CLANG").unwrap_or_else(|| "clang".into());
    let args = build_support::kernel_header_args(&clang);
    assert!(args.chunks_exact(2).all(|pair| {
        pair[0] == "-idirafter" && std::path::Path::new(&pair[1]).join("asm/types.h").is_file()
    }));
}
