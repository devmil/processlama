//! Remote hosts: profiles, shared connections with leases, the reconnect
//! schedule, helper installs, workflows and the tabs' remote sources.
//!
//! A port of the Flutter `RemoteHostServiceImpl`, `RemoteHostWorkflows` and
//! `RemoteProcessSource`, expressed as state the core advances on events.

use crate::core::{AppCore, CoreChanges, ToastTone, UiEvent, remote_tab_key};
use crate::events::CoreEvent;
use crate::ports::{EventSink, SourceId};
use crate::reconnect::Reconnector;
use crate::remote_ports::{
    CancelToken, HelperArtifact, RemoteConnection, RemoteHostError, TelemetryResult, TelemetrySubscription,
};
use crate::session::{Cadence, ProcessSession, SessionSource, SourcePhase, SourceState, DEFAULT_BACKGROUND_REFRESH_MS};
use processlama_domain::{
    BackgroundRefreshMode, HostCapabilities, ProcessIconRef, ProcessIdentity, ProcessSignal, ProcessSnapshot,
    RemoteConnectionPhase, RemoteFailureCode, RemoteHelperHello, RemoteHelperTarget, RemoteHostFacts,
    RemoteHostProfile, RemoteInstallResult, SignalOutcome, SnapshotDocument, SnapshotHost,
    MAXIMUM_REMOTE_HOST_PROFILES, MAXIMUM_REMOTE_TABS, MAX_REMOTE_ICON_CACHE_BYTES, MIN_REMOTE_ICON_CACHE_BYTES,
    REMOTE_HOST_DISPLAY_NAME_MAX_LENGTH, is_valid_alias, is_valid_display_name,
};
use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap};
use std::rc::Rc;
use std::sync::Arc;

/// Icon bytes one snapshot embeds; the bound of one `icons.fetch`.
const SNAPSHOT_ICON_BYTES: usize = 4 * 1024 * 1024;

/// What one remote host's connection is doing.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct ConnectionState {
    pub phase: RemoteConnectionPhase,
    pub failure: Option<RemoteFailureCode>,
    /// The host's platform when its helper is missing or outdated.
    pub missing_target: Option<RemoteHelperTarget>,
    /// The live helper's hello, kept while reconnecting.
    pub hello: Option<RemoteHelperHello>,
    /// Wall ms of the connection, while live.
    pub connected_since: Option<u64>,
}

impl ConnectionState {
    pub fn needs_helper(&self) -> bool {
        self.failure == Some(RemoteFailureCode::HelperNotInstalled)
    }
}

/// The typed result of "Test connection".
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProbeOutcome {
    SshUnreachable,
    HostKeyUntrusted,
    AuthenticationInteractive,
    UnsupportedPlatform,
    HelperMissing,
    HelperOutdated,
    Ready,
}

/// What the install dialog shows.
#[derive(Clone, Debug, PartialEq)]
pub struct InstallPrompt {
    pub profile_id: String,
    pub host: String,
    pub target: RemoteHelperTarget,
    pub install_path: String,
    pub build_prefix: String,
    pub size: u64,
    pub sha256_prefix: String,
    pub is_update: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum InstallChoice {
    Install,
    InstallAlways,
    Cancel,
}

/// A user-entered profile.
#[derive(Clone, Debug, PartialEq)]
pub struct ProfileDraft {
    pub ssh_alias: String,
    pub display_name: String,
    pub auto_install_helper: bool,
    pub auto_reconnect: bool,
    pub open_on_startup: Option<bool>,
    pub background_refresh: Option<BackgroundRefreshMode>,
}

#[derive(Clone, Debug)]
pub enum RemoteCommand {
    /// Saves a new profile (`id` None) or edits one; replies with
    /// `UiEvent::ProfileSaved`.
    SaveProfile {
        request: u64,
        id: Option<String>,
        draft: ProfileDraft,
    },
    DuplicateProfile(String),
    RemoveProfile(String),
    TestConnection { request: u64, alias: String },
    /// Opens (or selects) the profile's tab and connects.
    OpenTab(String),
    /// Connects, asking to install the helper when the host needs it.
    Connect(String),
    Disconnect(String),
    InstallChoice { profile_id: String, choice: InstallChoice },
    /// Removes every helper from the host (after the user confirmed).
    RemoveHelper(String),
    CopyNetworkInstallCommand(String),
}

#[derive(Debug)]
pub enum RemoteEvent {
    Connected {
        profile_id: String,
        generation: u64,
        result: Result<Arc<dyn RemoteConnection>, RemoteHostError>,
    },
    Closed {
        profile_id: String,
        serial: u64,
        failure: Option<RemoteFailureCode>,
    },
    Installed {
        profile_id: String,
        generation: u64,
        during_connect: bool,
        result: Result<RemoteInstallResult, RemoteHostError>,
    },
    Probed {
        request: u64,
        result: Result<RemoteHostFacts, RemoteHostError>,
    },
    HelperRemoved {
        profile_id: String,
        result: Result<RemoteInstallResult, RemoteHostError>,
    },
    Subscribed {
        source: SourceId,
        serial: u64,
        result: Result<Arc<dyn TelemetrySubscription>, String>,
    },
    Telemetry {
        source: SourceId,
        serial: u64,
        result: TelemetryResult,
    },
    IconsFetched {
        source_key: String,
        hashes: Vec<String>,
        icons: HashMap<String, Vec<u8>>,
    },
}

impl std::fmt::Debug for dyn RemoteConnection {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("RemoteConnection")
    }
}

impl std::fmt::Debug for dyn TelemetrySubscription {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("TelemetrySubscription")
    }
}

/// One profile's shared connection.
#[derive(Default)]
pub(crate) struct Host {
    pub state: ConnectionState,
    pub connection: Option<Arc<dyn RemoteConnection>>,
    pub serial: u64,
    pub leases: usize,
    pub generation: u64,
    pub pruned: bool,
    pub attempting: bool,
    pub attempt_reconnecting: bool,
    pub installed_during_attempt: bool,
    pub cancel: Option<CancelToken>,
    pub reconnector: Option<Reconnector>,
    /// A workflow connect waits for the attempt to report.
    pub workflow_pending: bool,
}

/// Shared between a remote tab's session source and the core.
#[derive(Default)]
pub(crate) struct RemoteSourceShared {
    pub cadence: Option<Cadence>,
    pub polling_ms: u32,
    pub connection: Option<Arc<dyn RemoteConnection>>,
    pub subscription: Option<Arc<dyn TelemetrySubscription>>,
}

/// A remote tab's source: its subscription follows the shared connection.
pub(crate) struct RemoteTab {
    pub profile_id: String,
    pub shared: Rc<RefCell<RemoteSourceShared>>,
    pub subscribe_serial: u64,
    pub last_sample_at: Option<u64>,
    pub connection_serial: u64,
    pub icon_topology: Option<usize>,
}

