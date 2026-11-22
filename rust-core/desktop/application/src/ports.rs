//! Outbound ports the shell implements. Blocking work runs on worker threads
//! through [`Executor`]; results come back to the GUI thread as
//! [`CoreEvent`]s through the [`EventSink`].

use crate::events::CoreEvent;
use crate::session_types::{Cadence, SessionSource};
use processlama_domain::{
    AppSettings, ProcessIdentity, ProcessSignal, ProcessSnapshot, RemoteHostsState,
    SignalOutcome, SnapshotDocument, SnapshotEntry,
};
use std::sync::Arc;

/// Delivers events to the core on the GUI thread. Callable from any thread.
pub trait EventSink: Send + Sync {
    fn post(&self, event: CoreEvent);
}

/// Runs finite blocking work off the GUI thread.
pub trait Executor: Send + Sync {
    fn spawn(&self, job: Box<dyn FnOnce() + Send>);
}

/// Wall and monotonic clocks.
pub trait Clock: Send + Sync {
    /// Monotonic milliseconds since an arbitrary start.
    fn monotonic_ms(&self) -> u64;
    /// Milliseconds since the Unix epoch.
    fn wall_ms(&self) -> u64;
}

/// Identifies one process source; events name the source they come from.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct SourceId(pub u64);

/// This computer's telemetry.
pub trait LocalTelemetry {
    /// A sampling handle for one session. Samples arrive as
    /// [`CoreEvent::Sample`] with `id`.
    fn create_source(&self, id: SourceId) -> Box<dyn SessionSource>;
    /// A handle that sends signals from worker threads.
    fn signal_handle(&self) -> Arc<dyn LocalSignals>;
}

/// Sends signals to local processes; blocking, called on workers.
pub trait LocalSignals: Send + Sync {
    fn send_signal(&self, identity: ProcessIdentity, signal: ProcessSignal) -> SignalOutcome;
}

/// Blocking cadence configuration for sources that run their own sampler.
pub trait CadenceControl: Send + Sync {
    fn set_cadence(&self, cadence: Cadence, polling_interval_ms: u32);
}

/// Saved snapshot documents. Every call blocks; the core calls them on
/// worker threads.
pub trait SnapshotStore: Send + Sync {
    fn list(&self) -> Result<Vec<SnapshotEntry>, String>;
    fn save(&self, document: &SnapshotDocument) -> Result<String, String>;
    fn read(&self, path: &str) -> Result<SnapshotDocument, String>;
    /// Copies an external document into the store; returns its stored path.
    fn import(&self, path: &str) -> Result<String, String>;
    fn export(&self, entry: &SnapshotEntry, target: &str) -> Result<(), String>;
    fn rename(&self, entry: &SnapshotEntry, name: &str) -> Result<(), String>;
    fn delete(&self, entry: &SnapshotEntry) -> Result<(), String>;
}

/// Persisted preferences. `load` runs at startup; saves run on workers.
pub trait SettingsStore: Send + Sync {
    fn load_settings(&self) -> AppSettings;
    fn save_settings(&self, settings: &AppSettings) -> Result<(), String>;
    fn load_remote_hosts(&self) -> RemoteHostsState;
    fn save_remote_hosts(&self, state: &RemoteHostsState) -> Result<(), String>;
}

/// The installed build and the published release lists.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InstalledVersion {
    pub version: String,
    pub build: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum UpdateCheck {
    /// The platform's own updater opened its UI (Sparkle on macOS).
    NativeCheckerOpened,
    UpToDate,
    UpdateAvailable { version: String, build: u64 },
    NoPublishedRelease,
}

pub trait UpdateChecker: Send + Sync {
    fn is_supported(&self) -> bool;
    fn installed(&self) -> InstalledVersion;
    /// Configures a platform updater for the channel (macOS).
    fn configure(&self, channel: processlama_domain::ReleaseChannel);
    /// Blocking; runs on a worker.
    fn check(&self, channel: processlama_domain::ReleaseChannel) -> Result<UpdateCheck, String>;
}

/// Failures installing the local Linux network service.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NetworkSetupFailure {
    InstallerMissing,
    AuthorizationUnavailable,
    AuthorizationCancelled,
    InstallFailed,
}

/// The local Linux network telemetry service.
pub trait NetworkServiceSetup: Send + Sync {
    /// Whether this platform has the service at all.
    fn is_supported(&self) -> bool;
    /// Blocking and cheap: whether the service published fresh counters.
    fn is_available(&self) -> bool;
    /// Blocking: installs or repairs the service with authorization.
    fn install_or_repair(&self) -> Result<(), NetworkSetupFailure>;
}

/// Shared ownership of a snapshot published to several consumers.
pub type SharedSnapshot = Arc<ProcessSnapshot>;
