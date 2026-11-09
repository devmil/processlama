//! Facts about the host the helper runs on. Identities are hashed; the hostname and machine
//! identity never cross the wire.
use processlama_wire::contract::{NetworkReason, NetworkSource, Target};
use processlama_wire::messages::{Capabilities, HelloBody, NetworkCapability};
use sha2::{Digest, Sha256};
use std::path::Path;
use std::time::Duration;

/// The target this helper binary was built for.
pub const TARGET: Option<Target> = if cfg!(all(target_os = "linux", target_arch = "x86_64")) {
    Some(Target::LinuxX8664)
} else if cfg!(all(target_os = "linux", target_arch = "aarch64")) {
    Some(Target::LinuxArm64)
} else if cfg!(all(target_os = "macos", target_arch = "aarch64")) {
    Some(Target::MacosArm64)
} else if cfg!(all(target_os = "macos", target_arch = "x86_64")) {
    Some(Target::MacosX8664)
} else {
    None
};

/// A Linux network snapshot older than this means the service is not running.
const NETWORK_SNAPSHOT_FRESHNESS: Duration = Duration::from_secs(5);

fn hex_digest(bytes: &[u8], length: usize) -> String {
    let digest = Sha256::digest(bytes);
    digest
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>()[..length]
        .to_owned()
}

fn bounded(text: &str, max: usize) -> String {
    let clean: String = text.trim().chars().filter(|c| !c.is_control()).collect();
    let mut end = clean.len().min(max);
    while !clean.is_char_boundary(end) {
        end -= 1;
    }
    clean[..end].to_owned()
}

#[cfg(unix)]
fn uname() -> (String, String) {
    let name = rustix::system::uname();
    (
        name.release().to_string_lossy().into_owned(),
        name.nodename().to_string_lossy().into_owned(),
    )
}

#[cfg(not(unix))]
fn uname() -> (String, String) {
    (String::new(), String::new())
}

fn machine_identity() -> String {
    for path in ["/etc/machine-id", "/var/lib/dbus/machine-id"] {
        if let Ok(text) = std::fs::read_to_string(path) {
            if !text.trim().is_empty() {
                return text.trim().to_owned();
            }
        }
    }
    if cfg!(target_os = "macos") {
        if let Ok(output) = std::process::Command::new("/usr/sbin/sysctl")
            .args(["-n", "kern.uuid"])
            .output()
        {
            let text = String::from_utf8_lossy(&output.stdout).trim().to_owned();
            if !text.is_empty() {
                return text;
            }
        }
    }
    String::new()
}

#[cfg(unix)]
fn effective_uid() -> u64 {
    u64::from(rustix::process::geteuid().as_raw())
}

#[cfg(not(unix))]
fn effective_uid() -> u64 {
    0
}

/// Whether `/proc` hides other users' processes (Linux `hidepid`).
pub fn hidepid() -> bool {
    let Ok(mounts) = std::fs::read_to_string("/proc/self/mounts") else {
        return false;
    };
    mounts.lines().any(|line| {
        let fields: Vec<&str> = line.split_whitespace().collect();
        fields.len() >= 4
            && fields[1] == "/proc"
            && fields[3].split(',').any(|option| {
                option
                    .strip_prefix("hidepid=")
                    .is_some_and(|value| !matches!(value, "0" | "off"))
            })
    })
}

/// Network rate availability: the ProcessLama network service on Linux, `nettop` on macOS.
pub fn network_capability() -> NetworkCapability {
    if cfg!(target_os = "macos") {
        return NetworkCapability {
            source: NetworkSource::Nettop,
            reason: None,
        };
    }
    if cfg!(target_os = "linux") {
        let fresh = std::fs::metadata(Path::new(
            processlama_telemetry::LINUX_NETWORK_SNAPSHOT_PATH,
        ))
        .and_then(|metadata| metadata.modified())
        .ok()
        .and_then(|modified| modified.elapsed().ok())
        .is_some_and(|age| age <= NETWORK_SNAPSHOT_FRESHNESS);
        return if fresh {
            NetworkCapability {
                source: NetworkSource::Ebpf,
                reason: None,
            }
        } else {
            NetworkCapability {
                source: NetworkSource::None,
                reason: Some(NetworkReason::ServiceNotInstalled),
            }
        };
    }
    NetworkCapability {
        source: NetworkSource::None,
        reason: Some(NetworkReason::Unsupported),
    }
}

