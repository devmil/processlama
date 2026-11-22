//! Decoding of the helper's results and telemetry publications. Every
//! violation is an error; nothing a helper sends is trusted.

use base64::Engine;
use processlama_domain::{
    DetailSection, FileDescriptorInfo, HostCapabilities, HostOperatingSystem, NetworkEndpointInfo,
    NetworkRateSource, NetworkUnavailableReason, ProcessDetail, ProcessIconRef, ProcessIdentity, ProcessRecord,
    ProcessSignal, ProcessSnapshot, ProcessStatus, ProcessTopology, RemoteHelperHello, RemoteHelperTarget,
    RemoteHostFacts, SecurityDetailInfo, SignalOutcome, TaskSummaryInfo, ThreadInfo, ThreadInspectionInfo,
};
use processlama_wire::contract::{ICON_BYTES, ICON_FETCH_BYTES, ICONS_PER_FETCH, PROCESSES_PER_SAMPLE};
use serde_json::{Map, Value, json};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Invalid(pub &'static str);

type Result<T> = std::result::Result<T, Invalid>;

/// An object with exactly `keys`.
fn object<'a>(value: &'a Value, keys: &[&str], what: &'static str) -> Result<&'a Map<String, Value>> {
    let map = value.as_object().ok_or(Invalid(what))?;
    if map.len() != keys.len() || !keys.iter().all(|key| map.contains_key(*key)) {
        return Err(Invalid(what));
    }
    Ok(map)
}

fn string<'a>(map: &'a Map<String, Value>, key: &str, max: usize, what: &'static str) -> Result<&'a str> {
    let text = map.get(key).and_then(Value::as_str).ok_or(Invalid(what))?;
    if text.chars().count() > max {
        return Err(Invalid(what));
    }
    Ok(text)
}

fn unsigned(map: &Map<String, Value>, key: &str, what: &'static str) -> Result<u64> {
    map.get(key).and_then(Value::as_u64).ok_or(Invalid(what))
}

fn integer(value: &Value, what: &'static str) -> Result<i64> {
    let number = value.as_i64().ok_or(Invalid(what))?;
    if !(-(1_i64 << 53)..=(1_i64 << 53)).contains(&number) {
        return Err(Invalid(what));
    }
    Ok(number)
}

fn boolean(map: &Map<String, Value>, key: &str, what: &'static str) -> Result<bool> {
    map.get(key).and_then(Value::as_bool).ok_or(Invalid(what))
}

fn is_lower_hex(text: &str, length: usize) -> bool {
    text.len() == length && text.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

fn column<'a>(map: &'a Map<String, Value>, key: &str, length: usize) -> Result<&'a Vec<Value>> {
    let values = map.get(key).and_then(Value::as_array).ok_or(Invalid("column"))?;
    if values.len() != length {
        return Err(Invalid("column"));
    }
    Ok(values)
}

/// Metric columns of `telemetry.snapshot`, in wire order.
pub const METRIC_COLUMNS: [&str; 19] = [
    "cpu", "gpu", "rss", "vmem", "cpuTimeMs", "threads", "files", "nice", "prio", "status", "netIn", "netOut",
    "netInTotal", "netOutTotal", "ioRead", "ioWrite", "ioReadTotal", "ioWriteTotal", "ioAvail",
];
const TOPOLOGY_COLUMNS: [&str; 11] = ["pid", "start", "parent", "ppid", "uid", "user", "name", "exe", "cmd", "bundle", "icon"];

#[derive(Clone)]
struct StaticRow {
    identity: ProcessIdentity,
    ppid: i32,
    uid: u32,
    user: String,
    name: String,
    executable: String,
    command: String,
    bundle: String,
    icon: Option<String>,
}

/// Decodes the publications of one telemetry subscription. Keeps the
/// topology between samples and fills `null` metrics from the previous one.
#[derive(Default)]
pub struct TelemetryDecoder {
    version: Option<u64>,
    rows: Vec<StaticRow>,
    topology: Option<Arc<ProcessTopology>>,
    metrics: Vec<[i64; 19]>,
}

