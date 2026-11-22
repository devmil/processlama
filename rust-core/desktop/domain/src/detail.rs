//! Inspector detail sections and ports.

use crate::process::{ProcessIdentity, ProcessRecord};

/// One inspector section: its value, or why there is none.
#[derive(Clone, Debug, PartialEq)]
pub enum DetailSection<T> {
    Available(T),
    Restricted(String),
    Unsupported(String),
    NotFound(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FileDescriptorInfo {
    pub fd: i32,
    pub kind: String,
    pub path: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NetworkEndpointInfo {
    pub protocol: String,
    pub local_address: String,
    pub local_port: u16,
    pub local_address_approximate: bool,
    pub remote_address: String,
    pub remote_port: u16,
    pub remote_address_approximate: bool,
    pub state: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TaskSummaryInfo {
    pub thread_count: u64,
    pub mach_syscall_count: u64,
    pub rosetta_translated: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ThreadInfo {
    pub thread_id: u64,
    pub cpu_percent: f64,
    pub cpu_percent_approximate: bool,
    pub state: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ThreadInspectionInfo {
    pub summary: Option<TaskSummaryInfo>,
    pub threads: Vec<ThreadInfo>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SecurityDetailInfo {
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

#[derive(Clone, Debug, PartialEq)]
pub struct ProcessDetail {
    pub identity: ProcessIdentity,
    pub files: DetailSection<Vec<FileDescriptorInfo>>,
    pub sockets: DetailSection<Vec<NetworkEndpointInfo>>,
    pub threads: DetailSection<ThreadInspectionInfo>,
    pub security: DetailSection<SecurityDetailInfo>,
}

/// The local ports of a process or a subtree, split into the ports it serves
/// on and the other local ports, mostly outgoing connections.
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct ProcessPorts {
    /// Sorted distinct ports served on.
    pub listening: Vec<u16>,
    /// Sorted distinct local ports that are not `listening`.
    pub other: Vec<u16>,
}

impl ProcessPorts {
    /// None when the host did not report port ownership for `record`.
    pub fn of_record(record: &ProcessRecord) -> Option<Self> {
        let local = record.local_ports.as_ref()?;
        Some(Self::merge([(
            local.as_ref(),
            record.listening_ports.as_deref(),
        )]))
    }

    /// Combines `(local, listening)` pairs. A port that listens in one process
    /// is listed as listening even when another uses it otherwise.
    pub fn merge<'a>(sources: impl IntoIterator<Item = (&'a [u16], Option<&'a [u16]>)>) -> Self {
        let mut listening = std::collections::BTreeSet::new();
        let mut local = std::collections::BTreeSet::new();
        for (local_ports, listening_ports) in sources {
            local.extend(local_ports.iter().copied());
            if let Some(ports) = listening_ports {
                listening.extend(ports.iter().copied());
            }
        }
        Self {
            other: local.difference(&listening).copied().collect(),
            listening: listening.into_iter().collect(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.listening.is_empty() && self.other.is_empty()
    }

    pub fn count(&self) -> usize {
        self.listening.len() + self.other.len()
    }

    /// `8080, 5432 +12`: listening ports, then how many other local ports.
    pub fn cell_text(&self) -> String {
        let mut parts = Vec::new();
        if !self.listening.is_empty() {
            parts.push(
                self.listening
                    .iter()
                    .map(u16::to_string)
                    .collect::<Vec<_>>()
                    .join(", "),
            );
        }
        if !self.other.is_empty() {
            parts.push(format!("+{}", self.other.len()));
        }
        parts.join(" ")
    }
}

/// A process that listens on a port, for linking a socket to its peer.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProcessPortOwner {
    pub identity: ProcessIdentity,
    pub pid: i32,
    pub name: String,
}

/// Whether `address` names this host from its own point of view.
pub fn is_loopback_address(address: &str) -> bool {
    let value = address.to_lowercase();
    value.starts_with("127.") || value == "::1" || value == "localhost" || value.starts_with("::ffff:127.")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    #[test]
    fn merged_ports_keep_listening_precedence() {
        let a: &[u16] = &[80, 5000];
        let b: &[u16] = &[80, 6000];
        let ports = ProcessPorts::merge([(a, Some(&[80u16][..])), (b, None)]);
        assert_eq!(ports.listening, vec![80]);
        assert_eq!(ports.other, vec![5000, 6000]);
        assert_eq!(ports.cell_text(), "80 +2");
    }

    #[test]
    fn unknown_ports_are_none() {
        let record = ProcessRecord::default();
        assert_eq!(ProcessPorts::of_record(&record), None);
        let record = ProcessRecord {
            local_ports: Some(Arc::from(vec![1u16, 2])),
            listening_ports: Some(Arc::from(vec![2u16])),
            ..ProcessRecord::default()
        };
        assert_eq!(ProcessPorts::of_record(&record).unwrap().cell_text(), "2 +1");
    }

    #[test]
    fn loopback_addresses() {
        assert!(is_loopback_address("127.0.0.1"));
        assert!(is_loopback_address("::1"));
        assert!(is_loopback_address("::FFFF:127.0.0.1"));
        assert!(!is_loopback_address("10.0.0.1"));
    }
}