#[derive(Default)]
pub struct RemoteHosts {
    pub(crate) hosts: HashMap<String, Host>,
    pub(crate) tabs: BTreeMap<SourceId, RemoteTab>,
    pending_install: HashMap<String, (InstallPrompt, HelperArtifact)>,
    probe_cancels: Vec<CancelToken>,
}

impl RemoteHosts {
    pub fn connection_state(&self, profile_id: &str) -> ConnectionState {
        self.hosts
            .get(profile_id)
            .map(|host| host.state.clone())
            .unwrap_or_default()
    }

    pub(crate) fn next_deadline(&self) -> Option<u64> {
        self.hosts
            .values()
            .filter_map(|host| host.reconnector.and_then(|r| r.next_at))
            .min()
    }
}

struct RemoteSessionSource {
    source: SourceId,
    shared: Rc<RefCell<RemoteSourceShared>>,
    sink: Arc<dyn EventSink>,
    executor: Arc<dyn crate::ports::Executor>,
}

impl SessionSource for RemoteSessionSource {
    fn set_cadence(&self, cadence: Cadence, polling_interval_ms: u32) {
        let mut shared = self.shared.borrow_mut();
        if shared.cadence == Some(cadence) && shared.polling_ms == polling_interval_ms {
            return;
        }
        shared.cadence = Some(cadence);
        shared.polling_ms = polling_interval_ms;
        if let Some(subscription) = shared.subscription.clone() {
            let ms = cadence.interval_ms();
            self.executor.spawn(Box::new(move || {
                // The next subscription carries the cadence on failure.
                let _ = subscription.set_cadence(ms, polling_interval_ms);
            }));
        }
    }

    /// The helper pushes samples at its cadence; there is nothing to pull.
    fn sample_now(&self, _polling_interval_ms: u32) {}

    fn fetch_detail(&self, identity: ProcessIdentity, generation: u64) {
        let Some(connection) = self.shared.borrow().connection.clone() else {
            return;
        };
        let sink = Arc::clone(&self.sink);
        let source = self.source;
        self.executor.spawn(Box::new(move || {
            let detail = connection.fetch_detail(identity).ok();
            sink.post(CoreEvent::Detail {
                source,
                identity,
                generation,
                detail,
            });
        }));
    }
}

fn new_profile_id() -> String {
    // An RFC 4122 version 4 UUID from the OS random source.
    let mut bytes = [0u8; 16];
    if getrandom_fill(&mut bytes).is_err() {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos());
        bytes = nanos.to_le_bytes();
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    format!(
        "{}-{}-{}-{}-{}",
        &hex[0..8],
        &hex[8..12],
        &hex[12..16],
        &hex[16..20],
        &hex[20..32]
    )
}

fn getrandom_fill(bytes: &mut [u8]) -> Result<(), ()> {
    use std::io::Read;
    #[cfg(unix)]
    {
        let mut file = std::fs::File::open("/dev/urandom").map_err(|_| ())?;
        file.read_exact(bytes).map_err(|_| ())
    }
    #[cfg(not(unix))]
    {
        let _ = bytes;
        Err(())
    }
}

/// The shell command that installs this build's network service package on a
/// Linux host of `target`; None for other hosts. The user runs it; the app
/// never runs sudo over SSH.
pub fn network_service_install_command(version: &str, build: u64, target: RemoteHelperTarget) -> Option<String> {
    let arch = match target {
        RemoteHelperTarget::LinuxX8664 => "x86_64",
        RemoteHelperTarget::LinuxArm64 => "aarch64",
        RemoteHelperTarget::MacosArm64 | RemoteHelperTarget::MacosX8664 => return None,
    };
    let name = format!("processlama-network-service-{version}-{build}-linux-{arch}");
    Some(format!(
        "curl -fsSLO https://github.com/devmil/processlama/releases/download/v{version}-{build}/{name}.tar.gz && tar -xzf {name}.tar.gz && sudo ./{name}/install.sh"
    ))
}

pub(crate) struct RemoteSnapshotContext {
    pub host: SnapshotHost,
    pub icons: Vec<(String, Vec<u8>)>,
}

impl RemoteSnapshotContext {
    pub fn icons_base64(&self) -> BTreeMap<String, String> {
        self.icons
            .iter()
            .map(|(hash, bytes)| (hash.clone(), base64_encode(bytes)))
            .collect()
    }
}

