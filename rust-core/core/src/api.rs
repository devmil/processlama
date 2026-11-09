//! Public Rust API intended for `flutter_rust_bridge` code generation.

use processlama_telemetry::{ParentLink, TelemetrySample};

use crate::network::{
    NetworkEventBatch, NetworkStreamConfig, NetworkStreamControl, NetworkStreamStatus,
};
use crate::process_backend::{
    DetailSection, FileDescriptorInfo, NetworkEndpoint, ProcessDetail, ProcessIdentity,
    ProcessRecord, ProcessSignal, ProcessSnapshot, ProcessStatus, SecurityInfo, TaskSummary,
    ThreadInfo, ThreadInspection,
};

#[derive(Debug, Clone)]
pub struct ProcessSnapshotDto {
    pub generated_at_unix_ms: u64,
    pub platform: String,
    pub processes: Vec<ProcessRecordDto>,
    /// Runtime-only cache token. A new engine receives a distinct version.
    pub topology_version: Option<u64>,
    /// Full identity-safe parent links on first load or a version mismatch.
    /// None means the caller's known version is still current.
    pub topology: Option<Vec<ProcessParentDto>>,
}

#[derive(Debug, Clone)]
pub struct ProcessParentDto {
    pub identity: ProcessIdentityDto,
    pub parent: Option<ProcessIdentityDto>,
}

