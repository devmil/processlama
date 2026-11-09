//! `process.detail`: inspector sections for one process, bounded.
use processlama_telemetry::backend::{
    DetailSection, FileDescriptorInfo, NetworkEndpoint, ProcessDetail, SecurityInfo,
    ThreadInspection,
};
use serde_json::{Value, json};

/// Entries per list section.
const SECTION_ENTRIES: usize = 4096;
const TEXT_BYTES: usize = 1024;
const REASON_BYTES: usize = 256;

fn text(value: &str, max: usize) -> String {
    if value.len() <= max {
        return value.to_owned();
    }
    let mut end = max;
    while !value.is_char_boundary(end) {
        end -= 1;
    }
    value[..end].to_owned()
}

fn section<T>(section: DetailSection<T>, encode: impl FnOnce(T) -> Value) -> Value {
    match section {
        DetailSection::Available(value) => {
            json!({"state": "available", "reason": null, "value": encode(value)})
        }
        DetailSection::Restricted { reason } => {
            json!({"state": "restricted", "reason": text(&reason, REASON_BYTES), "value": null})
        }
        DetailSection::Unsupported { reason } => {
            json!({"state": "unsupported", "reason": text(&reason, REASON_BYTES), "value": null})
        }
        DetailSection::NotFound { reason } => {
            json!({"state": "notFound", "reason": text(&reason, REASON_BYTES), "value": null})
        }
    }
}

fn files(files: Vec<FileDescriptorInfo>) -> Value {
    Value::Array(
        files
            .into_iter()
            .take(SECTION_ENTRIES)
            .map(|file| {
                json!({
                    "fd": file.fd,
                    "kind": text(&file.kind, 64),
                    "path": text(&file.path, TEXT_BYTES),
                })
            })
            .collect(),
    )
}

fn sockets(endpoints: Vec<NetworkEndpoint>) -> Value {
    Value::Array(
        endpoints
            .into_iter()
            .take(SECTION_ENTRIES)
            .map(|endpoint| {
                json!({
                    "protocol": text(&endpoint.protocol, 32),
                    "localAddress": text(&endpoint.local_address, 128),
                    "localPort": endpoint.local_port,
                    "localApproximate": endpoint.local_address_approximate,
                    "remoteAddress": text(&endpoint.remote_address, 128),
                    "remotePort": endpoint.remote_port,
                    "remoteApproximate": endpoint.remote_address_approximate,
                    "state": text(&endpoint.state, 32),
                })
            })
            .collect(),
    )
}

fn threads(inspection: ThreadInspection) -> Value {
    json!({
        "summary": inspection.summary.map(|summary| json!({
            "threadCount": summary.thread_count,
            "machSyscallCount": summary.mach_syscall_count,
            "rosettaTranslated": summary.rosetta_translated,
        })),
        "threads": inspection.threads.into_iter().take(SECTION_ENTRIES).map(|thread| json!({
            "id": thread.thread_id.min(1 << 53),
            "cpuTenths": if thread.cpu_percent.is_finite() && thread.cpu_percent > 0.0 {
                (thread.cpu_percent * 10.0).round() as i64
            } else { 0 },
            "approximate": thread.cpu_percent_approximate,
            "state": text(&thread.state, 32),
        })).collect::<Vec<_>>(),
    })
}

fn security(info: SecurityInfo) -> Value {
    json!({
        "signingStatus": text(&info.signing_status, 128),
        "signingAuthority": text(&info.signing_authority, TEXT_BYTES),
        "teamId": text(&info.team_id, 64),
        "bundleId": text(&info.bundle_id, 256),
        "entitlementsSummary": text(&info.entitlements_summary, TEXT_BYTES),
        "entitlementsApproximate": info.entitlements_approximate,
        "gatekeeperOrigin": text(&info.gatekeeper_origin, 256),
        "sandbox": info.sandbox,
        "hardenedRuntime": info.hardened_runtime,
        "architecture": text(&info.architecture, 64),
        "rosettaTranslated": info.rosetta_translated,
    })
}

pub fn encode(detail: ProcessDetail) -> Value {
    json!({
        "pid": detail.identity.pid,
        "start": detail.identity.start_time_unix_ms.min(1 << 53),
        "files": section(detail.files, files),
        "sockets": section(detail.sockets, sockets),
        "threads": section(detail.threads, threads),
        "security": section(detail.security, security),
    })
}
