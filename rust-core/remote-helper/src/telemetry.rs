//! The `telemetry` subscription: samples processtree at the subscribed cadence and publishes
//! `telemetry.snapshot` payloads.
//!
//! Topology (identities, parents, names, commands, icons) is sent only when it changed since
//! the last sample sent; metrics are columnar integer arrays indexed like that topology. A
//! metric equal to the previously sent value is sent as `null` when that is shorter. The
//! helper serializes a sample only when the client has credit, so a slow link lowers the
//! rate instead of queueing; the newest unsent sample replaces older ones.
use devmil_remote::server::Publisher;
use processlama_telemetry::backend::{ProcessIdentity, ProcessRecord, ProcessStatus};
use processlama_telemetry::{TelemetryEngine, TelemetrySample};
use processlama_wire::contract;
use serde_json::{Map, Value, json};
use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

/// String bounds of topology fields, in bytes.
const USER_BYTES: usize = 64;
const NAME_BYTES: usize = 256;
const PATH_BYTES: usize = 1024;
const COMMAND_BYTES: usize = 2048;
const PLATFORM_BYTES: usize = 32;

/// Metric columns, in wire order.
pub const METRICS: [&str; 19] = [
    "cpu",
    "gpu",
    "rss",
    "vmem",
    "cpuTimeMs",
    "threads",
    "files",
    "nice",
    "prio",
    "status",
    "netIn",
    "netOut",
    "netInTotal",
    "netOutTotal",
    "ioRead",
    "ioWrite",
    "ioReadTotal",
    "ioWriteTotal",
    "ioAvail",
];

/// processtree identities are not `Hash`; maps key by pid and start time.
type Key = (i32, u64);

fn key(identity: &ProcessIdentity) -> Key {
    (identity.pid, identity.start_time_unix_ms)
}

fn bounded(text: &str, max: usize) -> String {
    if text.len() <= max {
        return text.to_owned();
    }
    let mut end = max;
    while !text.is_char_boundary(end) {
        end -= 1;
    }
    text[..end].to_owned()
}

fn clamp_i64(value: u64) -> i64 {
    i64::try_from(value.min(1 << 53)).unwrap_or(1 << 53)
}

fn rate(value: f64) -> i64 {
    if value.is_finite() && value > 0.0 {
        (value.round() as i64).min(1 << 53)
    } else {
        0
    }
}

fn tenths(value: f64) -> i64 {
    if value.is_finite() && value > 0.0 {
        ((value * 10.0).round() as i64).min(1 << 53)
    } else {
        0
    }
}

fn status_index(status: ProcessStatus) -> i64 {
    match status {
        ProcessStatus::Running => 0,
        ProcessStatus::Sleeping => 1,
        ProcessStatus::Stopped => 2,
        ProcessStatus::Zombie => 3,
        ProcessStatus::Unknown => 4,
    }
}

fn metrics(record: &ProcessRecord) -> [i64; 19] {
    [
        tenths(record.cpu_percent),
        tenths(record.gpu_percent),
        clamp_i64(record.rss_bytes),
        clamp_i64(record.virtual_memory_bytes),
        clamp_i64(record.cpu_time_nanos / 1_000_000),
        i64::from(record.thread_count),
        i64::from(record.open_file_count),
        i64::from(record.nice),
        i64::from(record.priority),
        status_index(record.status),
        rate(record.network_in_bytes_per_second),
        rate(record.network_out_bytes_per_second),
        clamp_i64(record.total_network_in_bytes),
        clamp_i64(record.total_network_out_bytes),
        rate(record.storage_read_bytes_per_second),
        rate(record.storage_write_bytes_per_second),
        clamp_i64(record.total_storage_read_bytes),
        clamp_i64(record.total_storage_write_bytes),
        i64::from(record.storage_io_available),
    ]
}

