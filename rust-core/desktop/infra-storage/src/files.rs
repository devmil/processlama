use std::io::Write;
use std::path::{Path, PathBuf};

/// The per-user application support directory the Flutter builds used:
/// `~/.local/share/de.devmil.processlama` on Linux (or `$XDG_DATA_HOME`),
/// `~/Library/Application Support/de.devmil.processlama` on macOS and
/// `%APPDATA%\devmil\ProcessLama` on Windows.
pub fn application_support_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("PROCESSLAMA_DATA_DIR").filter(|dir| !dir.is_empty()) {
        return PathBuf::from(dir);
    }
    let home = || std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    if cfg!(target_os = "macos") {
        home().join("Library/Application Support/de.devmil.processlama")
    } else if cfg!(windows) {
        std::env::var_os("APPDATA")
            .map(PathBuf::from)
            .unwrap_or_else(home)
            .join("devmil")
            .join("ProcessLama")
    } else {
        std::env::var_os("XDG_DATA_HOME")
            .filter(|dir| !dir.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| home().join(".local/share"))
            .join("de.devmil.processlama")
    }
}

/// Writes `bytes` to `path` through a temporary file and a rename.
pub fn write_atomically(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let temporary = path.with_extension(format!("{}.tmp", std::process::id()));
    {
        let mut file = std::fs::File::create(&temporary)?;
        file.write_all(bytes)?;
        file.sync_all()?;
    }
    std::fs::rename(&temporary, path)
}
