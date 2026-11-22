//! processtree values to domain values.

use processlama_domain::{
    DetailSection, FileDescriptorInfo, NetworkEndpointInfo, ProcessDetail, ProcessIconRef,
    ProcessIdentity, ProcessRecord, ProcessSnapshot, ProcessStatus, ProcessTopology,
    SecurityDetailInfo, TaskSummaryInfo, ThreadInfo, ThreadInspectionInfo,
};
use processlama_telemetry::TelemetrySample;
use processlama_telemetry::backend as processtree;
use std::collections::HashMap;
use std::sync::Arc;

/// Keeps the topology between samples: the engine sends parent links only
/// when its structure version changes.
#[derive(Default)]
pub struct LocalSnapshotMapper {
    topology: Option<Arc<ProcessTopology>>,
}

impl LocalSnapshotMapper {
    pub fn known_topology_version(&self) -> Option<u64> {
        self.topology.as_ref().and_then(|topology| topology.version)
    }

    /// Err when the engine named a version this mapper never received; the
    /// next sample then asks for the full structure.
    pub fn map(&mut self, sample: TelemetrySample) -> Result<ProcessSnapshot, ()> {
        let topology = match (sample.topology_version, sample.topology) {
            (None, _) => None,
            (Some(version), Some(links)) => {
                let order: Vec<ProcessIdentity> = links.iter().map(|link| identity(link.identity)).collect();
                let parents: HashMap<ProcessIdentity, Option<ProcessIdentity>> = links
                    .iter()
                    .map(|link| (identity(link.identity), link.parent.map(identity)))
                    .collect();
                Some(Arc::new(ProcessTopology::new(Some(version), parents, &order)))
            }
            (Some(version), None) => match &self.topology {
                Some(known) if known.version == Some(version) => Some(Arc::clone(known)),
                _ => {
                    self.topology = None;
                    return Err(());
                }
            },
        };
        self.topology.clone_from(&topology);
        Ok(map_snapshot(sample.snapshot, topology))
    }
}

fn identity(identity: processtree::ProcessIdentity) -> ProcessIdentity {
    ProcessIdentity::new(identity.pid, identity.start_time_unix_ms)
}

pub fn map_snapshot(snapshot: processtree::ProcessSnapshot, topology: Option<Arc<ProcessTopology>>) -> ProcessSnapshot {
    ProcessSnapshot {
        generated_at_unix_ms: snapshot.captured_at_unix_ms,
        platform: snapshot.platform,
        processes: snapshot.processes.into_iter().map(|record| Arc::new(map_record(record))).collect(),
        error: None,
        topology,
    }
}

fn map_record(record: processtree::ProcessRecord) -> ProcessRecord {
    ProcessRecord {
        pid: record.identity.pid,
        ppid: record.ppid,
        uid: record.uid,
        user: record.user,
        status: match record.status {
            processtree::ProcessStatus::Running => ProcessStatus::Running,
            processtree::ProcessStatus::Sleeping => ProcessStatus::Sleeping,
            processtree::ProcessStatus::Stopped => ProcessStatus::Stopped,
            processtree::ProcessStatus::Zombie => ProcessStatus::Zombie,
            processtree::ProcessStatus::Unknown => ProcessStatus::Unknown,
        },
        rss_bytes: record.rss_bytes,
        virtual_memory_bytes: record.virtual_memory_bytes,
        cpu_time_nanos: record.cpu_time_nanos,
        thread_count: record.thread_count,
        open_file_count: record.open_file_count,
        local_ports: record.local_ports.map(Arc::from),
        listening_ports: record.listening_ports.map(Arc::from),
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
        start_time_unix_ms: record.identity.start_time_unix_ms,
        name: record.name,
        executable_path: record.executable_path,
        command_line: record.command_line,
        app_bundle_path: record.app_bundle_path,
        icon: record.icon_uri.map(ProcessIconRef::File),
    }
}

fn section<T, U>(section: processtree::introspection::DetailSection<T>, map: impl FnOnce(T) -> U) -> DetailSection<U> {
    use processtree::introspection::DetailSection as Native;
    match section {
        Native::Available(value) => DetailSection::Available(map(value)),
        Native::Restricted { reason } => DetailSection::Restricted(reason),
        Native::Unsupported { reason } => DetailSection::Unsupported(reason),
        Native::NotFound { reason } => DetailSection::NotFound(reason),
    }
}

pub fn map_detail(detail: processtree::ProcessDetail) -> ProcessDetail {
    ProcessDetail {
        identity: identity(detail.identity),
        files: section(detail.files, |files| {
            files
                .into_iter()
                .map(|file| FileDescriptorInfo {
                    fd: file.fd,
                    kind: file.kind,
                    path: file.path,
                })
                .collect()
        }),
        sockets: section(detail.sockets, |sockets| {
            sockets
                .into_iter()
                .map(|endpoint| NetworkEndpointInfo {
                    protocol: endpoint.protocol,
                    local_address: endpoint.local_address,
                    local_port: endpoint.local_port,
                    local_address_approximate: endpoint.local_address_approximate,
                    remote_address: endpoint.remote_address,
                    remote_port: endpoint.remote_port,
                    remote_address_approximate: endpoint.remote_address_approximate,
                    state: endpoint.state,
                })
                .collect()
        }),
        threads: section(detail.threads, |inspection| ThreadInspectionInfo {
            summary: inspection.summary.map(|summary| TaskSummaryInfo {
                thread_count: summary.thread_count.max(0) as u64,
                mach_syscall_count: summary.mach_syscall_count.max(0) as u64,
                rosetta_translated: summary.rosetta_translated,
            }),
            threads: inspection
                .threads
                .into_iter()
                .map(|thread| ThreadInfo {
                    thread_id: thread.thread_id,
                    cpu_percent: thread.cpu_percent,
                    cpu_percent_approximate: thread.cpu_percent_approximate,
                    state: thread.state,
                })
                .collect(),
        }),
        security: section(detail.security, |security| SecurityDetailInfo {
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
        }),
    }
}
