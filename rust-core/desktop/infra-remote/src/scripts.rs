//! Fixed POSIX scripts run on a remote host through `ssh`. Their only
//! variable parts are validated build IDs and digests; no alias, path or
//! other user input is ever part of a script.

use processlama_wire::contract::{
    BOOTSTRAP_PREFIX, CACHE_ROOT, HELPER_BYTES, HELPER_EXECUTABLE, INSTALL_PREFIX, INSTALL_ROOT, Target,
};

pub fn is_valid_build_id(value: &str) -> bool {
    processlama_wire::is_build_id(value)
}

pub fn is_valid_sha256(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

/// `case` arms mapping `uname -s`/`uname -m` to a helper target; anything
/// else, including a 32-bit userland, is unsupported.
fn target_case(unsupported: &str) -> String {
    let mut arms = String::new();
    for target in Target::ALL {
        let mut unames = vec![target.uname().to_owned()];
        if target == Target::LinuxArm64 {
            unames.push("Linux/arm64".to_owned());
        }
        arms.push_str(&format!("{}) t={}/{};; ", unames.join("|"), target.os(), target.arch()));
    }
    format!(
        "case \"$(uname -s)/$(uname -m)\" in {arms}*) {unsupported};; esac; \
         [ \"$(getconf LONG_BIT 2>/dev/null)\" = 64 ] || {{ {unsupported}; }}"
    )
}

/// Prints `<prefix> 1 start` and `exec`s the installed helper, or prints
/// `<prefix> 1 missing <os>/<arch>` or `... 1 unsupported`.
pub fn bootstrap(build_id: &str) -> Option<String> {
    if !is_valid_build_id(build_id) {
        return None;
    }
    let prefix = BOOTSTRAP_PREFIX;
    let unsupported = format!("printf '{prefix} 1 unsupported\\n'; exit 0");
    Some(
        [
            target_case(&unsupported),
            "case \"$t\" in macos/*) PATH=\"/usr/bin:/bin:/usr/sbin:/sbin:$PATH\"; export PATH;; esac".to_owned(),
            format!("h=\"$HOME/{INSTALL_ROOT}/{build_id}/{HELPER_EXECUTABLE}\""),
            format!(
                "if [ -f \"$h\" ] && [ -x \"$h\" ] && [ ! -L \"$h\" ]; then printf '{prefix} 1 start\\n'; exec \"$h\" --stdio; fi"
            ),
            format!("printf '{prefix} 1 missing %s\\n' \"$t\""),
            "exit 0".to_owned(),
        ]
        .join("; "),
    )
}

const INSTALL_BASE: &str = "$HOME/.local/lib/processlama";

/// Checks the helper bytes on stdin, makes sure they run and report the build
/// ID, and moves them into place. Prints `<INSTALL_PREFIX> 1 <result>`.
pub fn install(build_id: &str, sha256: &str, size: u64) -> Option<String> {
    if !is_valid_build_id(build_id) || !is_valid_sha256(sha256) || size == 0 || size > HELPER_BYTES as u64 {
        return None;
    }
    let result = |word: &str| format!("{{ printf '{INSTALL_PREFIX} 1 {word}\\n'; exit 0; }}");
    let exe = HELPER_EXECUTABLE;
    Some(
        [
            "umask 077".to_owned(),
            format!("r=\"{INSTALL_BASE}\""),
            format!("d=\"$r/remote/{build_id}\""),
            format!("h=\"$d/{exe}\""),
            format!(
                "for p in \"$HOME/.local\" \"$HOME/.local/lib\" \"$r\" \"$r/remote\" \"$d\" \"$h\"; do [ ! -L \"$p\" ] || {}; done",
                result("refused")
            ),
            format!("mkdir -p \"$d\" 2>/dev/null || {}", result("refused")),
            format!("chmod 700 \"$r\" \"$r/remote\" \"$d\" || {}", result("refused")),
            format!("{{ command -v sha256sum || command -v shasum; }} >/dev/null 2>&1 || {}", result("refused")),
            format!("t=\"$d/.{exe}.$$\""),
            "trap 'rm -f \"$t\"' EXIT".to_owned(),
            format!("head -c {} > \"$t\" 2>/dev/null || {}", size + 1, result("noSpace")),
            format!("[ \"$(wc -c < \"$t\" | tr -d \" \")\" = {size} ] || {}", result("damaged")),
            "if command -v sha256sum >/dev/null 2>&1; then v=\"$(sha256sum < \"$t\" | cut -c1-64)\"; else v=\"$(shasum -a 256 < \"$t\" | cut -c1-64)\"; fi".to_owned(),
            format!("[ \"$v\" = {sha256} ] || {}", result("damaged")),
            format!("chmod 755 \"$t\" || {}", result("refused")),
            "o=\"$(\"$t\" --version 2>/dev/null)\"; c=$?".to_owned(),
            format!("[ $c -ne 126 ] || {}", result("noexec")),
            format!("case \"$o\" in *'\"buildId\":\"{build_id}\"'*) ;; *) {};; esac", result("damaged")),
            format!("mv -f \"$t\" \"$h\" 2>/dev/null || {}", result("noSpace")),
            format!("printf '{INSTALL_PREFIX} 1 ok\\n'"),
        ]
        .join("; "),
    )
}

/// Removes helper builds unused for 30 days: never `keep` and never a build
/// whose helper still runs.
pub fn prune(keep: &str) -> Option<String> {
    if !is_valid_build_id(keep) {
        return None;
    }
    let ok = format!("printf '{INSTALL_PREFIX} 1 ok\\n'");
    Some(
        [
            format!("r=\"{INSTALL_BASE}/remote\""),
            format!("{{ [ -d \"$r\" ] && [ ! -L \"$r\" ]; }} || {{ {ok}; exit 0; }}"),
            format!(
                "find \"$r\" -mindepth 1 -maxdepth 1 -type d -mtime +30 | while IFS= read -r d; do b=\"${{d##*/}}\"; \
                 case \"$b\" in {keep}) continue;; *[!0-9a-f]*|\"\") continue;; esac; [ ${{#b}} -eq 40 ] || continue; \
                 busy=0; for f in \"$d\"/.running.*; do [ -e \"$f\" ] || continue; p=\"${{f##*.}}\"; \
                 case \"$p\" in *[!0-9]*|\"\") continue;; esac; kill -0 \"$p\" 2>/dev/null && busy=1; done; \
                 [ $busy = 1 ] || rm -rf -- \"$d\"; done"
            ),
            ok,
        ]
        .join("; "),
    )
}

/// Removes every installed helper and the helper's caches.
pub fn uninstall(build_id: &str) -> Option<String> {
    if !is_valid_build_id(build_id) {
        return None;
    }
    let cache = format!("$HOME/{CACHE_ROOT}");
    Some(
        [
            format!("r=\"{INSTALL_BASE}\""),
            format!("h=\"$r/remote/{build_id}/{HELPER_EXECUTABLE}\""),
            format!(
                "for p in \"$r\" \"$r/remote\" \"{cache}\"; do [ ! -L \"$p\" ] || {{ printf '{INSTALL_PREFIX} 1 refused\\n'; exit 0; }}; done"
            ),
            "[ ! -x \"$h\" ] || \"$h\" --remove-state >/dev/null 2>&1 || true".to_owned(),
            format!("rm -rf -- \"$r/remote\" \"{cache}\""),
            "rmdir \"$r\" 2>/dev/null || true".to_owned(),
            format!("printf '{INSTALL_PREFIX} 1 ok\\n'"),
        ]
        .join("; "),
    )
}

/// A status line `<PREFIX> <version> <word>...` printed by a fixed script.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StatusMarker {
    pub version: u32,
    pub words: Vec<String>,
}