/// The static fields of one row, as sent in a topology.
#[derive(Clone, PartialEq, Eq, Hash, Default)]
struct StaticRow {
    ppid: i32,
    uid: u32,
    user: String,
    name: String,
    exe: String,
    cmd: String,
    bundle: String,
    icon: Option<String>,
}

impl StaticRow {
    fn of(record: &ProcessRecord, icon: Option<String>) -> Self {
        Self {
            ppid: record.ppid,
            uid: record.uid,
            user: bounded(&record.user, USER_BYTES),
            name: bounded(&record.name, NAME_BYTES),
            exe: bounded(&record.executable_path, PATH_BYTES),
            cmd: bounded(&record.command_line, COMMAND_BYTES),
            bundle: bounded(&record.app_bundle_path, PATH_BYTES),
            icon,
        }
    }
}

/// Resolves a record's icon to a content hash.
pub trait IconHasher: Send + Sync {
    fn icon_hash(&self, record: &ProcessRecord) -> Option<String>;

    /// Lets queued icons finish, up to `timeout`, so a first sample carries them.
    fn settle(&self, _timeout: Duration) {}
}

/// How long the first sample of a subscription waits for its icons.
const FIRST_SAMPLE_ICON_WAIT: Duration = Duration::from_millis(500);

/// The first samples of a subscription come this fast, so names and icons the
/// engine resolves in the background reach a new tab quickly.
const WARM_UP_INTERVAL: Duration = Duration::from_millis(250);
const WARM_UP_SAMPLES: u32 = 4;

#[cfg(test)]
pub struct NoIcons;

#[cfg(test)]
impl IconHasher for NoIcons {
    fn icon_hash(&self, _record: &ProcessRecord) -> Option<String> {
        None
    }
}

/// Turns samples into `telemetry.snapshot` payloads for one subscription.
#[derive(Default)]
pub struct SampleEncoder {
    /// processtree's topology version of [`Self::rows`].
    engine_topology: Option<u64>,
    /// The version the client knows; bumps when identities, parents or static fields change.
    wire_version: u64,
    sent_any: bool,
    rows: Vec<ProcessIdentity>,
    parents: Vec<i64>,
    statics: Vec<StaticRow>,
    statics_hash: u64,
    /// Metrics of the last sample sent, aligned with `rows`.
    baseline: Option<Vec<[i64; 19]>>,
}

impl SampleEncoder {
    /// The processtree topology version to request.
    pub fn known_engine_topology(&self) -> Option<u64> {
        self.engine_topology
    }

