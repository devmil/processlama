use crate::files::write_atomically;
use processlama_application::SnapshotStore;
use processlama_domain::{SNAPSHOT_EXTENSION, SnapshotDocument, SnapshotEntry};
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

/// `<support>/snapshots/snapshot-<ms>.processlama-snapshot.json`.
pub struct FileSnapshotStore {
    directory: PathBuf,
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as u64)
}

fn read_document(path: &Path) -> Result<SnapshotDocument, String> {
    let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
    let value: Value = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
    if !value.is_object() {
        return Err("Snapshot document must be a JSON object.".into());
    }
    Ok(SnapshotDocument::from_json(&value, now_ms()))
}

fn encode(document: &SnapshotDocument) -> Result<Vec<u8>, String> {
    serde_json::to_vec_pretty(&document.to_json()).map_err(|e| e.to_string())
}

impl FileSnapshotStore {
    pub fn new(support_dir: &Path) -> Self {
        Self {
            directory: support_dir.join("snapshots"),
        }
    }

    fn ensure_directory(&self) -> Result<(), String> {
        std::fs::create_dir_all(&self.directory).map_err(|e| e.to_string())
    }

    fn next_file(&self) -> PathBuf {
        loop {
            let path = self
                .directory
                .join(format!("snapshot-{}{SNAPSHOT_EXTENSION}", now_ms()));
            if !path.exists() {
                return path;
            }
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
    }
}

impl SnapshotStore for FileSnapshotStore {
    fn list(&self) -> Result<Vec<SnapshotEntry>, String> {
        self.ensure_directory()?;
        let mut files: Vec<PathBuf> = std::fs::read_dir(&self.directory)
            .map_err(|e| e.to_string())?
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .filter(|path| path.is_file() && path.to_string_lossy().ends_with(SNAPSHOT_EXTENSION))
            .collect();
        files.sort_by(|a, b| b.cmp(a));
        Ok(files
            .into_iter()
            .filter_map(|path| {
                let document = read_document(&path).ok()?;
                Some(SnapshotEntry {
                    path: path.to_string_lossy().into_owned(),
                    generated_at_unix_ms: document.snapshot.generated_at_unix_ms,
                    process_count: document.snapshot.processes.len(),
                    platform: document.snapshot.platform.clone(),
                    name: document.display_name.clone(),
                })
            })
            .collect())
    }

    fn save(&self, document: &SnapshotDocument) -> Result<String, String> {
        self.ensure_directory()?;
        let path = self.next_file();
        write_atomically(&path, &encode(document)?).map_err(|e| e.to_string())?;
        Ok(path.to_string_lossy().into_owned())
    }

    fn read(&self, path: &str) -> Result<SnapshotDocument, String> {
        read_document(Path::new(path))
    }

    fn import(&self, path: &str) -> Result<String, String> {
        let document = read_document(Path::new(path))?;
        self.save(&document)
    }

    fn export(&self, entry: &SnapshotEntry, target: &str) -> Result<(), String> {
        std::fs::copy(&entry.path, target)
            .map(|_| ())
            .map_err(|e| e.to_string())
    }

    fn rename(&self, entry: &SnapshotEntry, name: &str) -> Result<(), String> {
        let mut document = read_document(Path::new(&entry.path))?;
        let trimmed = name.trim();
        document.display_name = (!trimmed.is_empty()).then(|| trimmed.to_owned());
        write_atomically(Path::new(&entry.path), &encode(&document)?).map_err(|e| e.to_string())
    }

    fn delete(&self, entry: &SnapshotEntry) -> Result<(), String> {
        match std::fs::remove_file(&entry.path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error.to_string()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use processlama_domain::{ProcessRecord, ProcessSnapshot};
    use std::sync::Arc;

    #[test]
    fn saves_lists_renames_imports_and_deletes() {
        let dir = tempfile::tempdir().unwrap();
        let store = FileSnapshotStore::new(dir.path());
        let document = SnapshotDocument {
            schema_version: 1,
            exported_at_unix_ms: 1,
            source: "ProcessLama".into(),
            display_name: None,
            host: None,
            icons: Default::default(),
            snapshot: ProcessSnapshot {
                generated_at_unix_ms: 42,
                platform: "linux".into(),
                processes: vec![Arc::new(ProcessRecord::default())],
                error: None,
                topology: None,
            },
        };
        let path = store.save(&document).unwrap();
        let entries = store.list().unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].process_count, 1);
        store.rename(&entries[0], " Mine ").unwrap();
        assert_eq!(store.list().unwrap()[0].name.as_deref(), Some("Mine"));
        let external = dir.path().join("outside.json");
        store
            .export(&entries[0], external.to_str().unwrap())
            .unwrap();
        let imported = store.import(external.to_str().unwrap()).unwrap();
        assert_ne!(imported, path);
        assert_eq!(store.list().unwrap().len(), 2);
        store.delete(&entries[0]).unwrap();
        assert_eq!(store.list().unwrap().len(), 1);
    }
}
