//! Snapshot documents: `*.processlama-snapshot.json`.

use crate::process::{ProcessIconRef, ProcessRecord, ProcessSnapshot, ProcessStatus};
use serde_json::{Map, Value, json};
use std::collections::BTreeMap;
use std::sync::Arc;

pub const SNAPSHOT_EXTENSION: &str = ".processlama-snapshot.json";
/// Version 2 adds the remote host and embedded icons.
pub const CURRENT_SCHEMA_VERSION: u64 = 2;

/// The remote host a snapshot was taken on.
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct SnapshotHost {
    pub display_name: String,
    pub alias: String,
    pub operating_system: String,
    pub architecture: String,
}

#[derive(Clone, Debug)]
pub struct SnapshotDocument {
    pub schema_version: u64,
    pub exported_at_unix_ms: u64,
    pub source: String,
    pub display_name: Option<String>,
    pub host: Option<SnapshotHost>,
    /// Base64 PNG icons by SHA-256, for remote snapshots.
    pub icons: BTreeMap<String, String>,
    pub snapshot: ProcessSnapshot,
}

/// A saved snapshot as the sidebar lists it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SnapshotEntry {
    pub path: String,
    pub generated_at_unix_ms: u64,
    pub process_count: usize,
    pub platform: String,
    pub name: Option<String>,
}

fn is_sha256(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

impl SnapshotDocument {
    pub fn from_json(value: &Value, now_ms: u64) -> Self {
        let empty = Map::new();
        let map = value.as_object().unwrap_or(&empty);
        let host = map.get("host").and_then(Value::as_object).map(|host| {
            let text = |key: &str| {
                host.get(key)
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_owned()
            };
            SnapshotHost {
                display_name: text("display_name"),
                alias: text("alias"),
                operating_system: text("os"),
                architecture: text("arch"),
            }
        });
        let icons = map
            .get("icons")
            .and_then(Value::as_object)
            .map(|icons| {
                icons
                    .iter()
                    .filter(|(key, _)| is_sha256(key))
                    .filter_map(|(key, value)| Some((key.clone(), value.as_str()?.to_owned())))
                    .collect()
            })
            .unwrap_or_default();
        Self {
            schema_version: map
                .get("schema_version")
                .and_then(Value::as_u64)
                .unwrap_or(1),
            exported_at_unix_ms: map
                .get("exported_at_unix_ms")
                .and_then(Value::as_u64)
                .unwrap_or(now_ms),
            source: map
                .get("source")
                .and_then(Value::as_str)
                .unwrap_or("ProcessLama")
                .to_owned(),
            display_name: map
                .get("display_name")
                .and_then(Value::as_str)
                .map(str::to_owned),
            host,
            icons,
            snapshot: snapshot_from_json(map.get("snapshot").unwrap_or(&Value::Null), now_ms),
        }
    }

    pub fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert("schema_version".into(), json!(self.schema_version));
        map.insert(
            "exported_at_unix_ms".into(),
            json!(self.exported_at_unix_ms),
        );
        map.insert("source".into(), json!(self.source));
        if let Some(name) = &self.display_name {
            map.insert("display_name".into(), json!(name));
        }
        if let Some(host) = &self.host {
            map.insert(
                "host".into(),
                json!({
                    "display_name": host.display_name,
                    "alias": host.alias,
                    "os": host.operating_system,
                    "arch": host.architecture,
                }),
            );
        }
        if !self.icons.is_empty() {
            map.insert("icons".into(), json!(self.icons));
        }
        map.insert("snapshot".into(), snapshot_to_json(&self.snapshot));
        Value::Object(map)
    }
}

pub fn snapshot_to_json(snapshot: &ProcessSnapshot) -> Value {
    let mut map = Map::new();
    map.insert(
        "generated_at_unix_ms".into(),
        json!(snapshot.generated_at_unix_ms),
    );
    map.insert("platform".into(), json!(snapshot.platform));
    map.insert(
        "processes".into(),
        Value::Array(
            snapshot
                .processes
                .iter()
                .map(|record| record_to_json(record))
                .collect(),
        ),
    );
    if let Some(error) = &snapshot.error {
        map.insert("error".into(), json!(error));
    }
    Value::Object(map)
}