    /// Encodes a sample. Call only when the payload will be published.
    pub fn encode(&mut self, sample: &TelemetrySample, icons: &dyn IconHasher) -> Value {
        let mut structure_changed = false;
        if let Some(links) = &sample.topology {
            let index: HashMap<Key, usize> = links
                .iter()
                .enumerate()
                .map(|(position, link)| (key(&link.identity), position))
                .collect();
            let rows: Vec<ProcessIdentity> = links.iter().map(|link| link.identity).collect();
            let parents: Vec<i64> = links
                .iter()
                .map(|link| {
                    link.parent
                        .and_then(|parent| index.get(&key(&parent)).copied())
                        .map_or(-1, |position| position as i64)
                })
                .collect();
            structure_changed = rows != self.rows || parents != self.parents;
            self.rows = rows;
            self.parents = parents;
        }
        self.engine_topology = sample.topology_version.or(self.engine_topology);

        let records: HashMap<Key, &ProcessRecord> = sample
            .snapshot
            .processes
            .iter()
            .map(|record| (key(&record.identity), record))
            .collect();
        let statics: Vec<StaticRow> = self
            .rows
            .iter()
            .map(|identity| {
                records
                    .get(&key(identity))
                    .map(|record| StaticRow::of(record, icons.icon_hash(record)))
                    .unwrap_or_default()
            })
            .collect();
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        statics.hash(&mut hasher);
        let statics_hash = hasher.finish();
        let send_topology =
            !self.sent_any || structure_changed || statics_hash != self.statics_hash;
        if send_topology {
            self.wire_version += 1;
            self.statics = statics;
            self.statics_hash = statics_hash;
            self.baseline = None;
        }

        let current: Vec<[i64; 19]> = self
            .rows
            .iter()
            .map(|identity| {
                records
                    .get(&key(identity))
                    .map_or([0; 19], |record| metrics(record))
            })
            .collect();
        let mut columns = Map::new();
        for (column, name) in METRICS.iter().enumerate() {
            let values: Vec<Value> = current
                .iter()
                .enumerate()
                .map(|(row, values)| {
                    let value = values[column];
                    let unchanged = self
                        .baseline
                        .as_ref()
                        .and_then(|baseline| baseline.get(row))
                        .is_some_and(|previous| previous[column] == value);
                    // `null` only where it is shorter than the number it stands for.
                    if unchanged && !(-99..=999).contains(&value) {
                        Value::Null
                    } else {
                        json!(value)
                    }
                })
                .collect();
            columns.insert((*name).to_owned(), Value::Array(values));
        }
        self.baseline = Some(current);
        self.sent_any = true;

        let topology = if send_topology {
            let column = |f: &dyn Fn(&StaticRow) -> Value| -> Value {
                Value::Array(self.statics.iter().map(f).collect())
            };
            json!({
                "pid": self.rows.iter().map(|identity| identity.pid).collect::<Vec<_>>(),
                "start": self.rows.iter().map(|identity| clamp_i64(identity.start_time_unix_ms)).collect::<Vec<_>>(),
                "parent": self.parents,
                "ppid": column(&|row| json!(row.ppid)),
                "uid": column(&|row| json!(row.uid)),
                "user": column(&|row| json!(row.user)),
                "name": column(&|row| json!(row.name)),
                "exe": column(&|row| json!(row.exe)),
                "cmd": column(&|row| json!(row.cmd)),
                "bundle": column(&|row| json!(row.bundle)),
                "icon": column(&|row| json!(row.icon)),
            })
        } else {
            Value::Null
        };
        json!({
            "capturedAtMs": clamp_i64(sample.snapshot.captured_at_unix_ms),
            "platform": bounded(&sample.snapshot.platform, PLATFORM_BYTES),
            "topologyVersion": self.wire_version,
            "topology": topology,
            "metrics": columns,
            "localPorts": self.rows.iter().map(|identity| records.get(&key(identity)).and_then(|r| r.local_ports.as_ref())).collect::<Vec<_>>(),
            "listeningPorts": self.rows.iter().map(|identity| records.get(&key(identity)).and_then(|r| r.listening_ports.as_ref())).collect::<Vec<_>>(),
        })
    }
}

/// How often the stream samples; `None` sends heartbeats only.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Cadence {
    pub cadence_ms: Option<u64>,
    pub polling_ms: u64,
}

impl Cadence {
    fn clamp(value: u64) -> u64 {
        value.clamp(
            contract::MIN_CADENCE_MS as u64,
            contract::MAX_CADENCE_MS as u64,
        )
    }

    /// Reads `{cadenceMs, pollingMs}`.
    pub fn parse(arguments: &Map<String, Value>) -> Option<Self> {
        let cadence_ms = match arguments.get("cadenceMs")? {
            Value::Null => None,
            value => Some(Self::clamp(value.as_u64()?)),
        };
        let polling_ms = Self::clamp(arguments.get("pollingMs")?.as_u64()?);
        Some(Self {
            cadence_ms,
            polling_ms,
        })
    }
}

struct Control {
    cadence: Cadence,
    changed: bool,
    stopped: bool,
}

/// One running telemetry subscription.
pub struct TelemetryStream {
    control: Mutex<Control>,
    wake: Condvar,
}

