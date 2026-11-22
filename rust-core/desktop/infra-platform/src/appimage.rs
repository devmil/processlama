//! In-place AppImage updates: the Linux counterpart of Sparkle.
//!
//! An AppImage is one self-contained file, like a macOS app bundle, so an
//! update replaces that file. The release list names the AppImage of each
//! release with its size, SHA-256 and an Ed25519 `updateSignature` by the
//! Sparkle key, over [`signed_message`]. The app trusts only that embedded
//! key: it verifies the signature before it offers the install, then
//! downloads into the AppImage's folder within a size bound, checks the exact
//! size and hash and renames the file over the running AppImage. The running
//! process keeps the old file open, so the swap takes effect on restart.
//!
//! `scripts/lib/update_signature.py` signs releases with the same message.

use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

/// The Sparkle public key (`SUPublicEDKey` in the macOS Info.plist).
pub const UPDATE_PUBLIC_KEY: &str = "VVeo9BGR688hcHmfypCIbf6pVrfT9UD3VUR6nJXFhcU=";
/// The largest update the client downloads.
pub const MAX_UPDATE_BYTES: u64 = 512 * 1024 * 1024;
const PREFIX: &str = "ProcessLama AppImage update v1";

/// A verified AppImage update.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AppImageUpdate {
    pub build: u64,
    pub url: String,
    pub size: u64,
    pub sha256: String,
}

/// The bytes the release signs for one AppImage.
pub fn signed_message(build: u64, arch: &str, size: u64, sha256: &str) -> String {
    format!("{PREFIX}\nbuild={build}\narch={arch}\nsize={size}\nsha256={sha256}\n")
}

/// The AppImage this process runs from, when it is one.
///
/// The AppImage runtime sets `APPIMAGE` and `APPDIR`; children inherit them,
/// so the executable must also live inside `APPDIR`.
pub fn running_appimage() -> Option<PathBuf> {
    if !cfg!(target_os = "linux") {
        return None;
    }
    let image = PathBuf::from(std::env::var_os("APPIMAGE")?);
    let mount = PathBuf::from(std::env::var_os("APPDIR")?);
    let executable = std::env::current_exe().ok()?;
    (image.is_absolute() && image.is_file() && executable.starts_with(&mount)).then_some(image)
}

/// Picks the signed AppImage for `arch` from a release entry.
pub fn select_update(entry: &Value, arch: &str, public_key: &str) -> Option<AppImageUpdate> {
    let build = entry.get("build").and_then(Value::as_u64)?;
    let artifact = entry
        .get("artifacts")?
        .as_array()?
        .iter()
        .find(|artifact| {
            artifact.get("format").and_then(Value::as_str) == Some("appimage")
                && artifact.get("architectures").and_then(Value::as_str) == Some(arch)
        })?;
    let url = artifact.get("downloadPath")?.as_str()?;
    let size = artifact.get("sizeBytes")?.as_u64()?;
    let sha256 = artifact.get("sha256")?.as_str()?;
    let signature = artifact.get("updateSignature")?.as_str()?;
    let valid_hash = sha256.len() == 64
        && sha256
            .bytes()
            .all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'));
    if !url.starts_with("https://") || size == 0 || size > MAX_UPDATE_BYTES || !valid_hash {
        return None;
    }
    let key = STANDARD.decode(public_key).ok()?;
    let signature = STANDARD.decode(signature).ok()?;
    let message = signed_message(build, arch, size, sha256);
    ring::signature::UnparsedPublicKey::new(&ring::signature::ED25519, key)
        .verify(message.as_bytes(), &signature)
        .ok()?;
    Some(AppImageUpdate {
        build,
        url: url.to_owned(),
        size,
        sha256: sha256.to_owned(),
    })
}

