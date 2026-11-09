//! ProcessLama telemetry use cases over processtree.
//!
//! The desktop core's bridge facade and the remote helper both call these
//! functions; neither talks to processtree's engine directly. Bridge and wire
//! types stay with their adapters.

pub mod icons;
mod network_path;

use std::path::PathBuf;
use std::sync::{Mutex, MutexGuard, OnceLock};

pub use network_path::LINUX_NETWORK_SNAPSHOT_PATH;
pub use processtree as backend;

use processtree::{
    EngineConfig, ProcessDetail, ProcessIdentity, ProcessSignal, ProcessSnapshot,
    ProcessTreeEngine, ProcessTreeError, ProcessTreeSample,
};

/// Polling interval of a freshly started engine.
pub const DEFAULT_POLLING_INTERVAL_MS: u64 = 1_000;

/// Edge size of generated process icons.
pub const ICON_TARGET_PX: u32 = 128;

/// One sample with the identity-safe topology the caller is missing.
#[derive(Debug, Clone)]
pub struct TelemetrySample {
    pub snapshot: ProcessSnapshot,
    /// Runtime-only cache token. A new engine receives a distinct version.
    pub topology_version: Option<u64>,
    /// Full parent links on first load or a version mismatch. `None` means the
    /// caller's known version is still current.
    pub topology: Option<Vec<ParentLink>>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ParentLink {
    pub identity: ProcessIdentity,
    pub parent: Option<ProcessIdentity>,
}

/// Engine configuration for a polling interval and icon cache directory.
pub fn engine_config(polling_interval_ms: u64, icon_cache_dir: Option<PathBuf>) -> EngineConfig {
    EngineConfig {
        polling_interval_ms,
        // processtree's default still names the pre-rename service path.
        linux_network_snapshot_path: LINUX_NETWORK_SNAPSHOT_PATH.into(),
        icon_cache_dir,
        icon_target_px: ICON_TARGET_PX,
        // Clients own the chart histories. Retain only the engine's latest
        // point instead of shifting 120 unused samples per process every poll.
        metric_history_len: 1,
        ..EngineConfig::default()
    }
}

/// A processtree engine that restarts when the polling interval changes.
pub struct TelemetryEngine {
    polling_interval_ms: u64,
    icon_cache_dir: Option<PathBuf>,
    engine: ProcessTreeEngine,
}

impl TelemetryEngine {
    pub fn new(polling_interval_ms: u64, icon_cache_dir: Option<PathBuf>) -> Self {
        Self {
            polling_interval_ms,
            engine: ProcessTreeEngine::new(engine_config(
                polling_interval_ms,
                icon_cache_dir.clone(),
            )),
            icon_cache_dir,
        }
    }

    /// Samples every process. Topology is included when `known_topology_version`
    /// is not the engine's current version.
    pub fn sample(
        &mut self,
        polling_interval_ms: u64,
        known_topology_version: Option<u64>,
    ) -> Result<TelemetrySample, ProcessTreeError> {
        if self.polling_interval_ms != polling_interval_ms {
            self.engine.stop();
            *self = Self::new(polling_interval_ms, self.icon_cache_dir.clone());
        }
        self.engine
            .snapshot_with_topology()
            .map(|sample| versioned_sample(sample, known_topology_version))
    }
}

impl Drop for TelemetryEngine {
    fn drop(&mut self) {
        self.engine.stop();
    }
}

/// Applies topology versioning to a raw engine sample.
pub fn versioned_sample(
    sample: ProcessTreeSample,
    known_topology_version: Option<u64>,
) -> TelemetrySample {
    let mut result = TelemetrySample {
        snapshot: sample.snapshot,
        topology_version: None,
        topology: None,
    };
    if let Some(topology) = sample.topology {
        result.topology_version = Some(topology.version);
        if known_topology_version != Some(topology.version) {
            result.topology = Some(
                topology
                    .parents
                    .iter()
                    .map(|link| ParentLink {
                        identity: link.identity,
                        parent: link.parent,
                    })
                    .collect(),
            );
        }
    }
    result
}

static ICON_CACHE_DIR: OnceLock<Option<PathBuf>> = OnceLock::new();

/// Configures the directory the shared engine caches process icons in. Must be
/// called before the first sample; later calls are ignored. `None` disables
/// icons.
pub fn configure_shared_icon_cache(cache_dir: Option<PathBuf>) {
    let _ = ICON_CACHE_DIR.set(cache_dir);
}

fn shared_icon_cache_dir() -> Option<PathBuf> {
    match ICON_CACHE_DIR.get() {
        Some(configured) => configured.clone(),
        None => Some(std::env::temp_dir().join("processlama/process-icons")),
    }
}

/// The process-wide engine the desktop application samples.
pub fn shared_engine() -> MutexGuard<'static, TelemetryEngine> {
    static ENGINE: OnceLock<Mutex<TelemetryEngine>> = OnceLock::new();
    ENGINE
        .get_or_init(|| {
            Mutex::new(TelemetryEngine::new(
                DEFAULT_POLLING_INTERVAL_MS,
                shared_icon_cache_dir(),
            ))
        })
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

/// Per-process network rates from the platform source: the ProcessLama
/// network service on Linux, `nettop` on macOS.
pub fn latest_network_rates(
    polling_interval_ms: u64,
) -> std::collections::HashMap<i32, processtree::network::NetworkRate> {
    processtree::network::latest_network_rates_by_pid_from_path(
        polling_interval_ms,
        std::path::Path::new(LINUX_NETWORK_SNAPSHOT_PATH),
    )
}

/// Inspector sections for one process.
pub fn inspect(identity: ProcessIdentity) -> ProcessDetail {
    processtree::inspect_process(identity)
}

/// Typed outcome of a signal request. A signal is never retried.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SignalOutcome {
    Sent,
    Denied,
    NotFound,
    Unknown,
}