#[derive(Debug, Clone)]
pub struct ProcessRecordDto {
    pub pid: i32,
    pub ppid: i32,
    pub uid: u32,
    pub user: String,
    pub status: ProcessStatusDto,
    pub rss_bytes: u64,
    pub virtual_memory_bytes: u64,
    pub cpu_time_nanos: u64,
    pub thread_count: u32,
    pub open_file_count: u32,
    pub local_ports: Option<Vec<u16>>,
    pub listening_ports: Option<Vec<u16>>,
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
    pub icon_uri: Option<String>,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum ProcessStatusDto {
    Running,
    Sleeping,
    Stopped,
    Zombie,
    Unknown,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum ProcessSignalDto {
    Terminate,
    Kill,
    Suspend,
    Resume,
}

#[derive(Debug, Clone)]
pub struct ProcessDetailDto {
    pub identity: ProcessIdentityDto,
    pub files: FileDetailSectionDto,
    pub sockets: SocketDetailSectionDto,
    pub threads: ThreadDetailSectionDto,
    pub security: SecurityDetailSectionDto,
}

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub struct ProcessIdentityDto {
    pub pid: i32,
    pub start_time_unix_ms: u64,
}

#[derive(Debug, Clone)]
pub enum FileDetailSectionDto {
    Available { value: Vec<FileDescriptorDto> },
    Restricted { reason: String },
    Unsupported { reason: String },
    NotFound { reason: String },
}

#[derive(Debug, Clone)]
pub enum SocketDetailSectionDto {
    Available { value: Vec<NetworkEndpointDto> },
    Restricted { reason: String },
    Unsupported { reason: String },
    NotFound { reason: String },
}

#[derive(Debug, Clone)]
pub enum ThreadDetailSectionDto {
    Available { value: ThreadInspectionDto },
    Restricted { reason: String },
    Unsupported { reason: String },
    NotFound { reason: String },
}

#[derive(Debug, Clone)]
pub enum SecurityDetailSectionDto {
    Available { value: SecurityDetailDto },
    Restricted { reason: String },
    Unsupported { reason: String },
    NotFound { reason: String },
}

#[derive(Debug, Clone)]
pub struct FileDescriptorDto {
    pub fd: i32,
    pub kind: String,
    pub path: String,
}

#[derive(Debug, Clone)]
pub struct NetworkEndpointDto {
    pub protocol: String,
    pub local_address: String,
    pub local_port: u16,
    pub local_address_approximate: bool,
    pub remote_address: String,
    pub remote_port: u16,
    pub remote_address_approximate: bool,
    pub state: String,
}

#[derive(Debug, Clone)]
pub struct ThreadInspectionDto {
    pub summary: Option<TaskSummaryDto>,
    pub threads: Vec<ThreadInfoDto>,
}

#[derive(Debug, Clone)]
pub struct TaskSummaryDto {
    pub thread_count: i32,
    pub mach_syscall_count: i32,
    pub rosetta_translated: bool,
}

#[derive(Debug, Clone)]
pub struct ThreadInfoDto {
    pub thread_id: u64,
    pub cpu_percent: f64,
    pub cpu_percent_approximate: bool,
    pub state: String,
}

#[derive(Debug, Clone)]
pub struct SecurityDetailDto {
    pub signing_status: String,
    pub signing_authority: String,
    pub team_id: String,
    pub bundle_id: String,
    pub entitlements_summary: String,
    pub entitlements_approximate: bool,
    pub gatekeeper_origin: String,
    pub sandbox: bool,
    pub hardened_runtime: bool,
    pub architecture: String,
    pub rosetta_translated: bool,
}

impl From<ProcessSnapshot> for ProcessSnapshotDto {
    fn from(snapshot: ProcessSnapshot) -> Self {
        Self {
            topology_version: None,
            topology: None,
            generated_at_unix_ms: snapshot.captured_at_unix_ms,
            platform: snapshot.platform,
            processes: snapshot
                .processes
                .into_iter()
                .map(ProcessRecordDto::from)
                .collect(),
        }
    }
}

impl From<ProcessRecord> for ProcessRecordDto {
    fn from(record: ProcessRecord) -> Self {
        let pid = record.pid();
        let start_time_unix_ms = record.start_time_unix_ms();
        Self {
            pid,
            ppid: record.ppid,
            uid: record.uid,
            user: record.user,
            status: ProcessStatusDto::from(record.status),
            rss_bytes: record.rss_bytes,
            virtual_memory_bytes: record.virtual_memory_bytes,
            cpu_time_nanos: record.cpu_time_nanos,
            thread_count: record.thread_count,
            open_file_count: record.open_file_count,
            local_ports: record.local_ports,
            listening_ports: record.listening_ports,
            nice: record.nice,
            priority: record.priority,
            cpu_usage: record.cpu_percent,
            gpu_usage: record.gpu_percent,
            network_in_bytes_per_second: record.network_in_bytes_per_second,
            network_out_bytes_per_second: record.network_out_bytes_per_second,
            total_network_in_bytes: record.total_network_in_bytes,
            total_network_out_bytes: record.total_network_out_bytes,
            storage_read_bytes_per_second: record.storage_read_bytes_per_second,
            storage_write_bytes_per_second: record.storage_write_bytes_per_second,
            total_storage_read_bytes: record.total_storage_read_bytes,
            total_storage_write_bytes: record.total_storage_write_bytes,
            storage_io_available: record.storage_io_available,
            tree_cpu_usage: record.tree_cpu_percent,
            tree_gpu_usage: record.tree_gpu_percent,
            tree_rss_bytes: record.tree_rss_bytes,
            tree_network_in_bytes_per_second: record.tree_network_in_bytes_per_second,
            tree_network_out_bytes_per_second: record.tree_network_out_bytes_per_second,
            tree_storage_read_bytes_per_second: record.tree_storage_read_bytes_per_second,
            tree_storage_write_bytes_per_second: record.tree_storage_write_bytes_per_second,
            tree_storage_io_available: record.tree_storage_io_available,
            descendant_count: record.descendant_count as u64,
            start_time_unix_ms,
            name: record.name,
            executable_path: record.executable_path,
            command_line: record.command_line,
            app_bundle_path: record.app_bundle_path,
            icon_uri: record.icon_uri,
        }
    }
}

impl From<ProcessStatus> for ProcessStatusDto {
    fn from(status: ProcessStatus) -> Self {
        match status {
            ProcessStatus::Running => Self::Running,
            ProcessStatus::Sleeping => Self::Sleeping,
            ProcessStatus::Stopped => Self::Stopped,
            ProcessStatus::Zombie => Self::Zombie,
            ProcessStatus::Unknown => Self::Unknown,
        }
    }
}

impl From<ProcessIdentity> for ProcessIdentityDto {
    fn from(identity: ProcessIdentity) -> Self {
        Self {
            pid: identity.pid,
            start_time_unix_ms: identity.start_time_unix_ms,
        }
    }
}

impl From<ProcessDetail> for ProcessDetailDto {
    fn from(detail: ProcessDetail) -> Self {
        Self {
            identity: detail.identity.into(),
            files: map_file_section(detail.files),
            sockets: map_socket_section(detail.sockets),
            threads: map_thread_section(detail.threads),
            security: map_security_section(detail.security),
        }
    }
}

impl From<FileDescriptorInfo> for FileDescriptorDto {
    fn from(file: FileDescriptorInfo) -> Self {
        Self {
            fd: file.fd,
            kind: file.kind,
            path: file.path,
        }
    }
}

impl From<NetworkEndpoint> for NetworkEndpointDto {
    fn from(endpoint: NetworkEndpoint) -> Self {
        Self {
            protocol: endpoint.protocol,
            local_address: endpoint.local_address,
            local_port: endpoint.local_port,
            local_address_approximate: endpoint.local_address_approximate,
            remote_address: endpoint.remote_address,
            remote_port: endpoint.remote_port,
            remote_address_approximate: endpoint.remote_address_approximate,
            state: endpoint.state,
        }
    }
}

impl From<ThreadInspection> for ThreadInspectionDto {
    fn from(inspection: ThreadInspection) -> Self {
        Self {
            summary: inspection.summary.map(TaskSummaryDto::from),
            threads: inspection
                .threads
                .into_iter()
                .map(ThreadInfoDto::from)
                .collect(),
        }
    }
}

impl From<TaskSummary> for TaskSummaryDto {
    fn from(summary: TaskSummary) -> Self {
        Self {
            thread_count: summary.thread_count,
            mach_syscall_count: summary.mach_syscall_count,
            rosetta_translated: summary.rosetta_translated,
        }
    }
}

impl From<ThreadInfo> for ThreadInfoDto {
    fn from(thread: ThreadInfo) -> Self {
        Self {
            thread_id: thread.thread_id,
            cpu_percent: thread.cpu_percent,
            cpu_percent_approximate: thread.cpu_percent_approximate,
            state: thread.state,
        }
    }
}

impl From<SecurityInfo> for SecurityDetailDto {
    fn from(security: SecurityInfo) -> Self {
        Self {
            signing_status: security.signing_status,
            signing_authority: security.signing_authority,
            team_id: security.team_id,
            bundle_id: security.bundle_id,
            entitlements_summary: security.entitlements_summary,
            entitlements_approximate: security.entitlements_approximate,
            gatekeeper_origin: security.gatekeeper_origin,
            sandbox: security.sandbox,
            hardened_runtime: security.hardened_runtime,
            architecture: security.architecture,
            rosetta_translated: security.rosetta_translated,
        }
    }
}

fn map_file_section(section: DetailSection<Vec<FileDescriptorInfo>>) -> FileDetailSectionDto {
    match section {
        DetailSection::Available(value) => FileDetailSectionDto::Available {
            value: value.into_iter().map(FileDescriptorDto::from).collect(),
        },
        DetailSection::Restricted { reason } => FileDetailSectionDto::Restricted { reason },
        DetailSection::Unsupported { reason } => FileDetailSectionDto::Unsupported { reason },
        DetailSection::NotFound { reason } => FileDetailSectionDto::NotFound { reason },
    }
}

fn map_socket_section(section: DetailSection<Vec<NetworkEndpoint>>) -> SocketDetailSectionDto {
    match section {
        DetailSection::Available(value) => SocketDetailSectionDto::Available {
            value: value.into_iter().map(NetworkEndpointDto::from).collect(),
        },
        DetailSection::Restricted { reason } => SocketDetailSectionDto::Restricted { reason },
        DetailSection::Unsupported { reason } => SocketDetailSectionDto::Unsupported { reason },
        DetailSection::NotFound { reason } => SocketDetailSectionDto::NotFound { reason },
    }
}

fn map_thread_section(section: DetailSection<ThreadInspection>) -> ThreadDetailSectionDto {
    match section {
        DetailSection::Available(value) => ThreadDetailSectionDto::Available {
            value: value.into(),
        },
        DetailSection::Restricted { reason } => ThreadDetailSectionDto::Restricted { reason },
        DetailSection::Unsupported { reason } => ThreadDetailSectionDto::Unsupported { reason },
        DetailSection::NotFound { reason } => ThreadDetailSectionDto::NotFound { reason },
    }
}

fn map_security_section(section: DetailSection<SecurityInfo>) -> SecurityDetailSectionDto {
    match section {
        DetailSection::Available(value) => SecurityDetailSectionDto::Available {
            value: value.into(),
        },
        DetailSection::Restricted { reason } => SecurityDetailSectionDto::Restricted { reason },
        DetailSection::Unsupported { reason } => SecurityDetailSectionDto::Unsupported { reason },
        DetailSection::NotFound { reason } => SecurityDetailSectionDto::NotFound { reason },
    }
}

impl From<ProcessSignalDto> for ProcessSignal {
    fn from(signal: ProcessSignalDto) -> Self {
        match signal {
            ProcessSignalDto::Terminate => Self::Terminate,
            ProcessSignalDto::Kill => Self::Kill,
            ProcessSignalDto::Suspend => Self::Suspend,
            ProcessSignalDto::Resume => Self::Resume,
        }
    }
}

pub fn core_version() -> String {
    devmil_logging::record("processlama.native_ready", "INFO", &[], false);
    env!("CARGO_PKG_VERSION").to_string()
}

pub fn collect_process_snapshot(
    polling_interval_ms: u64,
    known_topology_version: Option<u64>,
) -> Result<ProcessSnapshotDto, String> {
    devmil_logging::record(
        "process.snapshot_requested",
        "FINE",
        &[("polling_ms", polling_interval_ms as f64)],
        true,
    );
    processlama_telemetry::shared_engine()
        .sample(polling_interval_ms, known_topology_version)
        .map(ProcessSnapshotDto::from)
        .map_err(|error| error.to_string())
}

impl From<TelemetrySample> for ProcessSnapshotDto {
    fn from(sample: TelemetrySample) -> Self {
        let mut dto = ProcessSnapshotDto::from(sample.snapshot);
        dto.topology_version = sample.topology_version;
        dto.topology = sample.topology.map(|links| {
            links
                .into_iter()
                .map(|ParentLink { identity, parent }| ProcessParentDto {
                    identity: identity.into(),
                    parent: parent.map(Into::into),
                })
                .collect()
        });
        dto
    }
}

/// Configure the directory processtree uses to cache generated process icons.
/// The host owns this location (typically a host-managed temp directory). Must
/// be called before the first snapshot is collected; later calls are ignored.
/// Pass `None` to disable icon generation entirely.
pub fn configure_process_icon_cache(cache_dir: Option<String>) {
    processlama_telemetry::configure_shared_icon_cache(cache_dir.map(std::path::PathBuf::from));
}

pub fn send_process_signal(
    pid: i32,
    start_time_unix_ms: u64,
    signal: ProcessSignalDto,
) -> Result<(), String> {
    processlama_telemetry::send_signal(
        ProcessIdentity {
            pid,
            start_time_unix_ms,
        },
        signal.into(),
    )
    .map_err(|error| error.to_string())
}

pub fn inspect_process_detail(pid: i32, start_time_unix_ms: u64) -> ProcessDetailDto {
    processlama_telemetry::inspect(ProcessIdentity {
        pid,
        start_time_unix_ms,
    })
    .into()
}

pub fn default_network_stream_config() -> NetworkStreamConfig {
    NetworkStreamConfig::default()
}

pub fn create_network_stream_control(config: NetworkStreamConfig) -> NetworkStreamControl {
    NetworkStreamControl::new(config)
}

pub fn network_stream_status(control: &NetworkStreamControl) -> NetworkStreamStatus {
    control.status()
}

pub fn poll_network_event_batch(
    control: &NetworkStreamControl,
) -> Result<NetworkEventBatch, String> {
    control.poll_once().map_err(|error| error.to_string())
}

#[cfg(test)]
mod topology_tests {
    use super::*;
    use crate::process_backend::{PROCESS_TREE_FORMAT, ProcessTreeCache, ProcessTreeSample};
    use processlama_telemetry::versioned_sample;

    fn snapshot_dto(sample: ProcessTreeSample, known: Option<u64>) -> ProcessSnapshotDto {
        versioned_sample(sample, known).into()
    }

    fn sample(
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
    fn bridge_omits_known_topology_but_keeps_fresh_metrics() {
        let mut cache = ProcessTreeCache::default();
        let mut records = vec![
            ProcessRecord::synthetic(1, 0, "root"),
            ProcessRecord::synthetic(2, 1, "child"),
        ];
        let initial = snapshot_dto(sample(&mut cache, records.clone()), None);
        assert_eq!(initial.topology.as_ref().unwrap().len(), 2);
        records[1].cpu_percent = 42.0;
        let updated = snapshot_dto(
            sample(&mut cache, records.clone()),
            initial.topology_version,
        );
        assert!(updated.topology.is_none());
        assert_eq!(updated.processes[0].tree_cpu_usage, 42.0);
        assert_eq!(updated.processes[1].cpu_usage, 42.0);
        records[0].identity.start_time_unix_ms += 1;
        let reused = snapshot_dto(
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
        // A client that missed this change receives a complete graph again.
        let retry = snapshot_dto(
            sample(&mut cache, records.clone()),
            initial.topology_version,
        );
        assert!(retry.topology.is_some());
        let recreated = snapshot_dto(
            sample(&mut ProcessTreeCache::default(), records),
            retry.topology_version,
        );
        assert!(recreated.topology.is_some());
        assert_ne!(retry.topology_version, recreated.topology_version);
    }
}

pub use crate::child_process::{
    NativeCapturedProcess, NativeChildEvent, NativeChildEventKind, NativeEnvironmentVariable,
};

/// Starts a child process the application owns, such as the SSH transport of a remote host,
/// and reports its output and exit on `sink`. Standard error is drained and discarded.
pub fn child_process_start(
    executable: String,
    arguments: Vec<String>,
    environment: Vec<NativeEnvironmentVariable>,
    sink: crate::frb_generated::StreamSink<NativeChildEvent>,
) {
    crate::child_process::start(executable, arguments, environment, sink);
}

/// Queues bytes for a child's standard input; false once it closed.
#[flutter_rust_bridge::frb(sync)]
#[must_use]
pub fn child_process_write(child_id: u64, bytes: Vec<u8>) -> bool {
    crate::child_process::write(child_id, bytes)
}

#[flutter_rust_bridge::frb(sync)]
pub fn child_process_close_stdin(child_id: u64) {
    crate::child_process::close_stdin(child_id);
}

/// Sends SIGTERM, or SIGKILL when `kill`, to a running child.
#[flutter_rust_bridge::frb(sync)]
#[must_use]
pub fn child_process_signal(child_id: u64, kill: bool) -> bool {
    crate::child_process::signal(child_id, kill)
}

/// Runs a short probe such as `ssh -V` and keeps its bounded standard error.
#[must_use]
pub fn child_process_run_capture(
    executable: String,
    arguments: Vec<String>,
    timeout_ms: u32,
    maximum_bytes: u32,
) -> NativeCapturedProcess {
    crate::child_process::run_capture(executable, arguments, timeout_ms, maximum_bytes)
}

/// Drops the native StreamSink before Dart cancels its stream subscription.
pub fn detach_native_diagnostics() {
    devmil_logging::set_detailed(false);
    devmil_logging::install_hook(None);
}
/// Installs the Dart diagnostic availability hook. At most one notification is
/// outstanding until the bounded native history is drained.
pub fn watch_native_diagnostics(sink: crate::frb_generated::StreamSink<()>) {
    devmil_logging::install_hook(Some(std::sync::Arc::new(move || sink.add(()).is_ok())));
    devmil_logging::record("native.hook_ready", "INFO", &[], false);
}
pub fn drain_native_diagnostics() -> Vec<String> {
    devmil_logging::drain()
}
pub fn configure_native_diagnostics(detailed: bool, clear: bool) {
    devmil_logging::set_detailed(detailed);
    if clear {
        devmil_logging::clear();
    }
}
