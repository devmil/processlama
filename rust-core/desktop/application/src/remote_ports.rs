//! Ports of the remote host service: SSH connections to helpers and the
//! helpers bundled with the application.

use processlama_domain::{
    ProcessDetail, ProcessIdentity, ProcessSignal, ProcessSnapshot, RemoteFailureCode,
    RemoteHelperHello, RemoteHelperTarget, RemoteInstallResult, SignalOutcome,
};
use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

/// Cooperative cancellation for a connect or install attempt.
#[derive(Clone, Debug, Default)]
pub struct CancelToken(Arc<AtomicBool>);

impl CancelToken {
    pub fn cancel(&self) {
        self.0.store(true, Ordering::Release);
    }
    pub fn is_canceled(&self) -> bool {
        self.0.load(Ordering::Acquire)
    }
}

/// A typed remote failure, with the host's platform when its helper is
/// missing there.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RemoteHostError {
    pub code: RemoteFailureCode,
    pub host_target: Option<RemoteHelperTarget>,
}

impl RemoteHostError {
    pub const fn new(code: RemoteFailureCode) -> Self {
        Self {
            code,
            host_target: None,
        }
    }
}

/// A helper this application bundles, verified against its descriptor.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HelperArtifact {
    pub target: RemoteHelperTarget,
    pub build_id: String,
    pub size: u64,
    /// Lowercase hexadecimal SHA-256 of the helper bytes.
    pub sha256: String,
    pub path: std::path::PathBuf,
}

impl HelperArtifact {
    /// Where the helper is installed, relative to the account's home.
    pub fn install_path(&self) -> String {
        format!(
            "~/.local/lib/processlama/remote/{}/processlama-remote-helper",
            self.build_id
        )
    }
}

/// Telemetry of one subscription: decoded samples, or a malformed sample
/// after which the client subscribes again.
pub type TelemetryResult = Result<ProcessSnapshot, ()>;

/// One live telemetry subscription.
pub trait TelemetrySubscription: Send + Sync {
    /// Lets the helper send `amount` more samples.
    fn grant(&self, amount: u32);
    /// Blocking: changes the cadence; None pauses (heartbeats only).
    fn set_cadence(&self, cadence_ms: Option<u32>, polling_ms: u32) -> Result<(), String>;
    fn cancel(&self);
}

/// An open helper connection, shared by the tabs of one profile.
pub trait RemoteConnection: Send + Sync {
    fn hello(&self) -> &RemoteHelperHello;
    fn is_open(&self) -> bool;
    /// Blocking. Samples arrive through `on_sample` on a reader thread.
    fn subscribe_telemetry(
        &self,
        cadence_ms: Option<u32>,
        polling_ms: u32,
        on_sample: Box<dyn Fn(TelemetryResult) + Send + Sync>,
    ) -> Result<Arc<dyn TelemetrySubscription>, String>;
    fn fetch_detail(&self, identity: ProcessIdentity) -> Result<ProcessDetail, String>;
    fn send_signal(
        &self,
        identity: ProcessIdentity,
        signal: ProcessSignal,
    ) -> Result<SignalOutcome, String>;
    fn fetch_icons(&self, hashes: &[String]) -> Result<HashMap<String, Vec<u8>>, String>;
    /// Graceful, bounded close.
    fn close(&self);
}

/// Called once when a connection stops: None for an orderly close the client
/// requested, otherwise the failure.
pub type ClosedCallback = Box<dyn FnOnce(Option<RemoteFailureCode>) + Send>;

/// SSH to helpers through the system OpenSSH client. Every call blocks and
/// runs on a worker thread.
pub trait RemoteConnector: Send + Sync {
    fn connect(
        &self,
        alias: &str,
        cancel: &CancelToken,
        on_closed: ClosedCallback,
    ) -> Result<Arc<dyn RemoteConnection>, RemoteHostError>;
    fn install_helper(
        &self,
        alias: &str,
        artifact: &HelperArtifact,
        cancel: &CancelToken,
    ) -> Result<RemoteInstallResult, RemoteHostError>;
    fn prune_helpers(
        &self,
        alias: &str,
        keep_build_id: &str,
    ) -> Result<RemoteInstallResult, RemoteHostError>;
    fn remove_helpers(&self, alias: &str) -> Result<RemoteInstallResult, RemoteHostError>;
    /// The verified bundled helper for `target`.
    fn bundled_helper(&self, target: RemoteHelperTarget) -> Option<HelperArtifact>;
}

/// Icons on disk by content hash.
pub trait IconCache: Send + Sync {
    /// The cached file for `sha256`, if any. Cheap; callable on the GUI thread.
    fn path_for(&self, sha256: &str) -> Option<String>;
    fn total_bytes(&self) -> u64;
    /// Marks hashes as used now.
    fn touch(&self, hashes: &[String]);
    /// Validates and stores an icon; returns its path.
    fn store(&self, sha256: &str, bytes: &[u8]) -> Option<String>;
    fn read(&self, sha256: &str) -> Option<Vec<u8>>;
    fn evict(&self, limit_bytes: u64, keep: &std::collections::HashSet<String>);
    fn clear(&self);
}
