//! Process identities, records and snapshots.

use std::collections::HashMap;
use std::sync::Arc;

/// A process is identified by its PID and its start time: a PID alone can be
/// reused by another process.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Default)]
pub struct ProcessIdentity {
    pub pid: i32,
    pub start_time_unix_ms: u64,
}

impl ProcessIdentity {
    pub const fn new(pid: i32, start_time_unix_ms: u64) -> Self {
        Self {
            pid,
            start_time_unix_ms,
        }
    }

    /// `pid@start`, the form the inspector shows and QML passes back.
    pub fn key(self) -> String {
        format!("{}@{}", self.pid, self.start_time_unix_ms)
    }

    pub fn parse_key(value: &str) -> Option<Self> {
        let (pid, start) = value.split_once('@')?;
        Some(Self {
            pid: pid.parse().ok()?,
            start_time_unix_ms: start.parse().ok()?,
        })
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub enum ProcessStatus {
    Running,
    Sleeping,
    Stopped,
    Zombie,
    #[default]
    Unknown,
}

impl ProcessStatus {
    pub const fn name(self) -> &'static str {
        match self {
            Self::Running => "running",
            Self::Sleeping => "sleeping",
            Self::Stopped => "stopped",
            Self::Zombie => "zombie",
            Self::Unknown => "unknown",
        }
    }

    pub fn parse(value: &str) -> Self {
        match value {
            "running" => Self::Running,
            "sleeping" => Self::Sleeping,
            "stopped" => Self::Stopped,
            "zombie" => Self::Zombie,
            _ => Self::Unknown,
        }
    }

    /// `Running`, `Sleeping`, … as the State column shows it.
    pub fn capitalized(self) -> &'static str {
        match self {
            Self::Running => "Running",
            Self::Sleeping => "Sleeping",
            Self::Stopped => "Stopped",
            Self::Zombie => "Zombie",
            Self::Unknown => "Unknown",
        }
    }
}

/// Where a process's icon comes from.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum ProcessIconRef {
    /// A file the local telemetry core rendered (a path or `file://` URI).
    File(String),
    /// A remote helper's icon by the SHA-256 of its PNG bytes.
    Remote(String),
}

/// One process in a sample.
#[derive(Clone, Debug, PartialEq, Default)]
pub struct ProcessRecord {
    pub pid: i32,
    pub ppid: i32,
    pub uid: u32,
    pub user: String,
    pub status: ProcessStatus,
    pub rss_bytes: u64,
    pub virtual_memory_bytes: u64,
    pub cpu_time_nanos: u64,
    pub thread_count: u32,
    pub open_file_count: u32,
    /// Local TCP/UDP ports reported by the host; None when unavailable.
    pub local_ports: Option<Arc<[u16]>>,
    /// The subset of `local_ports` the process serves on. None when unavailable.
    pub listening_ports: Option<Arc<[u16]>>,
    pub nice: i32,
    pub priority: i32,
    pub cpu_usage: f64,
    pub gpu_usage: f64,
    pub network_in_bytes_per_second: f64,
    pub network_out_bytes_per_second: f64,
    pub total_network_in_bytes: u64,
    pub total_network_out_bytes: u64,
    pub storage_read_bytes_per_second: f64,
    pub storage_write_bytes_per_second: f64,
    pub total_storage_read_bytes: u64,
    pub total_storage_write_bytes: u64,
    pub storage_io_available: bool,
    pub tree_cpu_usage: f64,
    pub tree_gpu_usage: f64,
    pub tree_rss_bytes: u64,
    pub tree_network_in_bytes_per_second: f64,
    pub tree_network_out_bytes_per_second: f64,
    pub tree_storage_read_bytes_per_second: f64,
    pub tree_storage_write_bytes_per_second: f64,
    pub tree_storage_io_available: bool,
    pub descendant_count: u64,
    pub start_time_unix_ms: u64,
    pub name: String,
    pub executable_path: String,
    pub command_line: String,
    pub app_bundle_path: String,
    pub icon: Option<ProcessIconRef>,
}

impl ProcessRecord {
    pub fn identity(&self) -> ProcessIdentity {
        ProcessIdentity::new(self.pid, self.start_time_unix_ms)
    }

    /// The name rows show: the process name, or the executable's name when a
    /// macOS app bundle runs a helper executable of another name.
    pub fn display_name(&self) -> &str {
        let executable_name = basename(&self.executable_path);
        if self.app_bundle_path.is_empty() || executable_name.is_empty() {
            return &self.name;
        }
        let bundle_name = bundle_display_name(&self.app_bundle_path);
        let normalized_executable = normalize_executable_name(executable_name);
        if is_direct_bundle_executable(&self.executable_path, &self.app_bundle_path)
            || normalized_executable == normalize_executable_name(bundle_name)
            || normalized_executable == normalize_executable_name(&self.name)
        {
            return &self.name;
        }
        executable_name
    }