/// Sends `signal` to the process with `identity`.
pub fn send_signal(
    identity: ProcessIdentity,
    signal: ProcessSignal,
) -> Result<(), ProcessTreeError> {
    processtree::signal_process(identity, signal)
}

/// Sends `signal` and classifies the result.
pub fn send_signal_outcome(identity: ProcessIdentity, signal: ProcessSignal) -> SignalOutcome {
    classify_signal_result(&send_signal(identity, signal))
}

fn classify_signal_result(result: &Result<(), ProcessTreeError>) -> SignalOutcome {
    match result {
        Ok(()) => SignalOutcome::Sent,
        Err(ProcessTreeError::ProcessNotFound | ProcessTreeError::ProcessIdentityChanged) => {
            SignalOutcome::NotFound
        }
        Err(ProcessTreeError::ProcessAction(message)) if is_permission_message(message) => {
            SignalOutcome::Denied
        }
        Err(_) => SignalOutcome::Unknown,
    }
}

/// processtree reports a failed `kill` as the operating system's message for
/// its errno. Compare against the exact message of `EPERM`.
fn is_permission_message(message: &str) -> bool {
    #[cfg(unix)]
    {
        message == std::io::Error::from_raw_os_error(EPERM).to_string()
    }
    #[cfg(not(unix))]
    {
        message == std::io::Error::from(std::io::ErrorKind::PermissionDenied).to_string()
    }
}

#[cfg(unix)]
const EPERM: i32 = 1;

#[cfg(test)]
mod tests {
    use super::*;
    use processtree::{PROCESS_TREE_FORMAT, ProcessRecord, ProcessTreeCache};

    pub(crate) fn sample(
        cache: &mut ProcessTreeCache,
        mut processes: Vec<ProcessRecord>,
    ) -> ProcessTreeSample {
        let topology = cache.update(&mut processes);
        ProcessTreeSample {
            snapshot: ProcessSnapshot {
                format: PROCESS_TREE_FORMAT.to_owned(),
                version: 1,
                captured_at_unix_ms: 1,
                platform: "test".to_owned(),
                processes,
            },
            topology: Some(topology),
        }
    }

    #[test]
    fn topology_is_omitted_while_the_known_version_is_current() {
        let mut cache = ProcessTreeCache::default();
        let mut records = vec![
            ProcessRecord::synthetic(1, 0, "root"),
            ProcessRecord::synthetic(2, 1, "child"),
        ];
        let initial = versioned_sample(sample(&mut cache, records.clone()), None);
        assert_eq!(initial.topology.as_ref().unwrap().len(), 2);
        records[1].cpu_percent = 42.0;
        let updated = versioned_sample(
            sample(&mut cache, records.clone()),
            initial.topology_version,
        );
        assert!(updated.topology.is_none());
        assert_eq!(updated.snapshot.processes[1].cpu_percent, 42.0);
        records[0].identity.start_time_unix_ms += 1;
        let reused = versioned_sample(
            sample(&mut cache, records.clone()),
            initial.topology_version,
        );
        assert_ne!(initial.topology_version, reused.topology_version);
        assert_eq!(
            reused.topology.unwrap()[1]
                .parent
                .unwrap()
                .start_time_unix_ms,
            records[0].identity.start_time_unix_ms
        );
    }