/// Streams `source` into a file beside `target`, checks it against
/// `update` and renames it over `target`. Reports bytes received.
pub fn install_from(
    mut source: impl Read,
    update: &AppImageUpdate,
    target: &Path,
    progress: &mut dyn FnMut(u64, u64),
) -> Result<(), String> {
    let folder = target
        .parent()
        .ok_or_else(|| "The AppImage has no folder.".to_owned())?;
    let name = target
        .file_name()
        .ok_or_else(|| "The AppImage has no name.".to_owned())?
        .to_string_lossy()
        .into_owned();
    let partial = folder.join(format!(".{name}.update-{}", std::process::id()));
    let result = (|| {
        let mut file = create_executable(&partial).map_err(|error| {
            format!(
                "Could not write next to the AppImage in {}: {error}",
                folder.display()
            )
        })?;
        let mut hasher = Sha256::new();
        let mut received = 0u64;
        let mut buffer = vec![0u8; 64 * 1024];
        loop {
            let read = source.read(&mut buffer).map_err(|e| e.to_string())?;
            if read == 0 {
                break;
            }
            received += read as u64;
            if received > update.size {
                return Err("The download is larger than the release says.".to_owned());
            }
            hasher.update(&buffer[..read]);
            file.write_all(&buffer[..read]).map_err(|e| e.to_string())?;
            progress(received, update.size);
        }
        if received != update.size {
            return Err("The download ended early.".to_owned());
        }
        let digest: String = hasher
            .finalize()
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect();
        if digest != update.sha256 {
            return Err("The download does not match the release checksum.".to_owned());
        }
        file.sync_all().map_err(|e| e.to_string())?;
        drop(file);
        fs::rename(&partial, target).map_err(|e| e.to_string())?;
        if let Ok(folder) = File::open(folder) {
            let _ = folder.sync_all();
        }
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(&partial);
    }
    result
}

fn create_executable(path: &Path) -> std::io::Result<File> {
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    std::os::unix::fs::OpenOptionsExt::mode(&mut options, 0o755);
    options.open(path)
}

/// Starts `image` as a new process, without the AppImage runtime variables
/// of this one.
pub fn relaunch(image: &Path) -> Result<(), String> {
    std::process::Command::new(image)
        .env_remove("APPIMAGE")
        .env_remove("APPDIR")
        .env_remove("ARGV0")
        .env_remove("OWD")
        .spawn()
        .map(drop)
        .map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    // Made by `scripts/lib/update_signature.py sign` with the seed 0x00..0x1f
    // over a 14-byte AppImage `appimage-bytes`, build 47, x86_64.
    const TEST_KEY: &str = "A6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=";
    const TEST_SIGNATURE: &str =
        "a4nkL0vctU64mqhOEPSLMwRE8N3h/6JmnIUSPf7QnqRn4JPTkYUqNQOk5IstUwcP0P9tXVgaxUmueMAQ46/NBQ==";
    const PAYLOAD: &[u8] = b"appimage-bytes";

    fn sha(bytes: &[u8]) -> String {
        Sha256::digest(bytes)
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect()
    }

    fn entry(signature: &str, size: u64) -> Value {
        json!({"version": "1.0.0", "build": 47, "artifacts": [
            {"format": "deb", "architectures": "x86_64"},
            {"format": "appimage", "architectures": "x86_64",
             "downloadPath": "https://example.invalid/ProcessLama.AppImage",
             "sizeBytes": size, "sha256": sha(PAYLOAD), "updateSignature": signature}
        ]})
    }

    fn update() -> AppImageUpdate {
        select_update(&entry(TEST_SIGNATURE, 14), "x86_64", TEST_KEY).expect("signed update")
    }

    #[test]
    fn the_embedded_key_is_the_sparkle_key() {
        let plist = include_str!("../../../../packaging/macos/Info.plist.in");
        let key = plist.split("<key>SUPublicEDKey</key>").nth(1).unwrap();
        let value = key
            .split("<string>")
            .nth(1)
            .unwrap()
            .split("</string>")
            .next()
            .unwrap();
        assert_eq!(value, UPDATE_PUBLIC_KEY);
    }

    #[test]
    fn accepts_only_a_valid_signature_for_the_exact_identity() {
        assert_eq!(update().size, 14);
        assert_eq!(
            select_update(&entry(TEST_SIGNATURE, 15), "x86_64", TEST_KEY),
            None
        );
        assert_eq!(
            select_update(&entry(TEST_SIGNATURE, 14), "aarch64", TEST_KEY),
            None
        );
        assert_eq!(select_update(&entry("", 14), "x86_64", TEST_KEY), None);
        assert_eq!(
            select_update(&entry(TEST_SIGNATURE, 14), "x86_64", UPDATE_PUBLIC_KEY),
            None
        );
        let mut later = entry(TEST_SIGNATURE, 14);
        later["build"] = json!(48);
        assert_eq!(select_update(&later, "x86_64", TEST_KEY), None);
    }

    #[test]
    fn installs_by_renaming_over_the_appimage() {
        let folder = tempfile::tempdir().unwrap();
        let target = folder.path().join("ProcessLama.AppImage");
        fs::write(&target, b"old").unwrap();
        let mut seen = 0;
        install_from(PAYLOAD, &update(), &target, &mut |received, _| {
            seen = received
        })
        .unwrap();
        assert_eq!(fs::read(&target).unwrap(), PAYLOAD);
        assert_eq!(seen, 14);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                fs::metadata(&target).unwrap().permissions().mode() & 0o777,
                0o755
            );
        }
        assert_eq!(fs::read_dir(folder.path()).unwrap().count(), 1);
    }

    #[test]
    fn keeps_the_appimage_when_the_download_is_wrong() {
        let folder = tempfile::tempdir().unwrap();
        let target = folder.path().join("ProcessLama.AppImage");
        for bytes in [
            &b"appimage-bytez"[..],
            b"appimage",
            b"appimage-bytes-and-more",
        ] {
            fs::write(&target, b"old").unwrap();
            assert!(install_from(bytes, &update(), &target, &mut |_, _| {}).is_err());
            assert_eq!(fs::read(&target).unwrap(), b"old");
            assert_eq!(fs::read_dir(folder.path()).unwrap().count(), 1);
        }
    }
}