impl TelemetryDecoder {
    pub fn decode(&mut self, data: &Value) -> Result<ProcessSnapshot> {
        let map = data.as_object().ok_or(Invalid("sample"))?;
        let mut keys = vec!["capturedAtMs", "platform", "topologyVersion", "topology", "metrics"];
        if map.contains_key("localPorts") {
            keys.push("localPorts");
        }
        if map.contains_key("listeningPorts") {
            keys.push("listeningPorts");
        }
        let sample = object(data, &keys, "sample")?;
        let version = unsigned(sample, "topologyVersion", "version")?;
        let mut fresh = false;
        match sample.get("topology") {
            Some(Value::Null) | None => {
                if Some(version) != self.version {
                    return Err(Invalid("topology version"));
                }
            }
            Some(topology) => {
                self.read_topology(topology, version)?;
                fresh = true;
            }
        }
        let metrics_map = object(&sample["metrics"], &METRIC_COLUMNS, "metrics")?;
        let length = self.rows.len();
        let columns: Vec<&Vec<Value>> = METRIC_COLUMNS
            .iter()
            .map(|name| column(metrics_map, name, length))
            .collect::<Result<_>>()?;
        let mut metrics = Vec::with_capacity(length);
        for row in 0..length {
            let mut values = [0_i64; 19];
            for (index, column) in columns.iter().enumerate() {
                values[index] = match &column[row] {
                    Value::Null => {
                        if fresh || self.metrics.len() != length {
                            return Err(Invalid("null without a previous sample"));
                        }
                        self.metrics[row][index]
                    }
                    value => integer(value, "metric")?,
                };
            }
            metrics.push(values);
        }
        let ports = |name: &str| -> Result<Option<Vec<Option<Arc<[u16]>>>>> {
            let Some(_) = sample.get(name) else {
                return Ok(None);
            };
            let values = column(sample, name, length)?;
            values
                .iter()
                .map(|value| match value {
                    Value::Null => Ok(None),
                    Value::Array(ports) if ports.len() <= 65535 => ports
                        .iter()
                        .map(|port| {
                            port.as_u64()
                                .filter(|port| (1..=65535).contains(port))
                                .map(|port| port as u16)
                                .ok_or(Invalid("ports"))
                        })
                        .collect::<Result<Vec<u16>>>()
                        .map(|ports| Some(Arc::from(ports))),
                    _ => Err(Invalid("ports")),
                })
                .collect::<Result<Vec<_>>>()
                .map(Some)
        };
        let local = ports("localPorts")?;
        let listening = ports("listeningPorts")?;
        let platform = string(sample, "platform", 32, "platform")?.to_owned();
        let generated = unsigned(sample, "capturedAtMs", "capturedAt")?;
        let processes = (0..length)
            .map(|row| {
                let mut record = record(&self.rows[row], &metrics[row]);
                record.local_ports = local.as_ref().and_then(|ports| ports[row].clone());
                record.listening_ports = listening.as_ref().and_then(|ports| ports[row].clone());
                Arc::new(record)
            })
            .collect();
        self.metrics = metrics;
        Ok(ProcessSnapshot {
            generated_at_unix_ms: generated,
            platform,
            processes,
            error: None,
            topology: self.topology.clone(),
        })
    }

    fn read_topology(&mut self, value: &Value, version: u64) -> Result<()> {
        let map = object(value, &TOPOLOGY_COLUMNS, "topology")?;
        let pids = map.get("pid").and_then(Value::as_array).ok_or(Invalid("topology"))?;
        if pids.len() > PROCESSES_PER_SAMPLE {
            return Err(Invalid("topology size"));
        }
        let length = pids.len();
        let mut columns = HashMap::new();
        for name in TOPOLOGY_COLUMNS {
            columns.insert(name, column(map, name, length)?);
        }
        let int = |name: &str, row: usize| integer(&columns[name][row], "topology integer");
        let text = |name: &str, row: usize, max: usize| -> Result<String> {
            let value = columns[name][row].as_str().ok_or(Invalid("topology text"))?;
            if value.chars().count() > max {
                return Err(Invalid("topology text"));
            }
            Ok(value.to_owned())
        };
        let mut rows = Vec::with_capacity(length);
        let mut seen = HashSet::with_capacity(length);
        for row in 0..length {
            let pid = int("pid", row)?;
            let start = int("start", row)?;
            if pid < 0 || start < 0 || pid > i64::from(i32::MAX) {
                return Err(Invalid("identity"));
            }
            let identity = ProcessIdentity::new(pid as i32, start as u64);
            if !seen.insert(identity) {
                return Err(Invalid("duplicate identity"));
            }
            let icon = match &columns["icon"][row] {
                Value::Null => None,
                Value::String(hash) if is_lower_hex(hash, 64) => Some(hash.clone()),
                _ => return Err(Invalid("icon")),
            };
            rows.push(StaticRow {
                identity,
                ppid: i32::try_from(int("ppid", row)?).map_err(|_| Invalid("ppid"))?,
                uid: u32::try_from(int("uid", row)?).map_err(|_| Invalid("uid"))?,
                user: text("user", row, 64)?,
                name: text("name", row, 256)?,
                executable: text("exe", row, 1024)?,
                command: text("cmd", row, 2048)?,
                bundle: text("bundle", row, 1024)?,
                icon,
            });
        }
        let mut parents = HashMap::with_capacity(length);
        for row in 0..length {
            let parent = int("parent", row)?;
            if parent < -1 || parent >= length as i64 || parent == row as i64 {
                return Err(Invalid("parent"));
            }
            parents.insert(rows[row].identity, (parent >= 0).then(|| rows[parent as usize].identity));
        }
        let order: Vec<ProcessIdentity> = rows.iter().map(|row| row.identity).collect();
        self.topology = Some(Arc::new(ProcessTopology::new(Some(version), parents, &order)));
        self.rows = rows;
        self.version = Some(version);
        Ok(())
    }
}