pub fn snapshot_from_json(value: &Value, now_ms: u64) -> ProcessSnapshot {
    let empty = Map::new();
    let map = value.as_object().unwrap_or(&empty);
    if let Some(error) = map.get("error").and_then(Value::as_str) {
        let mut snapshot = ProcessSnapshot::empty(Some(error.to_owned()));
        snapshot.generated_at_unix_ms = now_ms;
        return snapshot;
    }
    ProcessSnapshot {
        generated_at_unix_ms: map
            .get("generated_at_unix_ms")
            .and_then(Value::as_u64)
            .unwrap_or(0),
        platform: map
            .get("platform")
            .and_then(Value::as_str)
            .unwrap_or("unknown")
            .to_owned(),
        processes: map
            .get("processes")
            .and_then(Value::as_array)
            .map(|items| {
                items
                    .iter()
                    .filter_map(record_from_json)
                    .map(Arc::new)
                    .collect()
            })
            .unwrap_or_default(),
        error: None,
        topology: None,
    }
}

fn ports_json(ports: &Option<Arc<[u16]>>) -> Value {
    ports
        .as_ref()
        .map_or(Value::Null, |ports| json!(ports.as_ref()))
}

pub fn record_to_json(record: &ProcessRecord) -> Value {
    let mut map = Map::new();
    let mut put = |key: &str, value: Value| {
        map.insert(key.to_owned(), value);
    };
    put("pid", json!(record.pid));
    put("ppid", json!(record.ppid));
    put("uid", json!(record.uid));
    put("user", json!(record.user));
    put("status", json!(record.status.name()));
    put("rss_bytes", json!(record.rss_bytes));
    put("virtual_memory_bytes", json!(record.virtual_memory_bytes));
    put("cpu_time_nanos", json!(record.cpu_time_nanos));
    put("thread_count", json!(record.thread_count));
    put("open_file_count", json!(record.open_file_count));
    put("local_ports", ports_json(&record.local_ports));
    put("listening_ports", ports_json(&record.listening_ports));
    put("nice", json!(record.nice));
    put("priority", json!(record.priority));
    put("cpu_usage", json!(record.cpu_usage));
    put("gpu_usage", json!(record.gpu_usage));
    put(
        "network_in_bytes_per_second",
        json!(record.network_in_bytes_per_second),
    );
    put(
        "network_out_bytes_per_second",
        json!(record.network_out_bytes_per_second),
    );
    put(
        "total_network_in_bytes",
        json!(record.total_network_in_bytes),
    );
    put(
        "total_network_out_bytes",
        json!(record.total_network_out_bytes),
    );
    put(
        "storage_read_bytes_per_second",
        json!(record.storage_read_bytes_per_second),
    );
    put(
        "storage_write_bytes_per_second",
        json!(record.storage_write_bytes_per_second),
    );
    put(
        "total_storage_read_bytes",
        json!(record.total_storage_read_bytes),
    );
    put(
        "total_storage_write_bytes",
        json!(record.total_storage_write_bytes),
    );
    put("storage_io_available", json!(record.storage_io_available));
    put("tree_cpu_usage", json!(record.tree_cpu_usage));
    put("tree_gpu_usage", json!(record.tree_gpu_usage));
    put("tree_rss_bytes", json!(record.tree_rss_bytes));
    put(
        "tree_network_in_bytes_per_second",
        json!(record.tree_network_in_bytes_per_second),
    );
    put(
        "tree_network_out_bytes_per_second",
        json!(record.tree_network_out_bytes_per_second),
    );
    put(
        "tree_storage_read_bytes_per_second",
        json!(record.tree_storage_read_bytes_per_second),
    );
    put(
        "tree_storage_write_bytes_per_second",
        json!(record.tree_storage_write_bytes_per_second),
    );
    put(
        "tree_storage_io_available",
        json!(record.tree_storage_io_available),
    );
    put("descendant_count", json!(record.descendant_count));
    put("start_time_unix_ms", json!(record.start_time_unix_ms));
    put("name", json!(record.name));
    put("executable_path", json!(record.executable_path));
    put("command_line", json!(record.command_line));
    put("app_bundle_path", json!(record.app_bundle_path));
    match &record.icon {
        Some(ProcessIconRef::File(uri)) => put("icon_uri", json!(uri)),
        Some(ProcessIconRef::Remote(sha)) => {
            put("icon_uri", Value::Null);
            put("icon_sha256", json!(sha));
        }
        None => put("icon_uri", Value::Null),
    }
    Value::Object(map)
}

