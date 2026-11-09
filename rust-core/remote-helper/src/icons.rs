//! Content-addressed process icons for one connection.
//!
//! A record's icon file is normalized once per (size, modification time) on a worker thread
//! and identified by the SHA-256 of the normalized PNG. Telemetry samples carry the hash;
//! `icons.fetch` returns the bytes. A changed source file gets a new hash, so the client
//! fetches it once and its old copy ages out of the cache.
use crate::telemetry::IconHasher;
use devmil_remote::server::lock;
use processlama_telemetry::backend::ProcessRecord;
use processlama_telemetry::icons::{self, MAX_SOURCE_BYTES};
use processlama_wire::contract;
use serde_json::{Map, Value, json};
use std::collections::{HashMap, HashSet, VecDeque};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, SystemTime};

/// Normalized bytes kept in memory; evicted icons are normalized again on demand.
const STORE_BYTES: usize = 32 * 1024 * 1024;
/// One normalization may take this long; a slower source is dropped.
const NORMALIZE_DEADLINE: Duration = Duration::from_secs(2);

#[derive(Clone)]
struct Source {
    size: u64,
    modified: Option<SystemTime>,
    /// None while queued or when the source cannot become an icon.
    hash: Option<String>,
}

#[derive(Default)]
struct State {
    sources: HashMap<PathBuf, Source>,
    queue: VecDeque<PathBuf>,
    queued: HashSet<PathBuf>,
    bytes: HashMap<String, Arc<Vec<u8>>>,
    /// Hashes by recency of use, oldest first.
    recency: VecDeque<String>,
    stored: usize,
    paths: HashMap<String, PathBuf>,
    working: bool,
    stopped: bool,
}

pub struct IconStore {
    state: Mutex<State>,
    work: Condvar,
    idle: Condvar,
}

/// The local path of a `file://` URI processtree produced.
pub fn path_of(uri: &str) -> Option<PathBuf> {
    let encoded = uri.strip_prefix("file://")?;
    let bytes = encoded.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' && index + 2 < bytes.len() {
            let hex = std::str::from_utf8(&bytes[index + 1..index + 3]).ok()?;
            decoded.push(u8::from_str_radix(hex, 16).ok()?);
            index += 3;
        } else {
            decoded.push(bytes[index]);
            index += 1;
        }
    }
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStringExt;
        Some(PathBuf::from(std::ffi::OsString::from_vec(decoded)))
    }
    #[cfg(not(unix))]
    {
        String::from_utf8(decoded).ok().map(PathBuf::from)
    }
}

fn read_bounded(path: &Path) -> Option<Vec<u8>> {
    let file = std::fs::File::open(path).ok()?;
    let mut bytes = Vec::new();
    file.take(MAX_SOURCE_BYTES as u64 + 1)
        .read_to_end(&mut bytes)
        .ok()?;
    Some(bytes)
}

/// Normalizes on a separate thread, so a pathological source cannot stall the worker.
fn normalize_bounded(source: Vec<u8>) -> Option<Vec<u8>> {
    let (sender, receiver) = mpsc::channel();
    std::thread::spawn(move || {
        let _ = sender.send(icons::normalize(&source).ok());
    });
    receiver.recv_timeout(NORMALIZE_DEADLINE).ok().flatten()
}

impl IconStore {
    pub fn start() -> Arc<Self> {
        let store = Arc::new(Self {
            state: Mutex::new(State::default()),
            work: Condvar::new(),
            idle: Condvar::new(),
        });
        let worker = Arc::clone(&store);
        std::thread::spawn(move || worker.run());
        store
    }

    /// Waits up to `timeout` until every queued icon is normalized.
    pub fn wait_idle(&self, timeout: Duration) {
        let deadline = std::time::Instant::now() + timeout;
        let mut state = lock(&self.state);
        while (state.working || !state.queue.is_empty()) && !state.stopped {
            let now = std::time::Instant::now();
            if now >= deadline {
                return;
            }
            state = self
                .idle
                .wait_timeout(state, deadline - now)
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .0;
        }
    }

    pub fn stop(&self) {
        lock(&self.state).stopped = true;
        self.work.notify_all();
    }

    fn run(&self) {
        loop {
            let path = {
                let mut state = lock(&self.state);
                loop {
                    if state.stopped {
                        return;
                    }
                    if let Some(path) = state.queue.pop_front() {
                        state.working = true;
                        break path;
                    }
                    state.working = false;
                    self.idle.notify_all();
                    state = self
                        .work
                        .wait(state)
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                }
            };
            let metadata = std::fs::metadata(&path).ok();
            let normalized = read_bounded(&path).and_then(normalize_bounded);
            let mut state = lock(&self.state);
            state.queued.remove(&path);
            let hash = normalized.map(|png| {
                let hash = icons::sha256_hex(&png);
                Self::keep(&mut state, &hash, Arc::new(png));
                state.paths.insert(hash.clone(), path.clone());
                hash
            });
            state.sources.insert(
                path,
                Source {
                    size: metadata.as_ref().map_or(0, std::fs::Metadata::len),
                    modified: metadata.and_then(|metadata| metadata.modified().ok()),
                    hash,
                },
            );
        }
    }

    fn keep(state: &mut State, hash: &str, png: Arc<Vec<u8>>) {
        if !state.bytes.contains_key(hash) {
            state.stored += png.len();
            state.bytes.insert(hash.to_owned(), png);
        }
        state.recency.retain(|known| known != hash);
        state.recency.push_back(hash.to_owned());
        while state.stored > STORE_BYTES {
            let Some(oldest) = state.recency.pop_front() else {
                break;
            };
            if let Some(evicted) = state.bytes.remove(&oldest) {
                state.stored -= evicted.len();
            }
        }
    }