pub(crate) fn base64_encode(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b = [chunk[0], *chunk.get(1).unwrap_or(&0), *chunk.get(2).unwrap_or(&0)];
        let n = (u32::from(b[0]) << 16) | (u32::from(b[1]) << 8) | u32::from(b[2]);
        out.push(TABLE[(n >> 18) as usize & 63] as char);
        out.push(TABLE[(n >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 { TABLE[(n >> 6) as usize & 63] as char } else { '=' });
        out.push(if chunk.len() > 2 { TABLE[n as usize & 63] as char } else { '=' });
    }
    out
}

pub(crate) fn base64_decode(text: &str) -> Option<Vec<u8>> {
    let value = |c: u8| -> Option<u32> {
        Some(match c {
            b'A'..=b'Z' => u32::from(c - b'A'),
            b'a'..=b'z' => u32::from(c - b'a') + 26,
            b'0'..=b'9' => u32::from(c - b'0') + 52,
            b'+' => 62,
            b'/' => 63,
            _ => return None,
        })
    };
    let bytes = text.as_bytes();
    if bytes.len() % 4 != 0 {
        return None;
    }
    let mut out = Vec::with_capacity(bytes.len() / 4 * 3);
    for chunk in bytes.chunks(4) {
        let pad = chunk.iter().rev().take_while(|c| **c == b'=').count();
        let mut n = 0u32;
        for (i, c) in chunk.iter().enumerate() {
            n <<= 6;
            if i < 4 - pad {
                n |= value(*c)?;
            }
        }
        out.push((n >> 16) as u8);
        if pad < 2 {
            out.push((n >> 8) as u8);
        }
        if pad < 1 {
            out.push(n as u8);
        }
    }
    Some(out)
}

impl AppCore {
    fn profile(&self, id: &str) -> Option<&RemoteHostProfile> {
        self.remote_state.profile(id)
    }

    fn host_mut(&mut self, id: &str) -> &mut Host {
        self.remote.hosts.entry(id.to_owned()).or_default()
    }

    fn mark_connections(&mut self) {
        self.mark(CoreChanges {
            connections: true,
            tabs: true,
            session_meta: true,
            ..CoreChanges::default()
        });
    }

    // Startup

    /// Reopens remote tabs that were open at quit, unless a profile says to
    /// always or never open it.
    pub(crate) fn restore_remote_tabs(&mut self) {
        let state = &self.remote_state;
        let mut open: Vec<String> = state
            .open_tabs
            .iter()
            .filter(|id| state.profile(id).is_some_and(|profile| profile.open_on_startup != Some(false)))
            .cloned()
            .collect();
        for profile in &state.profiles {
            if profile.open_on_startup == Some(true) && !state.open_tabs.contains(&profile.id) {
                open.push(profile.id.clone());
            }
        }
        let active = state.active_tab.clone();
        for id in open.into_iter().take(MAXIMUM_REMOTE_TABS) {
            self.open_remote_tab(&id, false);
        }
        if let Some(active) = active
            && let Some(index) = self.tabs.iter().position(|tab| tab.key == active)
        {
            self.activate(index, false);
        }
    }

    // Tabs

    /// Opens the profile's tab without activating it. Returns its index.
    fn open_remote_tab(&mut self, profile_id: &str, persist: bool) -> Option<usize> {
        let key = remote_tab_key(profile_id);
        if let Some(index) = self.tabs.iter().position(|tab| tab.key == key) {
            return Some(index);
        }
        if self.profile(profile_id).is_none() || self.tabs.len() - 1 >= MAXIMUM_REMOTE_TABS {
            return None;
        }
        let source = self.allocate_source();
        let shared = Rc::new(RefCell::new(RemoteSourceShared::default()));
        let session_source = RemoteSessionSource {
            source,
            shared: Rc::clone(&shared),
            sink: self.sink(),
            executor: Arc::clone(&self.ports.executor),
        };
        let mut session = ProcessSession::new(
            Box::new(session_source),
            HostCapabilities::UNKNOWN,
            SourceState::default(),
            self.background_cadence_for(profile_id),
        );
        let now = self.now();
        session.set_active(false, now);
        let settings = self.settings.clone();
        session.initialize(&settings, now);
        self.tabs.push(crate::core::Tab {
            key,
            profile_id: Some(profile_id.to_owned()),
            source,
            session,
        });
        self.remote.tabs.insert(
            source,
            RemoteTab {
                profile_id: profile_id.to_owned(),
                shared,
                subscribe_serial: 0,
                last_sample_at: None,
                connection_serial: 0,
                icon_topology: None,
            },
        );
        self.acquire(profile_id);
        self.sync_remote_tab(source);
        self.mark(CoreChanges {
            tabs: true,
            ..CoreChanges::default()
        });
        if persist {
            self.persist_tabs();
        }
        Some(self.tabs.len() - 1)
    }

    pub(crate) fn remote_release_tab(&mut self, tab: &crate::core::Tab) {
        if let Some(remote) = self.remote.tabs.remove(&tab.source) {
            if let Some(subscription) = remote.shared.borrow_mut().subscription.take() {
                subscription.cancel();
            }
            self.icons.release(&format!("remote:{}", remote.profile_id));
            self.release(&remote.profile_id);
        }
    }

    fn background_cadence_for(&self, profile_id: &str) -> Cadence {
        let mode = self
            .profile(profile_id)
            .and_then(|profile| profile.background_refresh)
            .unwrap_or(self.remote_state.default_background_refresh);
        match mode {
            BackgroundRefreshMode::Slow => Cadence::Background(DEFAULT_BACKGROUND_REFRESH_MS),
            BackgroundRefreshMode::Live => Cadence::Background(self.settings.polling_interval_ms),
            BackgroundRefreshMode::Paused => Cadence::Paused,
        }
    }

    pub(crate) fn remote_on_settings_changed(&mut self) {
        let updates: Vec<(usize, Cadence)> = self
            .tabs
            .iter()
            .enumerate()
            .filter_map(|(index, tab)| {
                tab.profile_id
                    .as_deref()
                    .map(|profile| (index, self.background_cadence_for(profile)))
            })
            .collect();
        for (index, cadence) in updates {
            self.tabs[index].session.set_background_cadence(cadence);
        }
    }

    // Leases and connections

    fn acquire(&mut self, profile_id: &str) {
        let host = self.host_mut(profile_id);
        host.leases += 1;
        if host.connection.is_none() && !host.attempting && host.state.phase != RemoteConnectionPhase::Reconnecting {
            self.connect(profile_id, false);
        }
    }

    fn release(&mut self, profile_id: &str) {
        let host = self.host_mut(profile_id);
        host.leases = host.leases.saturating_sub(1);
        if host.leases == 0 {
            self.disconnect(profile_id);
        }
    }

    /// Connects now or joins a running attempt. `workflow` asks to install a
    /// missing helper and reports failures.
    fn connect(&mut self, profile_id: &str, workflow: bool) {
        let host = self.host_mut(profile_id);
        if host.connection.as_ref().is_some_and(|connection| connection.is_open()) {
            return;
        }
        if workflow {
            host.workflow_pending = true;
        }
        host.reconnector = None;
        if host.attempting {
            return;
        }
        self.start_attempt(profile_id, false);
    }

    fn start_attempt(&mut self, profile_id: &str, reconnecting: bool) {
        let Some(alias) = self.profile(profile_id).map(|profile| profile.ssh_alias.clone()) else {
            let host = self.host_mut(profile_id);
            host.state = ConnectionState {
                phase: RemoteConnectionPhase::Failed,
                failure: Some(RemoteFailureCode::Internal),
                ..ConnectionState::default()
            };
            self.mark_connections();
            return;
        };
        let cancel = CancelToken::default();
        let host = self.host_mut(profile_id);
        host.attempting = true;
        host.attempt_reconnecting = reconnecting;
        host.installed_during_attempt = false;
        host.cancel = Some(cancel.clone());
        host.state.phase = if reconnecting {
            RemoteConnectionPhase::Reconnecting
        } else {
            RemoteConnectionPhase::Probing
        };
        let generation = host.generation;
        self.mark_connections();
        self.spawn_connect(profile_id, alias, generation, cancel);
    }

    fn spawn_connect(&self, profile_id: &str, alias: String, generation: u64, cancel: CancelToken) {
        let connector = Arc::clone(&self.ports.remote);
        let sink = self.sink();
        let profile = profile_id.to_owned();
        self.spawn(move || {
            let closed_sink = Arc::clone(&sink);
            let closed_profile = profile.clone();
            // The serial is filled in when the core adopts the connection.
            let result = connector.connect(
                &alias,
                &cancel,
                Box::new(move |failure| {
                    closed_sink.post(CoreEvent::Remote(RemoteEvent::Closed {
                        profile_id: closed_profile,
                        serial: 0,
                        failure,
                    }));
                }),
            );
            sink.post(CoreEvent::Remote(RemoteEvent::Connected {
                profile_id: profile,
                generation,
                result,
            }));
        });
    }

    fn on_connected(
        &mut self,
        profile_id: &str,
        generation: u64,
        result: Result<Arc<dyn RemoteConnection>, RemoteHostError>,
    ) {
        let disposed_or_stale = self.remote.hosts.get(profile_id).is_none_or(|host| host.generation != generation);
        if disposed_or_stale {
            if let Ok(connection) = result {
                std::thread::spawn(move || connection.close());
            }
            return;
        }
        match result {
            Ok(connection) => self.adopt(profile_id, connection),
            Err(error) => self.on_connect_failed(profile_id, error),
        }
    }

    fn on_connect_failed(&mut self, profile_id: &str, error: RemoteHostError) {
        let auto_install = self.profile(profile_id).is_some_and(|profile| profile.auto_install_helper);
        let host = self.host_mut(profile_id);
        let reconnecting = host.attempt_reconnecting;
        if error.code == RemoteFailureCode::HelperNotInstalled
            && let Some(target) = error.host_target
            && auto_install
            && !host.installed_during_attempt
        {
            host.installed_during_attempt = true;
            self.start_install(profile_id, target, true);
            return;
        }
        let hello = host.state.hello.clone();
        host.attempting = false;
        host.cancel = None;
        host.state = ConnectionState {
            phase: if reconnecting {
                RemoteConnectionPhase::Reconnecting
            } else if error.code.retryable() {
                RemoteConnectionPhase::Disconnected
            } else {
                RemoteConnectionPhase::Failed
            },
            failure: Some(error.code),
            missing_target: error.host_target,
            hello,
            connected_since: None,
        };
        self.mark_connections();
        self.sync_remote_sources(profile_id);
        if reconnecting {
            self.on_reconnect_attempt_failed(profile_id, error.code);
        }
        self.finish_workflow_connect(profile_id);
    }

    fn adopt(&mut self, profile_id: &str, connection: Arc<dyn RemoteConnection>) {
        let wall = self.wall();
        let facts = connection.hello().facts.clone();
        let host = self.host_mut(profile_id);
        host.serial += 1;
        host.attempting = false;
        host.cancel = None;
        host.reconnector = None;
        host.connection = Some(Arc::clone(&connection));
        host.state = ConnectionState {
            phase: RemoteConnectionPhase::Live,
            failure: None,
            missing_target: None,
            hello: Some(connection.hello().clone()),
            connected_since: Some(wall),
        };
        let prune = !host.pruned;
        host.pruned = true;
        self.update_facts(profile_id, facts.clone());
        if prune && let Some(alias) = self.profile(profile_id).map(|profile| profile.ssh_alias.clone()) {
            let connector = Arc::clone(&self.ports.remote);
            let keep = facts.helper_build_id.clone();
            self.spawn(move || {
                let _ = connector.prune_helpers(&alias, &keep);
            });
        }
        self.mark_connections();
        self.sync_remote_sources(profile_id);
        self.finish_workflow_connect(profile_id);
    }

    fn update_facts(&mut self, profile_id: &str, facts: RemoteHostFacts) {
        let Some(profile) = self.remote_state.profiles.iter_mut().find(|profile| profile.id == profile_id) else {
            return;
        };
        if profile.last_known.as_ref() == Some(&facts) {
            return;
        }
        profile.last_known = Some(facts);
        self.save_remote_hosts("profile");
    }

    fn on_closed(&mut self, profile_id: &str, failure: Option<RemoteFailureCode>) {
        let auto_reconnect = self.profile(profile_id).is_some_and(|profile| profile.auto_reconnect);
        let now = self.now();
        let Some(host) = self.remote.hosts.get_mut(profile_id) else {
            return;
        };
        let Some(connection) = host.connection.as_ref() else {
            return;
        };
        // Closed callbacks name no serial; only the adopted connection counts,
        // and an open one did not close.
        if connection.is_open() {
            return;
        }
        host.connection = None;
        host.state.connected_since = None;
        match failure {
            None => {
                host.state.phase = RemoteConnectionPhase::Disconnected;
                host.state.failure = None;
            }
            Some(code) => {
                let can_retry = code.retryable() && auto_reconnect && host.leases > 0;
                host.state.phase = if can_retry {
                    RemoteConnectionPhase::Reconnecting
                } else {
                    RemoteConnectionPhase::Disconnected
                };
                host.state.failure = Some(code);
                if can_retry {
                    host.reconnector = Reconnector::start(now);
                    if host.reconnector.is_none() {
                        host.state.phase = RemoteConnectionPhase::Disconnected;
                    }
                }
            }
        }
        self.mark_connections();
        self.sync_remote_sources(profile_id);
    }

    pub(crate) fn remote_on_time(&mut self, now: u64) {
        let due: Vec<String> = self
            .remote
            .hosts
            .iter()
            .filter(|(_, host)| host.reconnector.and_then(|r| r.next_at).is_some_and(|at| at <= now))
            .map(|(id, _)| id.clone())
            .collect();
        for profile_id in due {
            let host = self.host_mut(&profile_id);
            if let Some(reconnector) = host.reconnector.as_mut() {
                reconnector.next_at = None;
                reconnector.attempts += 1;
            }
            if host.attempting {
                continue;
            }
            self.start_attempt(&profile_id, true);
        }
    }

    fn on_reconnect_attempt_failed(&mut self, profile_id: &str, code: RemoteFailureCode) {
        let now = self.now();
        let host = self.host_mut(profile_id);
        let Some(reconnector) = host.reconnector.as_mut() else {
            return;
        };
        if !code.retryable() {
            host.reconnector = None;
            host.state.phase = RemoteConnectionPhase::Failed;
        } else if !reconnector.schedule_next(now) {
            host.reconnector = None;
            host.state.phase = RemoteConnectionPhase::Disconnected;
        }
        self.mark_connections();
    }

    fn disconnect(&mut self, profile_id: &str) {
        let Some(host) = self.remote.hosts.get_mut(profile_id) else {
            return;
        };
        host.generation += 1;
        host.reconnector = None;
        host.attempting = false;
        host.workflow_pending = false;
        if let Some(cancel) = host.cancel.take() {
            cancel.cancel();
        }
        let connection = host.connection.take();
        host.state.phase = RemoteConnectionPhase::Disconnected;
        host.state.failure = None;
        host.state.connected_since = None;
        if let Some(connection) = connection {
            self.spawn(move || connection.close());
        }
        self.mark_connections();
        self.sync_remote_sources(profile_id);
    }

    // Helper installs

    fn start_install(&mut self, profile_id: &str, target: RemoteHelperTarget, during_connect: bool) {
        let Some(alias) = self.profile(profile_id).map(|profile| profile.ssh_alias.clone()) else {
            return;
        };
        let Some(artifact) = self.ports.remote.bundled_helper(target) else {
            let host = self.host_mut(profile_id);
            host.attempting = false;
            host.state.phase = RemoteConnectionPhase::Failed;
            host.state.failure = Some(RemoteFailureCode::UnsupportedPlatform);
            self.mark_connections();
            return;
        };
        let cancel = CancelToken::default();
        let host = self.host_mut(profile_id);
        if !during_connect {
            host.cancel = Some(cancel.clone());
        }
        let cancel = host.cancel.clone().unwrap_or(cancel);
        host.state.phase = RemoteConnectionPhase::Installing;
        let generation = host.generation;
        self.mark_connections();
        let connector = Arc::clone(&self.ports.remote);
        let sink = self.sink();
        let profile = profile_id.to_owned();
        self.spawn(move || {
            let result = connector.install_helper(&alias, &artifact, &cancel);
            sink.post(CoreEvent::Remote(RemoteEvent::Installed {
                profile_id: profile,
                generation,
                during_connect,
                result,
            }));
        });
    }

    fn on_installed(
        &mut self,
        profile_id: &str,
        generation: u64,
        during_connect: bool,
        result: Result<RemoteInstallResult, RemoteHostError>,
    ) {
        if self.remote.hosts.get(profile_id).is_none_or(|host| host.generation != generation) {
            return;
        }
        let host = self.host_mut(profile_id);
        match result {
            Ok(RemoteInstallResult::Ok) => {
                if during_connect {
                    host.state.phase = RemoteConnectionPhase::Handshaking;
                    let alias = self.profile(profile_id).map(|profile| profile.ssh_alias.clone());
                    let cancel = self.host_mut(profile_id).cancel.clone().unwrap_or_default();
                    self.mark_connections();
                    if let Some(alias) = alias {
                        self.spawn_connect(profile_id, alias, generation, cancel);
                    }
                    return;
                }
                host.state.phase = RemoteConnectionPhase::Disconnected;
                host.state.failure = None;
                host.state.missing_target = None;
                self.mark_connections();
                let host_name = self.host_name(profile_id);
                self.toast("remoteHelperInstalled", vec![host_name], ToastTone::Success);
                self.connect(profile_id, true);
            }
            Ok(other) => {
                host.attempting = false;
                host.state.phase = RemoteConnectionPhase::Failed;
                host.state.failure = Some(other.failure());
                self.mark_connections();
                self.report_install_failed(profile_id, Some(other.failure()));
                self.finish_workflow_connect(profile_id);
            }
            Err(error) => {
                host.attempting = false;
                host.state.phase = RemoteConnectionPhase::Failed;
                host.state.failure = Some(error.code);
                self.mark_connections();
                self.report_install_failed(profile_id, Some(error.code));
                self.finish_workflow_connect(profile_id);
            }
        }
    }

    fn report_install_failed(&mut self, profile_id: &str, failure: Option<RemoteFailureCode>) {
        let host = self.host_name(profile_id);
        let reason = failure.map(|code| format!("@failure:{}", code.name())).unwrap_or_default();
        self.toast("remoteHelperInstallFailed", vec![host, reason], ToastTone::Error);
    }

    /// A workflow connect finished: ask to install a missing helper, or
    /// report the failure.
    fn finish_workflow_connect(&mut self, profile_id: &str) {
        let host = self.host_mut(profile_id);
        if !host.workflow_pending || host.attempting {
            return;
        }
        host.workflow_pending = false;
        let state = host.state.clone();
        if state.needs_helper()
            && let Some(target) = state.missing_target
        {
            self.prompt_install(profile_id, target);
        } else if state.phase == RemoteConnectionPhase::Failed {
            let host = self.host_name(profile_id);
            let reason = state.failure.map(|code| format!("@failure:{}", code.name())).unwrap_or_default();
            self.toast("remoteHostConnectFailed", vec![host, reason], ToastTone::Error);
        }
    }

    fn prompt_install(&mut self, profile_id: &str, target: RemoteHelperTarget) {
        let Some(profile) = self.profile(profile_id).cloned() else {
            return;
        };
        let Some(artifact) = self.ports.remote.bundled_helper(target) else {
            let host = self.host_name(profile_id);
            self.toast("remoteHelperInstallUnavailable", vec![host], ToastTone::Error);
            return;
        };
        let previous = profile.last_known.as_ref().map(|facts| facts.helper_build_id.clone());
        let prompt = InstallPrompt {
            profile_id: profile_id.to_owned(),
            host: profile.display_name.clone(),
            target,
            install_path: artifact.install_path(),
            build_prefix: artifact.build_id.chars().take(12).collect(),
            size: artifact.size,
            sha256_prefix: artifact.sha256.chars().take(12).collect(),
            is_update: previous.is_some_and(|previous| previous != artifact.build_id),
        };
        self.remote
            .pending_install
            .insert(profile_id.to_owned(), (prompt.clone(), artifact));
        self.emit(UiEvent::ConfirmHelperInstall(prompt));
    }

    fn on_install_choice(&mut self, profile_id: &str, choice: InstallChoice) {
        let Some((prompt, _)) = self.remote.pending_install.remove(profile_id) else {
            return;
        };
        match choice {
            InstallChoice::Cancel => {}
            InstallChoice::Install | InstallChoice::InstallAlways => {
                if choice == InstallChoice::InstallAlways
                    && let Some(profile) = self.remote_state.profiles.iter_mut().find(|p| p.id == profile_id)
                {
                    profile.auto_install_helper = true;
                    self.save_remote_hosts("profile");
                }
                self.start_install(profile_id, prompt.target, false);
            }
        }
    }

    fn host_name(&self, profile_id: &str) -> String {
        self.profile(profile_id)
            .map(|profile| profile.display_name.clone())
            .unwrap_or_default()
    }

    // Probes

    fn test_connection(&mut self, request: u64, alias: String) {
        let connector = Arc::clone(&self.ports.remote);
        let sink = self.sink();
        let cancel = CancelToken::default();
        self.remote.probe_cancels.push(cancel.clone());
        self.spawn(move || {
            let result = connector
                .connect(&alias, &cancel, Box::new(|_| {}))
                .map(|connection| {
                    let facts = connection.hello().facts.clone();
                    connection.close();
                    facts
                });
            sink.post(CoreEvent::Remote(RemoteEvent::Probed { request, result }));
        });
    }

    fn on_probed(&mut self, request: u64, result: Result<RemoteHostFacts, RemoteHostError>) {
        let (outcome, platform, compatibility) = match result {
            Ok(facts) => (
                ProbeOutcome::Ready,
                facts.target.platform_label().to_owned(),
                facts.compatibility.to_string(),
            ),
            Err(error) => {
                let outcome = match error.code {
                    RemoteFailureCode::HostKeyUntrusted => ProbeOutcome::HostKeyUntrusted,
                    RemoteFailureCode::AuthenticationInteractive => ProbeOutcome::AuthenticationInteractive,
                    RemoteFailureCode::UnsupportedPlatform => ProbeOutcome::UnsupportedPlatform,
                    RemoteFailureCode::HelperNotInstalled => ProbeOutcome::HelperMissing,
                    RemoteFailureCode::HelperOutdated
                    | RemoteFailureCode::HelperDamaged
                    | RemoteFailureCode::HelperStartFailed
                    | RemoteFailureCode::ProtocolMismatch => ProbeOutcome::HelperOutdated,
                    _ => ProbeOutcome::SshUnreachable,
                };
                (
                    outcome,
                    error
                        .host_target
                        .map_or_else(|| "–".to_owned(), |target| target.platform_label().to_owned()),
                    "–".to_owned(),
                )
            }
        };
        self.emit(UiEvent::ProbeFinished {
            request,
            outcome,
            platform,
            compatibility,
        });
    }

    // Profiles

    fn save_profile(&mut self, request: u64, id: Option<String>, draft: ProfileDraft) {
        let alias = draft.ssh_alias.trim().to_owned();
        let name = if draft.display_name.trim().is_empty() {
            alias.clone()
        } else {
            draft.display_name.trim().to_owned()
        };
        if !is_valid_alias(&alias) || !is_valid_display_name(&name) {
            self.emit(UiEvent::ProfileSaved {
                request,
                profile_id: None,
                error: Some("remoteHostSaveFailed"),
            });
            return;
        }
        let saved_id = match id {
            None => {
                if self.remote_state.profiles.len() >= MAXIMUM_REMOTE_HOST_PROFILES {
                    self.emit(UiEvent::ProfileSaved {
                        request,
                        profile_id: None,
                        error: Some("remoteHostTooMany"),
                    });
                    return;
                }
                let profile = RemoteHostProfile {
                    id: new_profile_id(),
                    display_name: name,
                    ssh_alias: alias,
                    auto_install_helper: draft.auto_install_helper,
                    auto_reconnect: draft.auto_reconnect,
                    open_on_startup: draft.open_on_startup,
                    background_refresh: draft.background_refresh,
                    last_known: None,
                    unknown_fields: serde_json::Map::new(),
                };
                let id = profile.id.clone();
                self.remote_state.profiles.push(profile);
                id
            }
            Some(id) => {
                let Some(profile) = self.remote_state.profiles.iter_mut().find(|profile| profile.id == id) else {
                    self.emit(UiEvent::ProfileSaved {
                        request,
                        profile_id: None,
                        error: Some("remoteHostSaveFailed"),
                    });
                    return;
                };
                let alias_changed = profile.ssh_alias != alias;
                profile.display_name = name;
                profile.ssh_alias = alias;
                profile.auto_install_helper = draft.auto_install_helper;
                profile.auto_reconnect = draft.auto_reconnect;
                profile.open_on_startup = draft.open_on_startup;
                profile.background_refresh = draft.background_refresh;
                if alias_changed {
                    // A different host behind a new alias is not the one we knew.
                    profile.last_known = None;
                }
                if alias_changed {
                    self.disconnect(&id);
                }
                id
            }
        };
        self.save_remote_hosts("profile");
        self.remote_on_settings_changed();
        self.mark_connections();
        self.emit(UiEvent::ProfileSaved {
            request,
            profile_id: Some(saved_id),
            error: None,
        });
    }

    fn duplicate_profile(&mut self, id: &str) {
        let Some(source) = self.profile(id).cloned() else {
            return;
        };
        if self.remote_state.profiles.len() >= MAXIMUM_REMOTE_HOST_PROFILES {
            self.toast("remoteHostTooMany", vec![], ToastTone::Error);
            return;
        }
        let suffix = " 2";
        let max = REMOTE_HOST_DISPLAY_NAME_MAX_LENGTH - suffix.len();
        let base: String = source.display_name.chars().take(max).collect();
        self.remote_state.profiles.push(RemoteHostProfile {
            id: new_profile_id(),
            display_name: format!("{base}{suffix}"),
            ssh_alias: source.ssh_alias,
            auto_install_helper: source.auto_install_helper,
            auto_reconnect: source.auto_reconnect,
            open_on_startup: Some(false),
            background_refresh: source.background_refresh,
            last_known: None,
            unknown_fields: serde_json::Map::new(),
        });
        self.save_remote_hosts("profile");
    }

    fn remove_profile(&mut self, id: &str) {
        let key = remote_tab_key(id);
        self.handle_command_close_tab(&key);
        self.disconnect(id);
        self.remote.hosts.remove(id);
        self.remote_state.profiles.retain(|profile| profile.id != id);
        self.remote_state.open_tabs.retain(|tab| tab != id);
        if self.remote_state.active_tab.as_deref() == Some(key.as_str()) {
            self.remote_state.active_tab = Some("local".into());
        }
        self.save_remote_hosts("profile");
        self.mark_connections();
    }

    fn handle_command_close_tab(&mut self, key: &str) {
        self.handle(CoreEvent::Command(crate::events::Command::CloseTab(key.to_owned())));
    }

    pub(crate) fn set_default_background_refresh(&mut self, mode: BackgroundRefreshMode) {
        if self.remote_state.default_background_refresh == mode {
            return;
        }
        self.remote_state.default_background_refresh = mode;
        self.save_remote_hosts("options");
        self.remote_on_settings_changed();
    }

    pub(crate) fn set_icon_cache_bytes(&mut self, bytes: u64) {
        let bytes = bytes.clamp(MIN_REMOTE_ICON_CACHE_BYTES, MAX_REMOTE_ICON_CACHE_BYTES);
        if self.remote_state.icon_cache_bytes == bytes {
            return;
        }
        self.remote_state.icon_cache_bytes = bytes;
        self.save_remote_hosts("options");
    }

    // Commands and events

    pub(crate) fn handle_remote_command(&mut self, command: RemoteCommand) {
        match command {
            RemoteCommand::SaveProfile { request, id, draft } => self.save_profile(request, id, draft),
            RemoteCommand::DuplicateProfile(id) => self.duplicate_profile(&id),
            RemoteCommand::RemoveProfile(id) => self.remove_profile(&id),
            RemoteCommand::TestConnection { request, alias } => self.test_connection(request, alias),
            RemoteCommand::OpenTab(id) => match self.open_remote_tab(&id, true) {
                Some(index) => {
                    self.activate(index, true);
                    self.connect(&id, true);
                }
                None => {
                    if self.profile(&id).is_some() {
                        self.toast("remoteTabLimit", vec![MAXIMUM_REMOTE_TABS.to_string()], ToastTone::Error);
                    }
                }
            },
            RemoteCommand::Connect(id) => {
                let state = self.remote.connection_state(&id);
                if state.needs_helper()
                    && let Some(target) = state.missing_target
                {
                    self.prompt_install(&id, target);
                } else {
                    self.connect(&id, true);
                }
            }
            RemoteCommand::Disconnect(id) => self.disconnect(&id),
            RemoteCommand::InstallChoice { profile_id, choice } => self.on_install_choice(&profile_id, choice),
            RemoteCommand::RemoveHelper(id) => {
                let Some(alias) = self.profile(&id).map(|profile| profile.ssh_alias.clone()) else {
                    return;
                };
                self.disconnect(&id);
                let connector = Arc::clone(&self.ports.remote);
                let sink = self.sink();
                self.spawn(move || {
                    let result = connector.remove_helpers(&alias);
                    sink.post(CoreEvent::Remote(RemoteEvent::HelperRemoved { profile_id: id, result }));
                });
            }
            RemoteCommand::CopyNetworkInstallCommand(id) => {
                let target = self
                    .remote
                    .connection_state(&id)
                    .hello
                    .map(|hello| hello.facts.target);
                let installed = self.ports.updates.installed();
                if let Some(command) =
                    target.and_then(|target| network_service_install_command(&installed.version, installed.build, target))
                {
                    self.emit(UiEvent::CopyToClipboard {
                        text: command,
                        toast_key: "remoteCapabilityInstallCommandCopied",
                    });
                }
            }
        }
    }

    pub(crate) fn handle_remote_event(&mut self, event: RemoteEvent) {
        match event {
            RemoteEvent::Connected {
                profile_id,
                generation,
                result,
            } => self.on_connected(&profile_id, generation, result),
            RemoteEvent::Closed { profile_id, failure, .. } => self.on_closed(&profile_id, failure),
            RemoteEvent::Installed {
                profile_id,
                generation,
                during_connect,
                result,
            } => self.on_installed(&profile_id, generation, during_connect, result),
            RemoteEvent::Probed { request, result } => self.on_probed(request, result),
            RemoteEvent::HelperRemoved { profile_id, result } => {
                self.host_mut(&profile_id).pruned = false;
                let host = self.host_name(&profile_id);
                match result {
                    Ok(RemoteInstallResult::Ok) => self.toast("remoteHelperRemoved", vec![host], ToastTone::Success),
                    _ => self.toast("remoteHelperRemoveFailed", vec![host], ToastTone::Error),
                }
            }
            RemoteEvent::Subscribed { source, serial, result } => self.on_subscribed(source, serial, result),
            RemoteEvent::Telemetry { source, serial, result } => self.on_telemetry(source, serial, result),
            RemoteEvent::IconsFetched {
                source_key,
                hashes,
                icons,
            } => self.on_icons_fetched(&source_key, &hashes, icons),
        }
    }

    // Remote sources

    fn sync_remote_sources(&mut self, profile_id: &str) {
        let sources: Vec<SourceId> = self
            .remote
            .tabs
            .iter()
            .filter(|(_, tab)| tab.profile_id == profile_id)
            .map(|(source, _)| *source)
            .collect();
        for source in sources {
            self.sync_remote_tab(source);
        }
    }

    /// Follows the host's connection: subscribe when live, drop the
    /// subscription when not, and project the host state onto the source.
    fn sync_remote_tab(&mut self, source: SourceId) {
        let Some(tab) = self.remote.tabs.get(&source) else {
            return;
        };
        let profile_id = tab.profile_id.clone();
        let host = self.remote.hosts.get(&profile_id);
        let connection = host.and_then(|host| host.connection.clone());
        let serial = host.map_or(0, |host| host.serial);
        let state = host.map(|host| host.state.clone()).unwrap_or_default();
        let tab = self.remote.tabs.get_mut(&source).expect("checked");
        let connection_changed = tab.connection_serial != serial
            || tab.shared.borrow().connection.is_some() != connection.is_some();
        if connection_changed {
            tab.connection_serial = serial;
            tab.icon_topology = None;
            let mut shared = tab.shared.borrow_mut();
            if let Some(subscription) = shared.subscription.take() {
                subscription.cancel();
            }
            shared.connection = connection.clone();
        }
        let last_sample = tab.last_sample_at;
        let phase = match state.phase {
            RemoteConnectionPhase::Live => {
                if last_sample.is_none() {
                    SourcePhase::Connecting
                } else {
                    SourcePhase::Live
                }
            }
            RemoteConnectionPhase::Failed | RemoteConnectionPhase::Reconnecting | RemoteConnectionPhase::Disconnected => {
                if last_sample.is_none() {
                    SourcePhase::Failed
                } else {
                    SourcePhase::Stale
                }
            }
            _ => {
                if last_sample.is_none() {
                    SourcePhase::Connecting
                } else {
                    SourcePhase::Stale
                }
            }
        };
        let source_state = SourceState {
            phase,
            last_sample_at_ms: last_sample,
            failure: state.failure,
        };
        if let Some(index) = self.tab_index_for_source(source) {
            let session = &mut self.tabs[index].session;
            if let Some(hello) = &state.hello {
                session.set_capabilities(hello.capabilities);
            }
            session.set_source_state(source_state);
        }
        if connection_changed && let Some(connection) = connection {
            self.icons.reset_failures(&format!("remote:{profile_id}"));
            self.subscribe(source, connection);
        }
        self.mark(CoreChanges {
            session_meta: true,
            ..CoreChanges::default()
        });
    }

    fn subscribe(&mut self, source: SourceId, connection: Arc<dyn RemoteConnection>) {
        let Some(tab) = self.remote.tabs.get_mut(&source) else {
            return;
        };
        tab.subscribe_serial += 1;
        let serial = tab.subscribe_serial;
        let (cadence, polling) = {
            let shared = tab.shared.borrow();
            (shared.cadence, shared.polling_ms.max(1))
        };
        let cadence_ms = cadence.and_then(Cadence::interval_ms);
        let polling = if polling <= 1 { self.settings.polling_interval_ms } else { polling };
        let sink = self.sink();
        self.spawn(move || {
            let sample_sink = Arc::clone(&sink);
            let result = connection.subscribe_telemetry(
                cadence_ms,
                polling,
                Box::new(move |result| {
                    sample_sink.post(CoreEvent::Remote(RemoteEvent::Telemetry { source, serial, result }));
                }),
            );
            sink.post(CoreEvent::Remote(RemoteEvent::Subscribed { source, serial, result }));
        });
    }

    fn on_subscribed(&mut self, source: SourceId, serial: u64, result: Result<Arc<dyn TelemetrySubscription>, String>) {
        let Some(tab) = self.remote.tabs.get_mut(&source) else {
            if let Ok(subscription) = result {
                subscription.cancel();
            }
            return;
        };
        let Ok(subscription) = result else {
            return;
        };
        if serial != tab.subscribe_serial || tab.shared.borrow().connection.is_none() {
            subscription.cancel();
            return;
        }
        let mut shared = tab.shared.borrow_mut();
        // The cadence may have changed while subscribing.
        if let Some(cadence) = shared.cadence {
            let ms = cadence.interval_ms();
            let polling = shared.polling_ms;
            let pending = Arc::clone(&subscription);
            self.ports.executor.spawn(Box::new(move || {
                let _ = pending.set_cadence(ms, polling);
            }));
        }
        shared.subscription = Some(subscription);
    }

    fn on_telemetry(&mut self, source: SourceId, serial: u64, result: TelemetryResult) {
        let Some(tab) = self.remote.tabs.get(&source) else {
            return;
        };
        if serial != tab.subscribe_serial {
            return;
        }
        match result {
            Ok(snapshot) => self.handle(CoreEvent::Sample {
                source,
                snapshot: Arc::new(snapshot),
            }),
            Err(()) => {
                // A malformed sample: start over with a fresh topology.
                let connection = {
                    let tab = self.remote.tabs.get_mut(&source).expect("checked");
                    let mut shared = tab.shared.borrow_mut();
                    if let Some(subscription) = shared.subscription.take() {
                        subscription.cancel();
                    }
                    shared.connection.clone()
                };
                if let Some(connection) = connection {
                    self.subscribe(source, connection);
                }
            }
        }
    }

    /// Before a remote sample reaches its session: liveness and icons.
    pub(crate) fn remote_before_sample(&mut self, index: usize, snapshot: &Arc<ProcessSnapshot>) {
        let source = self.tabs[index].source;
        let wall = self.wall();
        let Some(tab) = self.remote.tabs.get_mut(&source) else {
            return;
        };
        let first = tab.last_sample_at.is_none();
        tab.last_sample_at = Some(wall);
        let topology = snapshot.topology.as_ref().map(|topology| Arc::as_ptr(topology) as usize);
        let fetch = if tab.icon_topology != topology {
            tab.icon_topology = topology;
            tab.shared.borrow().connection.clone()
        } else {
            None
        };
        let profile_id = tab.profile_id.clone();
        if let Some(connection) = fetch {
            let hashes: Vec<String> = snapshot
                .processes
                .iter()
                .filter_map(|record| match &record.icon {
                    Some(ProcessIconRef::Remote(hash)) => Some(hash.clone()),
                    _ => None,
                })
                .collect();
            self.ensure_icons(&format!("remote:{profile_id}"), hashes, connection);
        }
        if first {
            self.sync_remote_tab(source);
        } else {
            let state = SourceState {
                phase: SourcePhase::Live,
                last_sample_at_ms: Some(wall),
                failure: None,
            };
            self.tabs[index].session.set_source_state(state);
            self.mark(CoreChanges {
                session_meta: true,
                ..CoreChanges::default()
            });
        }
    }

    /// Credit after the sample was applied: a slow client lowers the rate.
    pub(crate) fn remote_after_sample(&mut self, index: usize) {
        let source = self.tabs[index].source;
        if let Some(tab) = self.remote.tabs.get(&source)
            && let Some(subscription) = tab.shared.borrow().subscription.clone()
        {
            subscription.grant(1);
        }
    }

    pub(crate) fn remote_send_signal(
        &mut self,
        profile_id: &str,
        source: SourceId,
        identity: ProcessIdentity,
        signal: ProcessSignal,
    ) {
        let connection = self.remote.hosts.get(profile_id).and_then(|host| host.connection.clone());
        let sink = self.sink();
        let Some(connection) = connection else {
            sink.post(CoreEvent::SignalSent {
                source,
                identity,
                signal,
                outcome: Ok(SignalOutcome::Unknown),
            });
            return;
        };
        self.spawn(move || {
            // A failed call may or may not have sent it; never resend.
            let outcome = connection.send_signal(identity, signal).unwrap_or(SignalOutcome::Unknown);
            sink.post(CoreEvent::SignalSent {
                source,
                identity,
                signal,
                outcome: Ok(outcome),
            });
        });
    }

    pub(crate) fn remote_snapshot_context(&self, profile_id: &str, snapshot: &ProcessSnapshot) -> RemoteSnapshotContext {
        let profile = self.profile(profile_id);
        let facts = self
            .remote
            .hosts
            .get(profile_id)
            .and_then(|host| host.state.hello.as_ref().map(|hello| hello.facts.clone()))
            .or_else(|| profile.and_then(|profile| profile.last_known.clone()));
        let mut icons = Vec::new();
        let mut seen = std::collections::HashSet::new();
        let mut total = 0usize;
        for record in &snapshot.processes {
            if let Some(ProcessIconRef::Remote(hash)) = &record.icon
                && seen.insert(hash.clone())
                && let Some(bytes) = self.ports.icon_cache.read(hash)
                && total + bytes.len() <= SNAPSHOT_ICON_BYTES
            {
                total += bytes.len();
                icons.push((hash.clone(), bytes));
            }
        }
        RemoteSnapshotContext {
            host: SnapshotHost {
                display_name: profile.map(|p| p.display_name.clone()).unwrap_or_default(),
                alias: profile.map(|p| p.ssh_alias.clone()).unwrap_or_default(),
                operating_system: facts.as_ref().map(|f| f.target.os().to_owned()).unwrap_or_default(),
                architecture: facts.as_ref().map(|f| f.target.arch().to_owned()).unwrap_or_default(),
            },
            icons,
        }
    }

    pub(crate) fn import_snapshot_icons(&mut self, document: &SnapshotDocument) {
        if document.icons.is_empty() {
            return;
        }
        let icons: Vec<(String, Vec<u8>)> = document
            .icons
            .iter()
            .filter_map(|(hash, encoded)| base64_decode(encoded).map(|bytes| (hash.clone(), bytes)))
            .collect();
        let cache = Arc::clone(&self.ports.icon_cache);
        let sink = self.sink();
        self.spawn(move || {
            let mut stored: HashMap<String, Vec<u8>> = HashMap::new();
            for (hash, bytes) in icons {
                if cache.path_for(&hash).is_none() && cache.store(&hash, &bytes).is_some() {
                    stored.insert(hash, Vec::new());
                }
            }
            let hashes = stored.keys().cloned().collect();
            sink.post(CoreEvent::Remote(RemoteEvent::IconsFetched {
                source_key: String::new(),
                hashes,
                icons: HashMap::new(),
            }));
        });
    }

    pub(crate) fn remote_dispose(&mut self) {
        let ids: Vec<String> = self.remote.hosts.keys().cloned().collect();
        for id in ids {
            self.disconnect(&id);
        }
        for cancel in self.remote.probe_cancels.drain(..) {
            cancel.cancel();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_round_trips() {
        for input in [&b""[..], b"f", b"fo", b"foo", b"foob", b"fooba", b"foobar"] {
            assert_eq!(base64_decode(&base64_encode(input)).as_deref(), Some(input));
        }
        assert_eq!(base64_encode(b"foobar"), "Zm9vYmFy");
    }

    #[test]
    fn network_install_commands_only_for_linux() {
        assert!(network_service_install_command("1.0.0", 5, RemoteHelperTarget::MacosArm64).is_none());
        let command = network_service_install_command("1.0.0", 5, RemoteHelperTarget::LinuxArm64).unwrap();
        assert!(command.contains("processlama-network-service-1.0.0-5-linux-aarch64.tar.gz"));
        assert!(command.ends_with("sudo ./processlama-network-service-1.0.0-5-linux-aarch64/install.sh"));
    }

    #[test]
    fn profile_ids_are_v4_uuids() {
        let id = new_profile_id();
        assert_eq!(id.len(), 36);
        assert_eq!(&id[14..15], "4");
    }
}