    /// Whether the record carries tree totals computed by the native core.
    pub fn has_native_tree_metrics(&self) -> bool {
        self.descendant_count > 0
            || self.tree_cpu_usage != self.cpu_usage
            || self.tree_gpu_usage != self.gpu_usage
            || self.tree_rss_bytes != self.rss_bytes
            || self.tree_network_in_bytes_per_second != self.network_in_bytes_per_second
            || self.tree_network_out_bytes_per_second != self.network_out_bytes_per_second
            || self.tree_storage_read_bytes_per_second != self.storage_read_bytes_per_second
            || self.tree_storage_write_bytes_per_second != self.storage_write_bytes_per_second
            || self.tree_storage_io_available != self.storage_io_available
    }
}

fn basename(path: &str) -> &str {
    let trimmed = path.trim_end_matches(['/', '\\']);
    match trimmed.rfind(['/', '\\']) {
        Some(index) => &trimmed[index + 1..],
        None => trimmed,
    }
}

fn bundle_display_name(app_bundle_path: &str) -> &str {
    let directory = basename(app_bundle_path);
    directory.strip_suffix(".app").unwrap_or(directory)
}

fn is_direct_bundle_executable(executable_path: &str, app_bundle_path: &str) -> bool {
    let executable = executable_path.replace('\\', "/");
    let bundle = app_bundle_path.replace('\\', "/");
    let directory = if bundle.ends_with('/') {
        format!("{bundle}Contents/MacOS/")
    } else {
        format!("{bundle}/Contents/MacOS/")
    };
    executable
        .strip_prefix(&directory)
        .is_some_and(|relative| !relative.is_empty() && !relative.contains('/'))
}

fn normalize_executable_name(value: &str) -> String {
    value
        .chars()
        .filter(|c| !(c.is_whitespace() || matches!(c, '.' | '_' | '-')))
        .flat_map(char::to_lowercase)
        .collect()
}

/// Parent links of one sample, shared between metric-only samples of the
/// same topology.
#[derive(Debug, Default)]
pub struct ProcessTopology {
    pub version: Option<u64>,
    pub parent_by_identity: HashMap<ProcessIdentity, Option<ProcessIdentity>>,
    pub children_by_parent: HashMap<Option<ProcessIdentity>, Vec<ProcessIdentity>>,
}

impl ProcessTopology {
    pub fn new(
        version: Option<u64>,
        parents: HashMap<ProcessIdentity, Option<ProcessIdentity>>,
        order: &[ProcessIdentity],
    ) -> Self {
        let mut children_by_parent: HashMap<Option<ProcessIdentity>, Vec<ProcessIdentity>> =
            HashMap::new();
        for identity in order {
            if let Some(parent) = parents.get(identity) {
                children_by_parent.entry(*parent).or_default().push(*identity);
            }
        }
        Self {
            version,
            parent_by_identity: parents,
            children_by_parent,
        }
    }
}

/// One sample of every process on a host.
#[derive(Clone, Debug, Default)]
pub struct ProcessSnapshot {
    pub generated_at_unix_ms: u64,
    pub platform: String,
    pub processes: Vec<Arc<ProcessRecord>>,
    pub error: Option<String>,
    pub topology: Option<Arc<ProcessTopology>>,
}

impl ProcessSnapshot {
    pub fn empty(error: Option<String>) -> Self {
        Self {
            generated_at_unix_ms: 0,
            platform: "unknown".into(),
            processes: Vec::new(),
            error,
            topology: None,
        }
    }
}

/// The signals ProcessLama sends.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ProcessSignal {
    Terminate,
    Kill,
    Suspend,
    Resume,
}

impl ProcessSignal {
    pub const fn name(self) -> &'static str {
        match self {
            Self::Terminate => "terminate",
            Self::Kill => "kill",
            Self::Suspend => "suspend",
            Self::Resume => "resume",
        }
    }
}

/// The typed result of a signal request. An `Unknown` signal is never resent.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum SignalOutcome {
    Sent,
    Denied,
    NotFound,
    Unknown,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn record(name: &str, exe: &str, bundle: &str) -> ProcessRecord {
        ProcessRecord {
            name: name.into(),
            executable_path: exe.into(),
            app_bundle_path: bundle.into(),
            ..ProcessRecord::default()
        }
    }

    #[test]
    fn display_name_prefers_helper_executables_inside_bundles() {
        assert_eq!(
            record(
                "Code Helper",
                "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Renderer).app/Contents/MacOS/Code Helper (Renderer)",
                "/Applications/Visual Studio Code.app"
            )
            .display_name(),
            "Code Helper (Renderer)"
        );
        assert_eq!(
            record(
                "Safari",
                "/Applications/Safari.app/Contents/MacOS/Safari",
                "/Applications/Safari.app"
            )
            .display_name(),
            "Safari"
        );
        assert_eq!(record("bash", "/usr/bin/bash", "").display_name(), "bash");
    }

    #[test]
    fn identity_keys_round_trip() {
        let identity = ProcessIdentity::new(42, 1_700_000_000_123);
        assert_eq!(ProcessIdentity::parse_key(&identity.key()), Some(identity));
        assert_eq!(ProcessIdentity::parse_key("x@1"), None);
    }
}
