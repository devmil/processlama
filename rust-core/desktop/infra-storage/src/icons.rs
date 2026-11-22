use crate::files::write_atomically;
use processlama_application::IconCache;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

const ICON_BYTES: usize = 262_144;
const ICON_SOURCE_PIXELS: u32 = 512;
const PNG_SIGNATURE: [u8; 8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

fn is_hash(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

/// A PNG whose header declares at most 512×512 pixels, at most 256 KiB, with
/// the requested digest.
pub fn is_acceptable_icon(sha256: &str, bytes: &[u8]) -> bool {
    if !is_hash(sha256) || bytes.len() > ICON_BYTES || bytes.len() < 33 || bytes[..8] != PNG_SIGNATURE {
        return false;
    }
    if u32::from_be_bytes(bytes[8..12].try_into().expect("4 bytes")) != 13 || &bytes[12..16] != b"IHDR" {
        return false;
    }
    let width = u32::from_be_bytes(bytes[16..20].try_into().expect("4 bytes"));
    let height = u32::from_be_bytes(bytes[20..24].try_into().expect("4 bytes"));
    if width == 0 || height == 0 || width > ICON_SOURCE_PIXELS || height > ICON_SOURCE_PIXELS {
        return false;
    }
    let digest = Sha256::digest(bytes);
    let hex: String = digest.iter().map(|b| format!("{b:02x}")).collect();
    hex == sha256
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_millis() as u64)
}

#[derive(Clone, Copy)]
struct Entry {
    bytes: u64,
    last_used: u64,
}

/// `<root>/<aa>/<sha256>.png` plus `index.json` with size and last use.
pub struct FileIconCache {
    root: PathBuf,
    entries: Mutex<HashMap<String, Entry>>,
}

impl FileIconCache {
    pub fn open(root: PathBuf) -> Self {
        let _ = std::fs::create_dir_all(&root);
        let mut entries = HashMap::new();
        if let Ok(bytes) = std::fs::read(root.join("index.json"))
            && let Ok(Value::Object(map)) = serde_json::from_slice::<Value>(&bytes)
        {
            for (key, value) in map {
                let (Some(size), Some(last)) = (
                    value.get("bytes").and_then(Value::as_u64),
                    value.get("lastUsed").and_then(Value::as_u64),
                ) else {
                    continue;
                };
                if is_hash(&key) && root.join(&key[..2]).join(format!("{key}.png")).exists() {
                    entries.insert(key, Entry { bytes: size, last_used: last });
                }
            }
        }
        Self {
            root,
            entries: Mutex::new(entries),
        }
    }

    fn path(&self, hash: &str) -> PathBuf {
        self.root.join(&hash[..2]).join(format!("{hash}.png"))
    }

    fn write_index(&self, entries: &HashMap<String, Entry>) {
        let index: serde_json::Map<String, Value> = entries
            .iter()
            .map(|(key, entry)| (key.clone(), json!({"bytes": entry.bytes, "lastUsed": entry.last_used})))
            .collect();
        if let Ok(bytes) = serde_json::to_vec(&Value::Object(index)) {
            let _ = write_atomically(&self.root.join("index.json"), &bytes);
        }
    }
}

impl IconCache for FileIconCache {
    fn path_for(&self, sha256: &str) -> Option<String> {
        let entries = self.entries.lock().ok()?;
        entries
            .contains_key(sha256)
            .then(|| self.path(sha256).to_string_lossy().into_owned())
    }

    fn total_bytes(&self) -> u64 {
        self.entries.lock().map_or(0, |entries| entries.values().map(|e| e.bytes).sum())
    }

    fn touch(&self, hashes: &[String]) {
        let Ok(mut entries) = self.entries.lock() else {
            return;
        };
        let now = now_ms();
        for hash in hashes {
            if let Some(entry) = entries.get_mut(hash) {
                entry.last_used = now;
            }
        }
    }

    fn store(&self, sha256: &str, bytes: &[u8]) -> Option<String> {
        if !is_acceptable_icon(sha256, bytes) {
            return None;
        }
        let path = self.path(sha256);
        write_atomically(&path, bytes).ok()?;
        let mut entries = self.entries.lock().ok()?;
        entries.insert(
            sha256.to_owned(),
            Entry {
                bytes: bytes.len() as u64,
                last_used: now_ms(),
            },
        );
        self.write_index(&entries);
        Some(path.to_string_lossy().into_owned())
    }

    fn read(&self, sha256: &str) -> Option<Vec<u8>> {
        if self.path_for(sha256).is_none() {
            return None;
        }
        std::fs::read(self.path(sha256)).ok()
    }

    fn evict(&self, limit_bytes: u64, keep: &HashSet<String>) {
        let Ok(mut entries) = self.entries.lock() else {
            return;
        };
        let mut total: u64 = entries.values().map(|e| e.bytes).sum();
        if total <= limit_bytes {
            self.write_index(&entries);
            return;
        }
        let mut candidates: Vec<(String, Entry)> = entries
            .iter()
            .filter(|(key, _)| !keep.contains(*key))
            .map(|(key, entry)| (key.clone(), *entry))
            .collect();
        candidates.sort_by_key(|(_, entry)| entry.last_used);
        for (key, entry) in candidates {
            if total <= limit_bytes {
                break;
            }
            entries.remove(&key);
            total -= entry.bytes;
            let _ = std::fs::remove_file(self.path(&key));
        }
        self.write_index(&entries);
    }

    fn clear(&self) {
        if let Ok(mut entries) = self.entries.lock() {
            entries.clear();
        }
        let _ = std::fs::remove_dir_all(&self.root);
        let _ = std::fs::create_dir_all(&self.root);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn png(width: u32, height: u32) -> Vec<u8> {
        let mut bytes = PNG_SIGNATURE.to_vec();
        bytes.extend_from_slice(&13u32.to_be_bytes());
        bytes.extend_from_slice(b"IHDR");
        bytes.extend_from_slice(&width.to_be_bytes());
        bytes.extend_from_slice(&height.to_be_bytes());
        bytes.extend_from_slice(&[8, 6, 0, 0, 0, 0, 0, 0, 0]);
        bytes
    }

    fn hash(bytes: &[u8]) -> String {
        Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect()
    }

    #[test]
    fn stores_valid_icons_and_evicts_least_recently_used() {
        let dir = tempfile::tempdir().unwrap();
        let cache = FileIconCache::open(dir.path().join("icons"));
        let a = png(16, 16);
        let b = png(32, 32);
        assert!(cache.store(&hash(&a), &a).is_some());
        assert!(cache.store(&"0".repeat(64), &a).is_none());
        assert!(cache.store(&hash(&png(600, 2)), &png(600, 2)).is_none());
        std::thread::sleep(std::time::Duration::from_millis(2));
        cache.store(&hash(&b), &b).unwrap();
        assert_eq!(cache.total_bytes(), (a.len() + b.len()) as u64);
        cache.evict(b.len() as u64, &HashSet::new());
        assert!(cache.path_for(&hash(&a)).is_none());
        assert!(cache.path_for(&hash(&b)).is_some());
        let reopened = FileIconCache::open(dir.path().join("icons"));
        assert!(reopened.path_for(&hash(&b)).is_some());
        reopened.clear();
        assert_eq!(reopened.total_bytes(), 0);
    }
}