    #[test]
    fn engine_reads_the_processlama_network_snapshot() {
        assert_eq!(
            engine_config(1_000, None).linux_network_snapshot_path,
            PathBuf::from(LINUX_NETWORK_SNAPSHOT_PATH)
        );
    }

    #[test]
    fn signal_results_are_classified_without_retry_semantics() {
        assert_eq!(classify_signal_result(&Ok(())), SignalOutcome::Sent);
        assert_eq!(
            classify_signal_result(&Err(ProcessTreeError::ProcessNotFound)),
            SignalOutcome::NotFound
        );
        assert_eq!(
            classify_signal_result(&Err(ProcessTreeError::ProcessIdentityChanged)),
            SignalOutcome::NotFound
        );
        #[cfg(unix)]
        assert_eq!(
            classify_signal_result(&Err(ProcessTreeError::ProcessAction(
                std::io::Error::from_raw_os_error(EPERM).to_string()
            ))),
            SignalOutcome::Denied
        );
        assert_eq!(
            classify_signal_result(&Err(ProcessTreeError::ProcessAction("other".into()))),
            SignalOutcome::Unknown
        );
    }

    #[cfg(unix)]
    #[test]
    fn signal_outcome_matches_operating_system_permissions() {
        let init = processtree::enumerate_processes()
            .unwrap()
            .into_iter()
            .find(|record| record.pid() == 1);
        let Some(init) = init else { return };
        let expected = match rustix::process::kill_process(
            rustix::process::Pid::INIT,
            rustix::process::Signal::CONT,
        ) {
            Ok(()) => SignalOutcome::Sent,
            Err(rustix::io::Errno::PERM) => SignalOutcome::Denied,
            Err(error) => panic!("unexpected native resume result: {error}"),
        };
        assert_eq!(
            send_signal_outcome(init.identity, ProcessSignal::Resume),
            expected
        );
    }
}

#[cfg(all(test, target_os = "linux"))]
mod network_snapshot_tests {
    use super::*;
    use processtree::ProcessTreeEngine;
    use std::path::{Path, PathBuf};
    use std::time::{Duration, SystemTime, UNIX_EPOCH};

    fn now_ms() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64
    }

    fn write_synthetic_snapshot(path: &Path, pid: u32, bytes: u64) {
        let contents = format!(
            r#"{{"schema":1,"captured_at_unix_ms":{},"processes":[{{"pid":{pid},"bytes_in":{bytes},"bytes_out":{bytes}}}]}}"#,
            now_ms()
        );
        let temporary = path.with_extension("tmp");
        std::fs::write(&temporary, contents).unwrap();
        std::fs::rename(temporary, path).unwrap();
    }

    /// Runs against the installed network service when its snapshot is fresh,
    /// otherwise against a synthetic snapshot in a temporary directory.
    /// `cargo test -- --ignored network_snapshot_live`
    #[test]
    #[ignore = "reads live process telemetry"]
    fn network_snapshot_live() {
        let service_path = PathBuf::from(LINUX_NETWORK_SNAPSHOT_PATH);
        let service_is_fresh = std::fs::metadata(&service_path)
            .and_then(|metadata| metadata.modified())
            .ok()
            .and_then(|modified| modified.elapsed().ok())
            .is_some_and(|age| age <= Duration::from_secs(5));
        let synthetic_dir = std::env::temp_dir().join(format!(
            "processlama-network-snapshot-{}",
            std::process::id()
        ));
        let mut config = engine_config(500, None);
        if !service_is_fresh {
            std::fs::create_dir_all(&synthetic_dir).unwrap();
            config.linux_network_snapshot_path = synthetic_dir.join("network.json");
        }
        let snapshot_path = config.linux_network_snapshot_path.clone();
        let engine = ProcessTreeEngine::new(config);
        engine.start().unwrap();
        let mut observed = false;
        for round in 0..20u64 {
            if !service_is_fresh {
                write_synthetic_snapshot(&snapshot_path, std::process::id(), round * 100_000);
            }
            let snapshot = engine.snapshot().unwrap();
            observed = snapshot.processes.iter().any(|record| {
                record.network_in_bytes_per_second > 0.0
                    || record.network_out_bytes_per_second > 0.0
            });
            if observed {
                break;
            }
            std::thread::sleep(Duration::from_millis(600));
        }
        engine.stop();
        let _ = std::fs::remove_dir_all(&synthetic_dir);
        assert!(
            observed,
            "no network rates read from {}",
            snapshot_path.display()
        );
    }
}