pub fn capabilities(icons: bool) -> Capabilities {
    let macos = cfg!(target_os = "macos");
    Capabilities {
        gpu: processlama_telemetry::backend::gpu_metrics_available(),
        storage_io: true,
        network: network_capability(),
        signals: true,
        inspector_files: true,
        inspector_sockets: true,
        inspector_threads: true,
        inspector_security: macos,
        icons,
        hidepid: hidepid(),
    }
}

/// The product part of the hello.
pub fn hello_body(target: Target, icons: bool) -> HelloBody {
    let (kernel, hostname) = uname();
    let identity = machine_identity();
    HelloBody {
        target,
        kernel: bounded(&kernel, 128),
        host_instance_id: hex_digest(
            format!("processlama-host-instance\n{identity}\n{hostname}").as_bytes(),
            32,
        ),
        hostname_hash: hex_digest(format!("processlama-hostname\n{hostname}").as_bytes(), 16),
        processtree_revision: processlama_wire::PROCESSTREE_REVISION.to_owned(),
        compatibility: processlama_wire::COMPATIBILITY.parse().unwrap_or(0),
        uid: effective_uid(),
        capabilities: capabilities(icons),
    }
}

/// The helper's cache directory under the account's home.
pub fn cache_dir() -> Option<std::path::PathBuf> {
    let home = std::env::var_os("HOME").map(std::path::PathBuf::from)?;
    home.is_absolute()
        .then(|| home.join(processlama_wire::contract::CACHE_ROOT))
}

/// processtree's icon worker cache, created on demand.
pub fn icon_cache_dir() -> Option<std::path::PathBuf> {
    let directory = cache_dir()?.join("icons").join("v1");
    std::fs::create_dir_all(&directory).ok()?;
    Some(directory)
}

/// Deletes the helper's caches. True when they are gone.
pub fn remove_state() -> bool {
    let Some(cache) = cache_dir() else {
        return false;
    };
    match std::fs::remove_dir_all(&cache) {
        Ok(()) => true,
        Err(error) => error.kind() == std::io::ErrorKind::NotFound,
    }
}

fn total_memory_bytes() -> Option<u64> {
    if let Ok(meminfo) = std::fs::read_to_string("/proc/meminfo") {
        return meminfo
            .lines()
            .find_map(|line| line.strip_prefix("MemTotal:"))
            .and_then(|value| {
                value
                    .trim()
                    .trim_end_matches("kB")
                    .trim()
                    .parse::<u64>()
                    .ok()
            })
            .map(|kib| kib * 1024);
    }
    if cfg!(target_os = "macos") {
        let output = std::process::Command::new("/usr/sbin/sysctl")
            .args(["-n", "hw.memsize"])
            .output()
            .ok()?;
        return String::from_utf8_lossy(&output.stdout).trim().parse().ok();
    }
    None
}

fn uptime_seconds() -> Option<u64> {
    if let Ok(uptime) = std::fs::read_to_string("/proc/uptime") {
        return uptime
            .split_whitespace()
            .next()
            .and_then(|value| value.parse::<f64>().ok())
            .map(|seconds| seconds as u64);
    }
    if cfg!(target_os = "macos") {
        let output = std::process::Command::new("/usr/sbin/sysctl")
            .args(["-n", "kern.boottime"])
            .output()
            .ok()?;
        let text = String::from_utf8_lossy(&output.stdout);
        let boot: u64 = text
            .split("sec = ")
            .nth(1)?
            .split(',')
            .next()?
            .trim()
            .parse()
            .ok()?;
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .ok()?
            .as_secs();
        return now.checked_sub(boot);
    }
    None
}

/// `host.facts`: kernel, uptime, CPU count and total memory.
pub fn facts() -> serde_json::Value {
    let (kernel, _) = uname();
    serde_json::json!({
        "kernel": bounded(&kernel, 128),
        "uptimeSeconds": uptime_seconds(),
        "cpuCount": std::thread::available_parallelism().map_or(1, std::num::NonZeroUsize::get),
        "memoryBytes": total_memory_bytes().map(|bytes| bytes.min(1 << 53)),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hello_body_validates_on_this_host() {
        let Some(target) = TARGET else { return };
        let body = hello_body(target, false);
        let parsed = HelloBody::parse(&body.to_value()).unwrap();
        assert_eq!(parsed, body);
    }

    #[test]
    fn bounded_text_drops_control_characters() {
        assert_eq!(bounded(" 6.8\n", 128), "6.8");
        assert_eq!(bounded("ééé", 3), "é");
    }
}