fn record(row: &StaticRow, m: &[i64; 19]) -> ProcessRecord {
    let unsigned = |value: i64| value.max(0) as u64;
    let status = match m[9] {
        0 => ProcessStatus::Running,
        1 => ProcessStatus::Sleeping,
        2 => ProcessStatus::Stopped,
        3 => ProcessStatus::Zombie,
        _ => ProcessStatus::Unknown,
    };
    ProcessRecord {
        pid: row.identity.pid,
        ppid: row.ppid,
        uid: row.uid,
        user: row.user.clone(),
        status,
        rss_bytes: unsigned(m[2]),
        virtual_memory_bytes: unsigned(m[3]),
        cpu_time_nanos: unsigned(m[4]).saturating_mul(1_000_000),
        thread_count: m[5].clamp(0, i64::from(u32::MAX)) as u32,
        open_file_count: m[6].clamp(0, i64::from(u32::MAX)) as u32,
        local_ports: None,
        listening_ports: None,
        nice: m[7].clamp(i64::from(i32::MIN), i64::from(i32::MAX)) as i32,
        priority: m[8].clamp(i64::from(i32::MIN), i64::from(i32::MAX)) as i32,
        cpu_usage: m[0] as f64 / 10.0,
        gpu_usage: m[1] as f64 / 10.0,
        network_in_bytes_per_second: m[10] as f64,
        network_out_bytes_per_second: m[11] as f64,
        total_network_in_bytes: unsigned(m[12]),
        total_network_out_bytes: unsigned(m[13]),
        storage_read_bytes_per_second: m[14] as f64,
        storage_write_bytes_per_second: m[15] as f64,
        total_storage_read_bytes: unsigned(m[16]),
        total_storage_write_bytes: unsigned(m[17]),
        storage_io_available: m[18] != 0,
        tree_cpu_usage: m[0] as f64 / 10.0,
        tree_gpu_usage: m[1] as f64 / 10.0,
        tree_rss_bytes: unsigned(m[2]),
        tree_network_in_bytes_per_second: m[10] as f64,
        tree_network_out_bytes_per_second: m[11] as f64,
        tree_storage_read_bytes_per_second: m[14] as f64,
        tree_storage_write_bytes_per_second: m[15] as f64,
        tree_storage_io_available: m[18] != 0,
        descendant_count: 0,
        start_time_unix_ms: row.identity.start_time_unix_ms,
        name: row.name.clone(),
        executable_path: row.executable.clone(),
        command_line: row.command.clone(),
        app_bundle_path: row.bundle.clone(),
        icon: row.icon.clone().map(ProcessIconRef::Remote),
    }
}

pub fn telemetry_arguments(cadence_ms: Option<u32>, polling_ms: u32) -> Value {
    json!({"cadenceMs": cadence_ms, "pollingMs": polling_ms})
}

fn section<T>(value: &Value, decode: impl FnOnce(&Value) -> Result<T>) -> Result<DetailSection<T>> {
    let map = object(value, &["state", "reason", "value"], "section")?;
    let state = map.get("state").and_then(Value::as_str).ok_or(Invalid("section"))?;
    if state == "available" {
        if !map["reason"].is_null() {
            return Err(Invalid("section"));
        }
        return Ok(DetailSection::Available(decode(&map["value"])?));
    }
    let reason = map["reason"].as_str().filter(|r| r.chars().count() <= 256).ok_or(Invalid("section"))?;
    if !map["value"].is_null() {
        return Err(Invalid("section"));
    }
    let reason = reason.to_owned();
    match state {
        "restricted" => Ok(DetailSection::Restricted(reason)),
        "unsupported" => Ok(DetailSection::Unsupported(reason)),
        "notFound" => Ok(DetailSection::NotFound(reason)),
        _ => Err(Invalid("section state")),
    }
}