impl TelemetryStream {
    pub fn start(
        publisher: Publisher,
        cadence: Cadence,
        icon_cache: Option<std::path::PathBuf>,
        icons: Arc<dyn IconHasher>,
    ) -> Arc<Self> {
        let stream = Arc::new(Self {
            control: Mutex::new(Control {
                cadence,
                changed: true,
                stopped: false,
            }),
            wake: Condvar::new(),
        });
        let running = Arc::clone(&stream);
        std::thread::spawn(move || running.run(&publisher, icon_cache, icons.as_ref()));
        stream
    }

    pub fn set_cadence(&self, cadence: Cadence) {
        let mut control = devmil_remote::server::lock(&self.control);
        control.cadence = cadence;
        control.changed = true;
        self.wake.notify_all();
    }

    pub fn stop(&self) {
        let mut control = devmil_remote::server::lock(&self.control);
        control.stopped = true;
        self.wake.notify_all();
    }

    pub fn is_stopped(&self) -> bool {
        devmil_remote::server::lock(&self.control).stopped
    }

    fn wait(&self, timeout: Duration) {
        let control = devmil_remote::server::lock(&self.control);
        if control.stopped || control.changed {
            return;
        }
        let _ = self
            .wake
            .wait_timeout(control, timeout)
            .unwrap_or_else(std::sync::PoisonError::into_inner);
    }

