use std::ffi::{OsStr, OsString};
use std::path::PathBuf;
use std::process::{Command, Stdio};

fn include_search_paths(output: &str) -> Vec<PathBuf> {
    let mut searching = false;
    let mut paths = Vec::new();
    for line in output.lines().map(str::trim) {
        if line == "#include <...> search starts here:" {
            searching = true;
        } else if line == "End of search list." {
            break;
        } else if searching && !line.is_empty() {
            paths.push(PathBuf::from(line));
        }
    }
    paths
}

/// BPF's target triple omits the native multiarch include directory on Debian
/// and Ubuntu. Ask the same Clang driver for its native search path, then add
/// only directories that contain the Linux architecture's UAPI headers.
pub fn kernel_header_args(clang: &OsStr) -> Vec<OsString> {
    let output = Command::new(clang)
        .args(["-E", "-x", "c", "-v", "-"])
        .stdin(Stdio::null())
        .output()
        .expect("query Clang's native header search path");
    assert!(output.status.success(), "Clang native header query failed");
    let paths = include_search_paths(&String::from_utf8_lossy(&output.stderr));
    let mut args = Vec::new();
    for path in paths {
        if path.join("asm/types.h").is_file() {
            args.push(OsString::from("-idirafter"));
            args.push(path.into_os_string());
        }
    }
    assert!(
        !args.is_empty(),
        "Clang cannot find asm/types.h; install the native Linux UAPI development headers"
    );
    args
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn native_multiarch_paths_are_preserved_without_architecture_guesses() {
        for architecture in ["x86_64", "aarch64"] {
            let directory = format!("/sysroot/usr/include/{architecture}-linux-gnu");
            let output = format!(
                "clang version 18\nignoring nonexistent directory\n#include \"...\" search starts here:\n#include <...> search starts here:\n /usr/lib/clang/18/include\n {directory}\n /sysroot/usr/include\nEnd of search list.\ncompiler diagnostics\n"
            );
            assert_eq!(
                include_search_paths(&output),
                vec![
                    PathBuf::from("/usr/lib/clang/18/include"),
                    PathBuf::from(directory),
                    PathBuf::from("/sysroot/usr/include"),
                ]
            );
        }
    }

    #[test]
    fn missing_search_section_does_not_treat_diagnostics_as_paths() {
        assert!(include_search_paths("clang: error: no native target\n").is_empty());
    }
}