fn list(value: &Value) -> Result<&Vec<Value>> {
    value.as_array().filter(|items| items.len() <= 4096).ok_or(Invalid("list"))
}

fn port(map: &Map<String, Value>, key: &str) -> Result<u16> {
    u16::try_from(unsigned(map, key, "port")?).map_err(|_| Invalid("port"))
}

/// Decodes a `process.detail` result.
pub fn decode_detail(value: &Value) -> Result<ProcessDetail> {
    let map = object(value, &["pid", "start", "files", "sockets", "threads", "security"], "detail")?;
    let pid = i32::try_from(unsigned(map, "pid", "pid")?).map_err(|_| Invalid("pid"))?;
    let identity = ProcessIdentity::new(pid, unsigned(map, "start", "start")?);
    let files = section(&map["files"], |value| {
        list(value)?
            .iter()
            .map(|entry| {
                let file = object(entry, &["fd", "kind", "path"], "file")?;
                let fd = file["fd"].as_i64().and_then(|fd| i32::try_from(fd).ok()).ok_or(Invalid("fd"))?;
                Ok(FileDescriptorInfo {
                    fd,
                    kind: string(file, "kind", 64, "kind")?.to_owned(),
                    path: string(file, "path", 1024, "path")?.to_owned(),
                })
            })
            .collect()
    })?;
    let sockets = section(&map["sockets"], |value| {
        list(value)?
            .iter()
            .map(|entry| {
                let socket = object(
                    entry,
                    &["protocol", "localAddress", "localPort", "localApproximate", "remoteAddress", "remotePort", "remoteApproximate", "state"],
                    "socket",
                )?;
                Ok(NetworkEndpointInfo {
                    protocol: string(socket, "protocol", 32, "socket")?.to_owned(),
                    local_address: string(socket, "localAddress", 128, "socket")?.to_owned(),
                    local_port: port(socket, "localPort")?,
                    local_address_approximate: boolean(socket, "localApproximate", "socket")?,
                    remote_address: string(socket, "remoteAddress", 128, "socket")?.to_owned(),
                    remote_port: port(socket, "remotePort")?,
                    remote_address_approximate: boolean(socket, "remoteApproximate", "socket")?,
                    state: string(socket, "state", 32, "socket")?.to_owned(),
                })
            })
            .collect()
    })?;
    let threads = section(&map["threads"], |value| {
        let inspection = object(value, &["summary", "threads"], "threads")?;
        let summary = match &inspection["summary"] {
            Value::Null => None,
            value => {
                let summary = object(value, &["threadCount", "machSyscallCount", "rosettaTranslated"], "summary")?;
                Some(TaskSummaryInfo {
                    thread_count: unsigned(summary, "threadCount", "summary")?,
                    mach_syscall_count: unsigned(summary, "machSyscallCount", "summary")?,
                    rosetta_translated: boolean(summary, "rosettaTranslated", "summary")?,
                })
            }
        };
        let threads = list(&inspection["threads"])?
            .iter()
            .map(|entry| {
                let thread = object(entry, &["id", "cpuTenths", "approximate", "state"], "thread")?;
                Ok(ThreadInfo {
                    thread_id: unsigned(thread, "id", "thread")?,
                    cpu_percent: unsigned(thread, "cpuTenths", "thread")? as f64 / 10.0,
                    cpu_percent_approximate: boolean(thread, "approximate", "thread")?,
                    state: string(thread, "state", 32, "thread")?.to_owned(),
                })
            })
            .collect::<Result<_>>()?;
        Ok(ThreadInspectionInfo { summary, threads })
    })?;
    let security = section(&map["security"], |value| {
        let s = object(
            value,
            &[
                "signingStatus", "signingAuthority", "teamId", "bundleId", "entitlementsSummary",
                "entitlementsApproximate", "gatekeeperOrigin", "sandbox", "hardenedRuntime", "architecture",
                "rosettaTranslated",
            ],
            "security",
        )?;
        Ok(SecurityDetailInfo {
            signing_status: string(s, "signingStatus", 128, "security")?.to_owned(),
            signing_authority: string(s, "signingAuthority", 1024, "security")?.to_owned(),
            team_id: string(s, "teamId", 64, "security")?.to_owned(),
            bundle_id: string(s, "bundleId", 256, "security")?.to_owned(),
            entitlements_summary: string(s, "entitlementsSummary", 1024, "security")?.to_owned(),
            entitlements_approximate: boolean(s, "entitlementsApproximate", "security")?,
            gatekeeper_origin: string(s, "gatekeeperOrigin", 256, "security")?.to_owned(),
            sandbox: boolean(s, "sandbox", "security")?,
            hardened_runtime: boolean(s, "hardenedRuntime", "security")?,
            architecture: string(s, "architecture", 64, "security")?.to_owned(),
            rosetta_translated: boolean(s, "rosettaTranslated", "security")?,
        })
    })?;
    Ok(ProcessDetail {
        identity,
        files,
        sockets,
        threads,
        security,
    })
}