fn ports_from_json(value: Option<&Value>) -> Option<Arc<[u16]>> {
    let items = value?.as_array()?;
    Some(
        items
            .iter()
            .filter_map(Value::as_u64)
            .filter(|port| (1..=65535).contains(port))
            .map(|port| port as u16)
            .collect::<Vec<_>>()
            .into(),
    )
}

pub fn record_from_json(value: &Value) -> Option<ProcessRecord> {
    let map = value.as_object()?;
    let int = |key: &str| map.get(key).and_then(Value::as_f64).unwrap_or(0.0);
    let unsigned = |key: &str| map.get(key).and_then(Value::as_f64).unwrap_or(0.0).max(0.0) as u64;
    let boolean = |key: &str| map.get(key).and_then(Value::as_bool).unwrap_or(false);
    let text = |key: &str| {
        map.get(key)
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_owned()
    };
    let tree_cpu = map
        .get("tree_cpu_usage")
        .or_else(|| map.get("tree_cpu_percent"))
        .and_then(Value::as_f64)
        .unwrap_or(0.0);
    let tree_gpu = map
        .get("tree_gpu_usage")
        .or_else(|| map.get("tree_gpu_percent"))
        .and_then(Value::as_f64)
        .unwrap_or(0.0);
    let icon = if let Some(sha) = map.get("icon_sha256").and_then(Value::as_str) {
        Some(ProcessIconRef::Remote(sha.to_owned()))
    } else {
        map.get("icon_uri")
            .and_then(Value::as_str)
            .map(|uri| ProcessIconRef::File(uri.to_owned()))
    };
    Some(ProcessRecord {
        pid: int("pid") as i32,
        ppid: int("ppid") as i32,
        uid: unsigned("uid") as u32,
        user: text("user"),
        status: ProcessStatus::parse(map.get("status").and_then(Value::as_str).unwrap_or("")),
        rss_bytes: unsigned("rss_bytes"),
        virtual_memory_bytes: unsigned("virtual_memory_bytes"),
        cpu_time_nanos: unsigned("cpu_time_nanos"),
        thread_count: unsigned("thread_count") as u32,
        open_file_count: unsigned("open_file_count") as u32,
        local_ports: ports_from_json(map.get("local_ports")),
        listening_ports: ports_from_json(map.get("listening_ports")),
        nice: int("nice") as i32,
        priority: int("priority") as i32,
        cpu_usage: int("cpu_usage"),
        gpu_usage: int("gpu_usage"),
        network_in_bytes_per_second: int("network_in_bytes_per_second"),
        network_out_bytes_per_second: int("network_out_bytes_per_second"),
        total_network_in_bytes: unsigned("total_network_in_bytes"),
        total_network_out_bytes: unsigned("total_network_out_bytes"),
        storage_read_bytes_per_second: int("storage_read_bytes_per_second"),
        storage_write_bytes_per_second: int("storage_write_bytes_per_second"),
        total_storage_read_bytes: unsigned("total_storage_read_bytes"),
        total_storage_write_bytes: unsigned("total_storage_write_bytes"),
        storage_io_available: boolean("storage_io_available"),
        tree_cpu_usage: tree_cpu,
        tree_gpu_usage: tree_gpu,
        tree_rss_bytes: unsigned("tree_rss_bytes"),
        tree_network_in_bytes_per_second: int("tree_network_in_bytes_per_second"),
        tree_network_out_bytes_per_second: int("tree_network_out_bytes_per_second"),
        tree_storage_read_bytes_per_second: int("tree_storage_read_bytes_per_second"),
        tree_storage_write_bytes_per_second: int("tree_storage_write_bytes_per_second"),
        tree_storage_io_available: boolean("tree_storage_io_available"),
        descendant_count: unsigned("descendant_count"),
        start_time_unix_ms: unsigned("start_time_unix_ms"),
        name: map
            .get("name")
            .and_then(Value::as_str)
            .unwrap_or("Unknown")
            .to_owned(),
        executable_path: text("executable_path"),
        command_line: text("command_line"),
        app_bundle_path: text("app_bundle_path"),
        icon,
    })
}