impl StatusMarker {
    pub fn parse(line: Option<&str>, prefix: &str) -> Option<Self> {
        let parts: Vec<&str> = line?.trim().split(' ').collect();
        if parts.len() < 2 || parts.len() > 10 || parts[0] != prefix {
            return None;
        }
        let version: u32 = parts[1].parse().ok()?;
        if parts[1] != version.to_string() {
            return None;
        }
        let words: Vec<String> = parts[2..].iter().map(|word| (*word).to_owned()).collect();
        if words
            .iter()
            .any(|word| word.is_empty() || word.len() > 64 || word.bytes().any(|b| !(0x21..=0x7e).contains(&b)))
        {
            return None;
        }
        Some(Self { version, words })
    }
}

/// The last non-empty line, read as Latin-1 so invalid UTF-8 cannot fail.
pub fn last_non_empty_line(bytes: &[u8]) -> Option<String> {
    let text: String = bytes.iter().map(|&b| b as char).collect();
    text.split('\n')
        .rev()
        .map(|line| line.strip_suffix('\r').unwrap_or(line))
        .find(|line| !line.trim().is_empty())
        .map(str::to_owned)
}

#[cfg(test)]
mod tests {
    use super::*;

    const BUILD: &str = "0000000000000000000000000000000000000003";

    #[test]
    fn scripts_reject_untrusted_values() {
        assert!(bootstrap("x; rm -rf /").is_none());
        assert!(install(BUILD, "not-a-digest", 10).is_none());
        assert!(install(BUILD, &"a".repeat(64), 0).is_none());
    }

    #[test]
    fn bootstrap_execs_the_installed_helper() {
        let script = bootstrap(BUILD).unwrap();
        assert!(script.contains(&format!("{INSTALL_ROOT}/{BUILD}/{HELPER_EXECUTABLE}")));
        assert!(script.contains("exec \"$h\" --stdio"));
        assert!(!script.contains('\n'));
    }

    #[test]
    fn markers_parse_the_last_line() {
        let output = b"motd text\r\nPROCESSLAMA-BOOTSTRAP 1 missing linux/x86_64\r\n\r\n";
        let line = last_non_empty_line(output);
        let marker = StatusMarker::parse(line.as_deref(), BOOTSTRAP_PREFIX).unwrap();
        assert_eq!(marker.version, 1);
        assert_eq!(marker.words, ["missing", "linux/x86_64"]);
        assert!(StatusMarker::parse(Some("PROCESSLAMA-BOOTSTRAP 01 start"), BOOTSTRAP_PREFIX).is_none());
    }
}