pub fn signal_arguments(identity: ProcessIdentity, signal: ProcessSignal) -> Value {
    let signal = match signal {
        ProcessSignal::Terminate => "terminate",
        ProcessSignal::Kill => "kill",
        ProcessSignal::Suspend => "suspend",
        ProcessSignal::Resume => "resume",
    };
    json!({"pid": identity.pid, "start": identity.start_time_unix_ms, "signal": signal})
}

pub fn decode_signal_outcome(value: &Value) -> Result<SignalOutcome> {
    let map = object(value, &["outcome"], "signal")?;
    match string(map, "outcome", 16, "signal")? {
        "sent" => Ok(SignalOutcome::Sent),
        "denied" => Ok(SignalOutcome::Denied),
        "notFound" => Ok(SignalOutcome::NotFound),
        "unknown" => Ok(SignalOutcome::Unknown),
        _ => Err(Invalid("signal outcome")),
    }
}

/// Canonical base64 PNG bytes by hash; only requested hashes are accepted.
pub fn decode_icons(value: &Value, requested: &HashSet<String>) -> Result<HashMap<String, Vec<u8>>> {
    let map = object(value, &["icons"], "icons")?;
    let icons = map["icons"].as_array().filter(|icons| icons.len() <= ICONS_PER_FETCH).ok_or(Invalid("icons"))?;
    let engine = base64::engine::general_purpose::STANDARD;
    let mut result = HashMap::new();
    for entry in icons {
        let icon = object(entry, &["sha256", "png"], "icon")?;
        let hash = string(icon, "sha256", 64, "icon")?;
        if !requested.contains(hash) {
            return Err(Invalid("unrequested icon"));
        }
        let encoded = string(icon, "png", ICON_FETCH_BYTES * 2, "icon")?;
        let bytes = engine.decode(encoded).map_err(|_| Invalid("icon encoding"))?;
        if engine.encode(&bytes) != encoded || bytes.len() > ICON_BYTES {
            return Err(Invalid("icon encoding"));
        }
        result.insert(hash.to_owned(), bytes);
    }
    Ok(result)
}

/// The domain hello from the helper's validated hello body.
pub fn hello(body: &Value, build_id: &str) -> Result<RemoteHelperHello> {
    let parsed = processlama_wire::messages::HelloBody::parse(body).map_err(|_| Invalid("hello"))?;
    let target = RemoteHelperTarget::parse(parsed.target.as_str()).ok_or(Invalid("target"))?;
    if !is_lower_hex(&parsed.host_instance_id, 32)
        || !is_lower_hex(&parsed.hostname_hash, 16)
        || !parsed.processtree_revision.bytes().all(|b| b.is_ascii_hexdigit())
    {
        return Err(Invalid("identity"));
    }
    let capabilities = &parsed.capabilities;
    let network_source = NetworkRateSource::parse(capabilities.network.source.as_str()).ok_or(Invalid("network"))?;
    let network_unavailable_reason = match capabilities.network.reason {
        None => None,
        Some(reason) => Some(NetworkUnavailableReason::parse(reason.as_str()).ok_or(Invalid("network"))?),
    };
    Ok(RemoteHelperHello {
        facts: RemoteHostFacts {
            target,
            kernel: parsed.kernel.clone(),
            host_instance_id: parsed.host_instance_id.clone(),
            hostname_hash: parsed.hostname_hash.clone(),
            helper_build_id: build_id.to_owned(),
            compatibility: parsed.compatibility,
            processtree_revision: parsed.processtree_revision.clone(),
            uid: parsed.uid,
        },
        capabilities: HostCapabilities {
            operating_system: if target.os() == "macos" { HostOperatingSystem::Macos } else { HostOperatingSystem::Linux },
            gpu: capabilities.gpu,
            storage_io: capabilities.storage_io,
            network_source,
            network_unavailable_reason,
            signals: capabilities.signals,
            inspector_files: capabilities.inspector_files,
            inspector_sockets: capabilities.inspector_sockets,
            inspector_threads: capabilities.inspector_threads,
            inspector_security: capabilities.inspector_security,
            icons: capabilities.icons,
            hidepid: capabilities.hidepid,
        },
    })
}