/// `name-from-user.processlama-snapshot.json` for an export, or
/// `snapshot-<ms>` when the snapshot has no usable name.
pub fn export_file_name(entry: &SnapshotEntry) -> String {
    let base = sanitize_file_name(entry.name.as_deref());
    let base = if base.is_empty() {
        format!("snapshot-{}", entry.generated_at_unix_ms)
    } else {
        base
    };
    format!("{base}{SNAPSHOT_EXTENSION}")
}

fn sanitize_file_name(name: Option<&str>) -> String {
    let Some(name) = name else {
        return String::new();
    };
    let mut trimmed = name.trim().to_owned();
    let lower = trimmed.to_lowercase();
    if lower.ends_with(SNAPSHOT_EXTENSION) {
        trimmed.truncate(trimmed.len() - SNAPSHOT_EXTENSION.len());
    } else if lower.ends_with(".json") {
        trimmed.truncate(trimmed.len() - ".json".len());
    }
    if trimmed.is_empty() {
        return String::new();
    }
    let replaced: String = trimmed
        .chars()
        .map(|c| {
            if matches!(c, '<' | '>' | ':' | '"' | '/' | '\\' | '|' | '?' | '*')
                || (c as u32) < 0x20
            {
                '-'
            } else {
                c
            }
        })
        .collect();
    let mut collapsed = String::with_capacity(replaced.len());
    let mut previous_space = false;
    let mut previous_dash = false;
    for c in replaced.chars() {
        if c.is_whitespace() {
            if !previous_space {
                collapsed.push(' ');
            }
            previous_space = true;
            previous_dash = false;
        } else if c == '-' {
            if !previous_dash {
                collapsed.push('-');
            }
            previous_dash = true;
            previous_space = false;
        } else {
            collapsed.push(c);
            previous_space = false;
            previous_dash = false;
        }
    }
    collapsed.trim().to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn documents_round_trip() {
        let record = ProcessRecord {
            pid: 3,
            name: "x".into(),
            local_ports: Some(Arc::from(vec![80u16])),
            icon: Some(ProcessIconRef::Remote("a".repeat(64))),
            ..ProcessRecord::default()
        };
        let document = SnapshotDocument {
            schema_version: 2,
            exported_at_unix_ms: 9,
            source: "ProcessLama".into(),
            display_name: Some("Mine".into()),
            host: Some(SnapshotHost {
                display_name: "Box".into(),
                alias: "box".into(),
                operating_system: "linux".into(),
                architecture: "arm64".into(),
            }),
            icons: BTreeMap::from([("a".repeat(64), "AAAA".into())]),
            snapshot: ProcessSnapshot {
                generated_at_unix_ms: 7,
                platform: "linux".into(),
                processes: vec![Arc::new(record.clone())],
                error: None,
                topology: None,
            },
        };
        let back = SnapshotDocument::from_json(&document.to_json(), 0);
        assert_eq!(back.display_name.as_deref(), Some("Mine"));
        assert_eq!(back.host, document.host);
        assert_eq!(back.icons, document.icons);
        assert_eq!(*back.snapshot.processes[0], record);
    }

    #[test]
    fn export_names_are_sanitized() {
        let entry = |name: Option<&str>| SnapshotEntry {
            path: String::new(),
            generated_at_unix_ms: 5,
            process_count: 0,
            platform: String::new(),
            name: name.map(str::to_owned),
        };
        assert_eq!(
            export_file_name(&entry(None)),
            "snapshot-5.processlama-snapshot.json"
        );
        assert_eq!(
            export_file_name(&entry(Some(" a/b  c.json "))),
            "a-b c.processlama-snapshot.json"
        );
    }
}
