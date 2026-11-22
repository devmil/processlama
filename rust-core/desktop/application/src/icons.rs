//! Remote process icons: content-addressed, fetched in batches, cached on
//! disk. A port of the Flutter `ProcessIconServiceImpl`.

use crate::core::{AppCore, CoreChanges, ToastTone};
use crate::events::CoreEvent;
use crate::remote::RemoteEvent;
use crate::remote_ports::RemoteConnection;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;

/// Icon requests grouped by the connection that serves them.
type ConnectionBatch = (Arc<dyn RemoteConnection>, Vec<(String, HashSet<String>)>);

/// Unknown hashes are collected this long, so tabs and samples share a fetch.
pub const ICON_BATCH_DELAY_MS: u64 = 100;
/// Icons per `icons.fetch`.
pub const ICON_BATCH_SIZE: usize = 64;

struct Pending {
    connection: Arc<dyn RemoteConnection>,
    keys: HashSet<String>,
}

#[derive(Default)]
pub struct IconService {
    referenced: HashMap<String, HashSet<String>>,
    failed: HashMap<String, HashSet<String>>,
    in_flight: HashSet<String>,
    pending: HashMap<String, Pending>,
    batch_at: Option<u64>,
    /// Bumped whenever an icon arrives, so rows refresh their icon role.
    pub(crate) revision: u64,
}

impl IconService {
    pub fn revision(&self) -> u64 {
        self.revision
    }

    pub(crate) fn next_deadline(&self) -> Option<u64> {
        self.batch_at
    }

    pub(crate) fn release(&mut self, source_key: &str) {
        self.referenced.remove(source_key);
        self.failed.remove(source_key);
    }

    pub(crate) fn reset_failures(&mut self, source_key: &str) {
        self.failed.remove(source_key);
    }
}

impl AppCore {
    pub(crate) fn ensure_icons(
        &mut self,
        source_key: &str,
        hashes: Vec<String>,
        connection: Arc<dyn RemoteConnection>,
    ) {
        let now = self.now();
        let cache = Arc::clone(&self.ports.icon_cache);
        cache.touch(&hashes);
        let icons = &mut self.icons;
        icons
            .referenced
            .insert(source_key.to_owned(), hashes.iter().cloned().collect());
        let failed = icons.failed.get(source_key).cloned().unwrap_or_default();
        for hash in hashes {
            if cache.path_for(&hash).is_some()
                || icons.in_flight.contains(&hash)
                || failed.contains(&hash)
            {
                continue;
            }
            icons
                .pending
                .entry(hash)
                .or_insert_with(|| Pending {
                    connection: Arc::clone(&connection),
                    keys: HashSet::new(),
                })
                .keys
                .insert(source_key.to_owned());
        }
        if !icons.pending.is_empty() && icons.batch_at.is_none() {
            icons.batch_at = Some(now + ICON_BATCH_DELAY_MS);
        }
    }

    pub(crate) fn icons_on_time(&mut self, now: u64) {
        if !self.icons.batch_at.is_some_and(|at| at <= now) {
            return;
        }
        self.icons.batch_at = None;
        let pending = std::mem::take(&mut self.icons.pending);
        // One fetcher per connection, in chunks.
        let mut by_connection: Vec<ConnectionBatch> = Vec::new();
        for (hash, entry) in pending {
            match by_connection
                .iter_mut()
                .find(|(connection, _)| Arc::ptr_eq(connection, &entry.connection))
            {
                Some((_, list)) => list.push((hash, entry.keys)),
                None => by_connection.push((entry.connection, vec![(hash, entry.keys)])),
            }
        }
        for (connection, entries) in by_connection {
            for chunk in entries.chunks(ICON_BATCH_SIZE) {
                let hashes: Vec<String> = chunk.iter().map(|(hash, _)| hash.clone()).collect();
                self.icons.in_flight.extend(hashes.iter().cloned());
                let keys: Vec<String> = chunk
                    .iter()
                    .flat_map(|(_, keys)| keys.iter().cloned())
                    .collect::<HashSet<_>>()
                    .into_iter()
                    .collect();
                let connection = Arc::clone(&connection);
                let cache = Arc::clone(&self.ports.icon_cache);
                let sink = self.sink();
                self.spawn(move || {
                    let fetched = connection.fetch_icons(&hashes).unwrap_or_default();
                    let mut stored = HashMap::new();
                    for hash in &hashes {
                        if let Some(bytes) = fetched.get(hash)
                            && cache.store(hash, bytes).is_some()
                        {
                            stored.insert(hash.clone(), Vec::new());
                        }
                    }
                    sink.post(CoreEvent::Remote(RemoteEvent::IconsFetched {
                        source_key: keys.join("\n"),
                        hashes,
                        icons: stored,
                    }));
                });
            }
        }
    }

    pub(crate) fn on_icons_fetched(
        &mut self,
        source_keys: &str,
        hashes: &[String],
        stored: HashMap<String, Vec<u8>>,
    ) {
        for hash in hashes {
            self.icons.in_flight.remove(hash);
            if !stored.contains_key(hash) && !source_keys.is_empty() {
                // Remembered for this connection; the row keeps its letter.
                for key in source_keys.split('\n') {
                    self.icons
                        .failed
                        .entry(key.to_owned())
                        .or_default()
                        .insert(hash.clone());
                }
            }
        }
        let keep: HashSet<String> = self.icons.referenced.values().flatten().cloned().collect();
        let limit = self.remote_state.icon_cache_bytes;
        let cache = Arc::clone(&self.ports.icon_cache);
        if !stored.is_empty() || source_keys.is_empty() {
            self.icons.revision += 1;
            self.mark(CoreChanges {
                icons: true,
                ..CoreChanges::default()
            });
        }
        self.spawn(move || cache.evict(limit, &keep));
    }

    pub(crate) fn clear_icon_cache(&mut self) {
        let cache = Arc::clone(&self.ports.icon_cache);
        cache.clear();
        self.icons.revision += 1;
        self.mark(CoreChanges {
            icons: true,
            remote_hosts: true,
            ..CoreChanges::default()
        });
        self.toast("remoteIconCacheCleared", vec![], ToastTone::Success);
    }
}