    fn run(
        &self,
        publisher: &Publisher,
        icon_cache: Option<std::path::PathBuf>,
        icons: &dyn IconHasher,
    ) {
        let initial = devmil_remote::server::lock(&self.control).cadence;
        let mut engine = TelemetryEngine::new(initial.polling_ms, icon_cache);
        let mut encoder = SampleEncoder::default();
        let mut unsent: Option<TelemetrySample> = None;
        let mut first = true;
        let mut warm_up = WARM_UP_SAMPLES;
        let mut next_due = Instant::now();
        loop {
            if publisher.is_closed() {
                break;
            }
            let cadence = {
                let mut control = devmil_remote::server::lock(&self.control);
                if control.stopped {
                    break;
                }
                if control.changed {
                    control.changed = false;
                    // A new cadence samples right away, so a tab coming to the front is fresh.
                    next_due = Instant::now();
                }
                control.cadence
            };
            if cadence.cadence_ms.is_none() {
                // Paused: heartbeats only, not even a sample taken before.
                unsent = None;
            }
            if unsent.is_some() && publisher.has_credit() {
                let sample = unsent.take().expect("checked above");
                if first {
                    // Queue every icon, then give the worker a moment, so the first
                    // topology a tab shows already names them.
                    first = false;
                    for record in &sample.snapshot.processes {
                        icons.icon_hash(record);
                    }
                    icons.settle(FIRST_SAMPLE_ICON_WAIT);
                }
                let payload = encoder.encode(&sample, icons);
                if !publisher.publish(payload) {
                    break;
                }
                continue;
            }
            let Some(cadence_ms) = cadence.cadence_ms else {
                self.wait(Duration::from_millis(500));
                continue;
            };
            let now = Instant::now();
            if now >= next_due {
                match engine.sample(cadence.polling_ms, encoder.known_engine_topology()) {
                    Ok(sample) => unsent = Some(sample),
                    Err(_) => unsent = None,
                }
                let interval = Duration::from_millis(cadence_ms);
                next_due = now
                    + if warm_up > 0 {
                        warm_up -= 1;
                        interval.min(WARM_UP_INTERVAL)
                    } else {
                        interval
                    };
                continue;
            }
            let remaining = next_due - now;
            if unsent.is_some() {
                publisher.wait_for_credit(remaining);
            } else {
                self.wait(remaining);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use processlama_telemetry::backend::{
        PROCESS_TREE_FORMAT, ProcessSnapshot, ProcessTreeCache, ProcessTreeSample,
    };

    fn sample(
        cache: &mut ProcessTreeCache,
        known: Option<u64>,
        mut records: Vec<ProcessRecord>,
    ) -> TelemetrySample {
        let topology = cache.update(&mut records);
        processlama_telemetry::versioned_sample(
            ProcessTreeSample {
                snapshot: ProcessSnapshot {
                    format: PROCESS_TREE_FORMAT.to_owned(),
                    version: 1,
                    captured_at_unix_ms: 1,
                    platform: "test".to_owned(),
                    processes: records,
                },
                topology: Some(topology),
            },
            known,
        )
    }

    #[test]
    fn topology_is_sent_once_and_again_after_static_changes() {
        let mut cache = ProcessTreeCache::default();
        let mut encoder = SampleEncoder::default();
        let mut records = vec![
            ProcessRecord::synthetic(1, 0, "init"),
            ProcessRecord::synthetic(2, 1, "worker"),
        ];
        records[1].rss_bytes = 123_456_789;
        let first = encoder.encode(
            &sample(&mut cache, encoder.known_engine_topology(), records.clone()),
            &NoIcons,
        );
        assert_eq!(first["topologyVersion"], 1);
        assert_eq!(first["topology"]["parent"], json!([-1, 0]));
        assert_eq!(first["topology"]["name"], json!(["init", "worker"]));
        assert_eq!(first["metrics"]["rss"][1], 123_456_789);

        records[1].cpu_percent = 12.34;
        let second = encoder.encode(
            &sample(&mut cache, encoder.known_engine_topology(), records.clone()),
            &NoIcons,
        );
        assert_eq!(second["topology"], Value::Null);
        assert_eq!(second["topologyVersion"], 1);
        assert_eq!(second["metrics"]["cpu"][1], 123);
        assert_eq!(
            second["metrics"]["rss"][1],
            Value::Null,
            "unchanged long value"
        );
        assert_eq!(
            second["metrics"]["threads"][1], 0,
            "short values stay numbers"
        );

        records[1].name = "renamed".to_owned();
        let third = encoder.encode(
            &sample(&mut cache, encoder.known_engine_topology(), records.clone()),
            &NoIcons,
        );
        assert_eq!(third["topologyVersion"], 2);
        assert_eq!(third["topology"]["name"][1], "renamed");
        assert_eq!(
            third["metrics"]["rss"][1], 123_456_789,
            "full metrics after topology"
        );

        // A new subscription starts from scratch.
        let mut encoder = SampleEncoder::default();
        let fourth = encoder.encode(
            &sample(&mut cache, encoder.known_engine_topology(), records),
            &NoIcons,
        );
        assert_eq!(fourth["topologyVersion"], 1);
        assert!(fourth["topology"].is_object());
    }

    #[test]
    fn metrics_are_integers_at_display_precision() {
        let mut record = ProcessRecord::synthetic(5, 0, "p");
        record.cpu_percent = std::f64::consts::PI;
        record.network_in_bytes_per_second = 1023.6;
        record.cpu_time_nanos = 2_500_000_000;
        record.storage_io_available = true;
        let values = metrics(&record);
        assert_eq!(values[0], 31);
        assert_eq!(values[4], 2_500);
        assert_eq!(values[10], 1024);
        assert_eq!(values[18], 1);
        assert_eq!(rate(f64::NAN), 0);
        assert_eq!(bounded("ééé", 3), "é");
    }

    #[test]
    fn cadence_is_bounded() {
        let parsed = Cadence::parse(
            json!({"cadenceMs": 10, "pollingMs": 999_999})
                .as_object()
                .unwrap(),
        )
        .unwrap();
        assert_eq!(parsed.cadence_ms, Some(contract::MIN_CADENCE_MS as u64));
        assert_eq!(parsed.polling_ms, contract::MAX_CADENCE_MS as u64);
        let paused = Cadence::parse(
            json!({"cadenceMs": null, "pollingMs": 1000})
                .as_object()
                .unwrap(),
        )
        .unwrap();
        assert_eq!(paused.cadence_ms, None);
        assert!(Cadence::parse(json!({"pollingMs": 1000}).as_object().unwrap()).is_none());
    }
}

#[cfg(test)]
mod golden {
    use super::*;
    use processlama_telemetry::backend::{
        PROCESS_TREE_FORMAT, ProcessSnapshot, ProcessTreeCache, ProcessTreeSample,
    };

    fn records() -> Vec<ProcessRecord> {
        let mut init = ProcessRecord::synthetic(1, 0, "init");
        init.uid = 0;
        init.user = "root".to_owned();
        init.rss_bytes = 12_582_912;
        init.virtual_memory_bytes = 171_048_960;
        init.cpu_time_nanos = 4_200_000_000;
        init.thread_count = 1;
        init.status = ProcessStatus::Sleeping;
        init.identity.start_time_unix_ms = 1_699_000_000_000;
        let mut worker = ProcessRecord::synthetic(42, 1, "worker");
        worker.uid = 1000;
        worker.user = "tester".to_owned();
        worker.executable_path = "/usr/bin/worker".to_owned();
        worker.command_line = "/usr/bin/worker --serve".to_owned();
        worker.cpu_percent = 12.34;
        worker.rss_bytes = 104_857_600;
        worker.virtual_memory_bytes = 2_147_483_648;
        worker.thread_count = 8;
        worker.open_file_count = 23;
        worker.network_in_bytes_per_second = 2048.4;
        worker.total_network_in_bytes = 9_000_000;
        worker.storage_io_available = true;
        worker.identity.start_time_unix_ms = 1_699_000_001_000;
        vec![init, worker]
    }

    fn sample(
        cache: &mut ProcessTreeCache,
        known: Option<u64>,
        mut records: Vec<ProcessRecord>,
        at: u64,
    ) -> TelemetrySample {
        let topology = cache.update(&mut records);
        processlama_telemetry::versioned_sample(
            ProcessTreeSample {
                snapshot: ProcessSnapshot {
                    format: PROCESS_TREE_FORMAT.to_owned(),
                    version: 1,
                    captured_at_unix_ms: at,
                    platform: "linux".to_owned(),
                    processes: records,
                },
                topology: Some(topology),
            },
            known,
        )
    }

    /// The encoder's output is the contract the Dart decoder reads
    /// (`test/remote/telemetry_codec_test.dart` decodes the same file).
    #[test]
    fn encoder_output_matches_the_golden_samples() {
        let mut cache = ProcessTreeCache::default();
        let mut encoder = SampleEncoder::default();
        let mut records = records();
        records[1].local_ports = Some(vec![8080, 51000]);
        records[1].listening_ports = Some(vec![8080]);
        let first = encoder.encode(
            &sample(
                &mut cache,
                encoder.known_engine_topology(),
                records.clone(),
                1_700_000_000_000,
            ),
            &NoIcons,
        );
        records[1].local_ports = Some(vec![9090]);
        records[1].listening_ports = Some(vec![]);
        records[1].cpu_percent = 50.0;
        records[1].network_in_bytes_per_second = 0.0;
        let second = encoder.encode(
            &sample(
                &mut cache,
                encoder.known_engine_topology(),
                records,
                1_700_000_001_000,
            ),
            &NoIcons,
        );
        let actual = json!({"samples": [first, second]});
        let golden: Value = serde_json::from_str(include_str!(
            "../../../fixtures/remote_telemetry_golden.json"
        ))
        .unwrap();
        if std::env::var_os("PROCESSLAMA_UPDATE_GOLDEN").is_some() {
            let path = concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/../../fixtures/remote_telemetry_golden.json"
            );
            std::fs::write(path, serde_json::to_string_pretty(&actual).unwrap() + "\n").unwrap();
            return;
        }
        assert_eq!(actual, golden);
    }
}