    /// `icons.fetch`: up to 64 icons and 4 MiB per call; unknown hashes are left out.
    pub fn fetch(&self, arguments: &Map<String, Value>) -> Option<Value> {
        let hashes = arguments.get("hashes")?.as_array()?;
        if hashes.len() > contract::ICONS_PER_FETCH {
            return None;
        }
        let mut icons = Vec::new();
        let mut total = 0;
        for hash in hashes {
            let hash = hash.as_str()?;
            if hash.len() != 64
                || !hash
                    .bytes()
                    .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
            {
                return None;
            }
            let Some(png) = self.bytes_for(hash) else {
                continue;
            };
            if total + png.len() > contract::ICON_FETCH_BYTES {
                break;
            }
            total += png.len();
            icons.push(json!({"sha256": hash, "png": base64(&png)}));
        }
        Some(json!({"icons": icons}))
    }

    fn bytes_for(&self, hash: &str) -> Option<Arc<Vec<u8>>> {
        let path = {
            let mut state = lock(&self.state);
            if let Some(png) = state.bytes.get(hash).cloned() {
                Self::keep(&mut state, hash, Arc::clone(&png));
                return Some(png);
            }
            state.paths.get(hash).cloned()?
        };
        // Evicted from memory: normalize the source again, if it still matches.
        let png = read_bounded(&path).and_then(normalize_bounded)?;
        if icons::sha256_hex(&png) != hash {
            return None;
        }
        let png = Arc::new(png);
        Self::keep(&mut lock(&self.state), hash, Arc::clone(&png));
        Some(png)
    }
}

impl IconHasher for IconStore {
    fn settle(&self, timeout: Duration) {
        self.wait_idle(timeout);
    }

    fn icon_hash(&self, record: &ProcessRecord) -> Option<String> {
        let path = path_of(record.icon_uri.as_deref()?)?;
        let metadata = std::fs::metadata(&path).ok()?;
        let modified = metadata.modified().ok();
        let mut state = lock(&self.state);
        let known = state.sources.get(&path).cloned();
        if let Some(source) = &known {
            if source.size == metadata.len() && source.modified == modified {
                return source.hash.clone();
            }
        }
        if state.queued.insert(path.clone()) {
            state.queue.push_back(path);
            self.work.notify_all();
        }
        // While a changed source is normalized, keep showing its previous icon.
        known.and_then(|source| source.hash)
    }
}

const BASE64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// Standard padded base64.
pub fn base64(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let value = (u32::from(chunk[0]) << 16)
            | (u32::from(*chunk.get(1).unwrap_or(&0)) << 8)
            | u32::from(*chunk.get(2).unwrap_or(&0));
        for (index, shift) in [18, 12, 6, 0].into_iter().enumerate() {
            if index <= chunk.len() {
                out.push(BASE64[((value >> shift) & 63) as usize] as char);
            } else {
                out.push('=');
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_matches_the_standard_alphabet() {
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"f"), "Zg==");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert_eq!(base64(b"foo"), "Zm9v");
        assert_eq!(base64(&[0xfb, 0xff]), "+/8=");
    }

    #[test]
    fn file_uris_decode_percent_escapes() {
        assert_eq!(
            path_of("file:///usr/share/icons/a%20b.png").unwrap(),
            PathBuf::from("/usr/share/icons/a b.png")
        );
        assert!(path_of("https://example.invalid/x.png").is_none());
    }

    #[test]
    fn icons_are_hashed_after_normalization_and_fetched_by_hash() {
        let directory =
            std::env::temp_dir().join(format!("processlama-icons-{}", std::process::id()));
        std::fs::create_dir_all(&directory).unwrap();
        let path = directory.join("app icon.svg");
        std::fs::write(
            &path,
            br##"<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16" fill="#f80"/></svg>"##,
        )
        .unwrap();
        let mut record = ProcessRecord::synthetic(3, 1, "app");
        record.icon_uri = Some(format!(
            "file://{}",
            path.to_string_lossy().replace(' ', "%20")
        ));
        let store = IconStore::start();
        let mut hash = store.icon_hash(&record);
        for _ in 0..100 {
            if hash.is_some() {
                break;
            }
            std::thread::sleep(Duration::from_millis(20));
            hash = store.icon_hash(&record);
        }
        let hash = hash.expect("normalized");
        let mut arguments = Map::new();
        arguments.insert("hashes".to_owned(), json!([hash, "0".repeat(64)]));
        let fetched = store.fetch(&arguments).unwrap();
        assert_eq!(fetched["icons"].as_array().unwrap().len(), 1);
        assert_eq!(fetched["icons"][0]["sha256"], hash);

        // A changed source keeps the old hash until the new one is ready.
        std::thread::sleep(Duration::from_millis(1100));
        std::fs::write(
            &path,
            br##"<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16" fill="#08f"/></svg>"##,
        )
        .unwrap();
        assert_eq!(store.icon_hash(&record).as_deref(), Some(hash.as_str()));
        let mut changed = store.icon_hash(&record);
        for _ in 0..100 {
            if changed.as_deref() != Some(hash.as_str()) {
                break;
            }
            std::thread::sleep(Duration::from_millis(20));
            changed = store.icon_hash(&record);
        }
        assert_ne!(changed.as_deref(), Some(hash.as_str()));
        arguments.insert("hashes".to_owned(), json!(["x"]));
        assert!(store.fetch(&arguments).is_none());
        store.stop();
        std::fs::remove_dir_all(directory).unwrap();
    }
}
