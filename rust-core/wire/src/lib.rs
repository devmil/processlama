//! ProcessLama's remote helper contract.
//!
//! `contract` is generated from `tooling/remote_wire/contract.json`; `messages` encodes and
//! validates the product payloads both peers exchange. The helper and the desktop core use
//! only these values.
pub mod contract;
pub mod messages;

/// The helper compatibility version from `remote-helper/COMPATIBILITY`.
pub const COMPATIBILITY: &str = env!("PROCESSLAMA_REMOTE_HELPER_COMPATIBILITY");

/// The build ID a helper reports and is installed under: the compatibility version as 40
/// decimal digits. A client talks only to a helper of its own build ID.
pub const BUILD_ID: &str = env!("PROCESSLAMA_REMOTE_HELPER_ID");

/// The processtree revision the telemetry is built from.
pub const PROCESSTREE_REVISION: &str = env!("PROCESSLAMA_PROCESSTREE_REVISION");

/// Whether `value` is a well-formed build ID: 40 lowercase hexadecimal digits.
pub fn is_build_id(value: &str) -> bool {
    value.len() == 40
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_id_is_the_compatibility_version_as_forty_digits() {
        assert!(is_build_id(BUILD_ID));
        let version: u64 = COMPATIBILITY.parse().unwrap();
        assert_eq!(BUILD_ID, format!("{version:0>40}"));
        assert!(!PROCESSTREE_REVISION.is_empty());
    }
}
