//! Remote hosts: capabilities, profiles and their stored state.

use serde_json::{Map, Value, json};

/// Where per-process network rates come from on a host.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub enum NetworkRateSource {
    Ebpf,
    Nettop,
    Helper,
    #[default]
    None,
}

impl NetworkRateSource {
    pub fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "ebpf" => Self::Ebpf,
            "nettop" => Self::Nettop,
            "helper" => Self::Helper,
            "none" => Self::None,
            _ => return None,
        })
    }
}

/// Why network rates are unavailable.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum NetworkUnavailableReason {
    ServiceNotInstalled,
    Unsupported,
    Restricted,
}

impl NetworkUnavailableReason {
    pub fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "serviceNotInstalled" => Self::ServiceNotInstalled,
            "unsupported" => Self::Unsupported,
            "restricted" => Self::Restricted,
            _ => return None,
        })
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub enum HostOperatingSystem {
    Macos,
    Linux,
    Windows,
    #[default]
    Unknown,
}

/// What a process source can show. Remote tabs take these from the helper's
/// hello; the local tab from the running platform.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
#[allow(clippy::struct_excessive_bools)]
pub struct HostCapabilities {
    pub operating_system: HostOperatingSystem,
    pub gpu: bool,
    pub storage_io: bool,
    pub network_source: NetworkRateSource,
    pub network_unavailable_reason: Option<NetworkUnavailableReason>,
    pub signals: bool,
    pub inspector_files: bool,
    pub inspector_sockets: bool,
    pub inspector_threads: bool,
    pub inspector_security: bool,
    pub icons: bool,
    /// Linux `hidepid`: only the connecting account's processes are visible.
    pub hidepid: bool,
}

impl HostCapabilities {
    pub const UNKNOWN: Self = Self {
        operating_system: HostOperatingSystem::Unknown,
        gpu: false,
        storage_io: false,
        network_source: NetworkRateSource::None,
        network_unavailable_reason: None,
        signals: false,
        inspector_files: false,
        inspector_sockets: false,
        inspector_threads: false,
        inspector_security: false,
        icons: false,
        hidepid: false,
    };

    /// The capabilities of this computer's own telemetry core.
    pub const fn local(operating_system: HostOperatingSystem) -> Self {
        match operating_system {
            HostOperatingSystem::Macos => Self {
                operating_system,
                gpu: true,
                storage_io: true,
                network_source: NetworkRateSource::Nettop,
                network_unavailable_reason: None,
                signals: true,
                inspector_files: true,
                inspector_sockets: true,
                inspector_threads: true,
                inspector_security: true,
                icons: true,
                hidepid: false,
            },
            HostOperatingSystem::Linux => Self {
                operating_system,
                gpu: true,
                storage_io: true,
                network_source: NetworkRateSource::Ebpf,
                network_unavailable_reason: None,
                signals: true,
                inspector_files: true,
                inspector_sockets: true,
                inspector_threads: true,
                inspector_security: false,
                icons: true,
                hidepid: false,
            },
            HostOperatingSystem::Windows => Self {
                operating_system,
                gpu: true,
                storage_io: true,
                network_source: NetworkRateSource::Helper,
                network_unavailable_reason: None,
                signals: true,
                inspector_files: false,
                inspector_sockets: true,
                inspector_threads: true,
                inspector_security: false,
                icons: true,
                hidepid: false,
            },
            HostOperatingSystem::Unknown => Self::UNKNOWN,
        }
    }
}

/// A helper build target.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum RemoteHelperTarget {
    LinuxX8664,
    LinuxArm64,
    MacosArm64,
    MacosX8664,
}

impl RemoteHelperTarget {
    pub const ALL: [Self; 4] = [
        Self::LinuxX8664,
        Self::LinuxArm64,
        Self::MacosArm64,
        Self::MacosX8664,
    ];

    pub const fn wire_name(self) -> &'static str {
        match self {
            Self::LinuxX8664 => "linux-x86_64",
            Self::LinuxArm64 => "linux-arm64",
            Self::MacosArm64 => "macos-arm64",
            Self::MacosX8664 => "macos-x86_64",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        Self::ALL
            .into_iter()
            .find(|target| target.wire_name() == value)
    }

    pub const fn os(self) -> &'static str {
        match self {
            Self::LinuxX8664 | Self::LinuxArm64 => "linux",
            Self::MacosArm64 | Self::MacosX8664 => "macos",
        }
    }

    pub const fn arch(self) -> &'static str {
        match self {
            Self::LinuxX8664 | Self::MacosX8664 => "x86_64",
            Self::LinuxArm64 | Self::MacosArm64 => "arm64",
        }
    }

    /// `Linux/x86_64`-style platform names; never translated.
    pub const fn platform_label(self) -> &'static str {
        match self {
            Self::LinuxX8664 => "Linux/x86_64",
            Self::LinuxArm64 => "Linux/arm64",
            Self::MacosArm64 => "macOS/arm64",
            Self::MacosX8664 => "macOS/x86_64",
        }
    }

    pub const fn operating_system(self) -> HostOperatingSystem {
        match self {
            Self::LinuxX8664 | Self::LinuxArm64 => HostOperatingSystem::Linux,
            Self::MacosArm64 | Self::MacosX8664 => HostOperatingSystem::Macos,
        }
    }
}

/// Typed failures of remote operations; never received text.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum RemoteFailureCode {
    SshMissing,
    SshTooOld,
    SshConnectionFailed,
    HostKeyUntrusted,
    AuthenticationInteractive,
    UnsupportedPlatform,
    HelperNotInstalled,
    HelperOutdated,
    HelperDamaged,
    HelperStartFailed,
    InstallFailed,
    InstallNoSpace,
    InstallNoexec,
    InstallRefused,
    ProtocolMismatch,
    HeartbeatLost,
    FrameTooLarge,
    RemoteRestricted,
    Canceled,
    Internal,
}

impl RemoteFailureCode {
    pub const ALL: [Self; 20] = [
        Self::SshMissing,
        Self::SshTooOld,
        Self::SshConnectionFailed,
        Self::HostKeyUntrusted,
        Self::AuthenticationInteractive,
        Self::UnsupportedPlatform,
        Self::HelperNotInstalled,
        Self::HelperOutdated,
        Self::HelperDamaged,
        Self::HelperStartFailed,
        Self::InstallFailed,
        Self::InstallNoSpace,
        Self::InstallNoexec,
        Self::InstallRefused,
        Self::ProtocolMismatch,
        Self::HeartbeatLost,
        Self::FrameTooLarge,
        Self::RemoteRestricted,
        Self::Canceled,
        Self::Internal,
    ];

    pub const fn name(self) -> &'static str {
        match self {
            Self::SshMissing => "sshMissing",
            Self::SshTooOld => "sshTooOld",
            Self::SshConnectionFailed => "sshConnectionFailed",
            Self::HostKeyUntrusted => "hostKeyUntrusted",
            Self::AuthenticationInteractive => "authenticationInteractive",
            Self::UnsupportedPlatform => "unsupportedPlatform",
            Self::HelperNotInstalled => "helperNotInstalled",
            Self::HelperOutdated => "helperOutdated",
            Self::HelperDamaged => "helperDamaged",
            Self::HelperStartFailed => "helperStartFailed",
            Self::InstallFailed => "installFailed",
            Self::InstallNoSpace => "installNoSpace",
            Self::InstallNoexec => "installNoexec",
            Self::InstallRefused => "installRefused",
            Self::ProtocolMismatch => "protocolMismatch",
            Self::HeartbeatLost => "heartbeatLost",
            Self::FrameTooLarge => "frameTooLarge",
            Self::RemoteRestricted => "remoteRestricted",
            Self::Canceled => "canceled",
            Self::Internal => "internal",
        }
    }

    /// Whether a reconnect may help (the wire contract's `retryable`).
    pub const fn retryable(self) -> bool {
        matches!(
            self,
            Self::SshConnectionFailed | Self::HelperStartFailed | Self::HeartbeatLost
        )
    }
}

/// The result word of an install, prune or uninstall script.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum RemoteInstallResult {
    Ok,
    Damaged,
    NoSpace,
    Noexec,
    Refused,
}

impl RemoteInstallResult {
    pub fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "ok" => Self::Ok,
            "damaged" => Self::Damaged,
            "noSpace" => Self::NoSpace,
            "noexec" => Self::Noexec,
            "refused" => Self::Refused,
            _ => return None,
        })
    }

    pub const fn failure(self) -> RemoteFailureCode {
        match self {
            Self::Ok => RemoteFailureCode::Internal,
            Self::Damaged => RemoteFailureCode::HelperDamaged,
            Self::NoSpace => RemoteFailureCode::InstallNoSpace,
            Self::Noexec => RemoteFailureCode::InstallNoexec,
            Self::Refused => RemoteFailureCode::InstallRefused,
        }
    }
}

/// How a hidden remote tab refreshes.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub enum BackgroundRefreshMode {
    /// Every 5 seconds.
    #[default]
    Slow,
    /// At the live polling interval.
    Live,
    /// Heartbeats only.
    Paused,
}

impl BackgroundRefreshMode {
    pub const ALL: [Self; 3] = [Self::Slow, Self::Live, Self::Paused];
    pub const fn name(self) -> &'static str {
        match self {
            Self::Slow => "slow",
            Self::Live => "live",
            Self::Paused => "paused",
        }
    }
    pub fn parse(value: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|mode| mode.name() == value)
    }
}

/// What a helper reported about its host. Display only; never an authority.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RemoteHostFacts {
    pub target: RemoteHelperTarget,
    pub kernel: String,
    pub host_instance_id: String,
    pub hostname_hash: String,
    pub helper_build_id: String,
    pub compatibility: u64,
    pub processtree_revision: String,
    pub uid: u64,
}

impl RemoteHostFacts {
    pub fn to_json(&self) -> Value {
        json!({
            "target": self.target.wire_name(),
            "kernel": self.kernel,
            "hostInstanceId": self.host_instance_id,
            "hostnameHash": self.hostname_hash,
            "helperBuildId": self.helper_build_id,
            "compatibility": self.compatibility,
            "processtreeRevision": self.processtree_revision,
            "uid": self.uid,
        })
    }

    pub fn from_json(value: &Value) -> Option<Self> {
        let map = value.as_object()?;
        Some(Self {
            target: RemoteHelperTarget::parse(map.get("target")?.as_str()?)?,
            kernel: map.get("kernel")?.as_str()?.to_owned(),
            host_instance_id: map.get("hostInstanceId")?.as_str()?.to_owned(),
            hostname_hash: map.get("hostnameHash")?.as_str()?.to_owned(),
            helper_build_id: map.get("helperBuildId")?.as_str()?.to_owned(),
            compatibility: map.get("compatibility")?.as_u64()?,
            processtree_revision: map.get("processtreeRevision")?.as_str()?.to_owned(),
            uid: map.get("uid")?.as_u64()?,
        })
    }
}

/// A helper's validated hello: what it is and what it can show.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RemoteHelperHello {
    pub facts: RemoteHostFacts,
    pub capabilities: HostCapabilities,
}

/// The connection lifecycle of one remote host.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub enum RemoteConnectionPhase {
    #[default]
    Idle,
    Probing,
    Installing,
    Handshaking,
    Live,
    Reconnecting,
    Disconnected,
    Failed,
}

impl RemoteConnectionPhase {
    pub const fn name(self) -> &'static str {
        match self {
            Self::Idle => "idle",
            Self::Probing => "probing",
            Self::Installing => "installing",
            Self::Handshaking => "handshaking",
            Self::Live => "live",
            Self::Reconnecting => "reconnecting",
            Self::Disconnected => "disconnected",
            Self::Failed => "failed",
        }
    }
}

pub const REMOTE_HOST_ALIAS_MAX_LENGTH: usize = 128;
pub const REMOTE_HOST_DISPLAY_NAME_MAX_LENGTH: usize = 64;
pub const MAXIMUM_REMOTE_HOST_PROFILES: usize = 64;
pub const MAXIMUM_REMOTE_TABS: usize = 16;
pub const DEFAULT_REMOTE_ICON_CACHE_BYTES: u64 = 64 * 1024 * 1024;
pub const MIN_REMOTE_ICON_CACHE_BYTES: u64 = 1024 * 1024;
pub const MAX_REMOTE_ICON_CACHE_BYTES: u64 = 4096 * 1024 * 1024;

/// An SSH destination: a `~/.ssh/config` host alias, a hostname or
/// `user@host`, at most 128 ASCII bytes. Each part starts with a letter or
/// digit and holds letters, digits, `.`, `_` or `-`; ports, URIs, options,
/// whitespace and shell syntax are refused.
pub fn is_valid_alias(alias: &str) -> bool {
    fn part(text: &str) -> bool {
        let bytes = text.as_bytes();
        !bytes.is_empty()
            && bytes[0].is_ascii_alphanumeric()
            && bytes[1..]
                .iter()
                .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
    }
    if alias.len() > REMOTE_HOST_ALIAS_MAX_LENGTH {
        return false;
    }
    match alias.split_once('@') {
        Some((user, host)) => part(user) && part(host),
        None => part(alias),
    }
}

pub fn is_valid_display_name(name: &str) -> bool {
    let trimmed = name.trim();
    !trimmed.is_empty()
        && trimmed.chars().count() <= REMOTE_HOST_DISPLAY_NAME_MAX_LENGTH
        && !trimmed.chars().any(|c| (c as u32) < 0x20)
}

/// A configured remote host. Stores no user names, ports, keys or commands:
/// those belong in `~/.ssh/config`.
#[derive(Clone, Debug, PartialEq)]
pub struct RemoteHostProfile {
    pub id: String,
    pub display_name: String,
    pub ssh_alias: String,
    pub auto_install_helper: bool,
    pub auto_reconnect: bool,
    /// None follows whether the tab was open when the app quit.
    pub open_on_startup: Option<bool>,
    /// None uses the global default.
    pub background_refresh: Option<BackgroundRefreshMode>,
    pub last_known: Option<RemoteHostFacts>,
    /// Fields a newer version stored; kept on save.
    pub unknown_fields: Map<String, Value>,
}

const PROFILE_KEYS: [&str; 8] = [
    "id",
    "displayName",
    "sshAlias",
    "autoInstallHelper",
    "autoReconnect",
    "openOnStartup",
    "backgroundRefresh",
    "lastKnown",
];

impl RemoteHostProfile {
    pub fn to_json(&self) -> Value {
        let mut map = self.unknown_fields.clone();
        map.insert("id".into(), json!(self.id));
        map.insert("displayName".into(), json!(self.display_name));
        map.insert("sshAlias".into(), json!(self.ssh_alias));
        map.insert("autoInstallHelper".into(), json!(self.auto_install_helper));
        map.insert("autoReconnect".into(), json!(self.auto_reconnect));
        map.insert("openOnStartup".into(), json!(self.open_on_startup));
        map.insert(
            "backgroundRefresh".into(),
            json!(self.background_refresh.map(BackgroundRefreshMode::name)),
        );
        map.insert(
            "lastKnown".into(),
            self.last_known
                .as_ref()
                .map_or(Value::Null, RemoteHostFacts::to_json),
        );
        Value::Object(map)
    }

    /// Reads a stored profile; one without a valid id or alias is dropped.
    pub fn from_json(value: &Value) -> Option<Self> {
        let map = value.as_object()?;
        let id = map.get("id")?.as_str()?;
        let alias = map.get("sshAlias")?.as_str()?;
        if id.is_empty() || !is_valid_alias(alias) {
            return None;
        }
        let display_name = map
            .get("displayName")
            .and_then(Value::as_str)
            .filter(|name| is_valid_display_name(name))
            .map_or_else(|| alias.to_owned(), |name| name.trim().to_owned());
        Some(Self {
            id: id.to_owned(),
            display_name,
            ssh_alias: alias.to_owned(),
            auto_install_helper: map.get("autoInstallHelper") == Some(&Value::Bool(true)),
            auto_reconnect: map.get("autoReconnect") != Some(&Value::Bool(false)),
            open_on_startup: map.get("openOnStartup").and_then(Value::as_bool),
            background_refresh: map
                .get("backgroundRefresh")
                .and_then(Value::as_str)
                .and_then(BackgroundRefreshMode::parse),
            last_known: map.get("lastKnown").and_then(RemoteHostFacts::from_json),
            unknown_fields: map
                .iter()
                .filter(|(key, _)| !PROFILE_KEYS.contains(&key.as_str()))
                .map(|(key, value)| (key.clone(), value.clone()))
                .collect(),
        })
    }
}

/// The stored remote hosts value (`remote_hosts_v1`).
#[derive(Clone, Debug, PartialEq)]
pub struct RemoteHostsState {
    pub profiles: Vec<RemoteHostProfile>,
    /// Profile ids of the open remote tabs, in display order.
    pub open_tabs: Vec<String>,
    /// The active tab's key (`local` or `remote:<id>`), if any.
    pub active_tab: Option<String>,
    pub icon_cache_bytes: u64,
    pub default_background_refresh: BackgroundRefreshMode,
    pub unknown_fields: Map<String, Value>,
}

impl Default for RemoteHostsState {
    fn default() -> Self {
        Self {
            profiles: Vec::new(),
            open_tabs: Vec::new(),
            active_tab: None,
            icon_cache_bytes: DEFAULT_REMOTE_ICON_CACHE_BYTES,
            default_background_refresh: BackgroundRefreshMode::Slow,
            unknown_fields: Map::new(),
        }
    }
}

const STATE_KEYS: [&str; 6] = [
    "version",
    "profiles",
    "openTabs",
    "activeTab",
    "iconCacheBytes",
    "defaultBackgroundRefresh",
];

impl RemoteHostsState {
    pub fn profile(&self, id: &str) -> Option<&RemoteHostProfile> {
        self.profiles.iter().find(|profile| profile.id == id)
    }

    pub fn to_json(&self) -> Value {
        let mut map = self.unknown_fields.clone();
        map.insert("version".into(), json!(1));
        map.insert(
            "profiles".into(),
            Value::Array(
                self.profiles
                    .iter()
                    .map(RemoteHostProfile::to_json)
                    .collect(),
            ),
        );
        map.insert("openTabs".into(), json!(self.open_tabs));
        map.insert("activeTab".into(), json!(self.active_tab));
        map.insert("iconCacheBytes".into(), json!(self.icon_cache_bytes));
        map.insert(
            "defaultBackgroundRefresh".into(),
            json!(self.default_background_refresh.name()),
        );
        Value::Object(map)
    }

    /// Reads the stored value, dropping invalid profiles, duplicate ids and
    /// tabs of unknown profiles.
    pub fn from_json(value: &Value) -> Self {
        let Some(map) = value.as_object() else {
            return Self::default();
        };
        let mut profiles = Vec::new();
        let mut ids = std::collections::HashSet::new();
        if let Some(stored) = map.get("profiles").and_then(Value::as_array) {
            for entry in stored {
                if let Some(profile) = RemoteHostProfile::from_json(entry)
                    && profiles.len() < MAXIMUM_REMOTE_HOST_PROFILES
                    && ids.insert(profile.id.clone())
                {
                    profiles.push(profile);
                }
            }
        }
        let mut open_tabs: Vec<String> = Vec::new();
        if let Some(stored) = map.get("openTabs").and_then(Value::as_array) {
            for id in stored.iter().filter_map(Value::as_str) {
                if ids.contains(id) && !open_tabs.iter().any(|tab| tab == id) {
                    open_tabs.push(id.to_owned());
                }
            }
        }
        Self {
            profiles,
            open_tabs,
            active_tab: map
                .get("activeTab")
                .and_then(Value::as_str)
                .map(str::to_owned),
            icon_cache_bytes: map
                .get("iconCacheBytes")
                .and_then(Value::as_u64)
                .filter(|bytes| *bytes >= MIN_REMOTE_ICON_CACHE_BYTES)
                .unwrap_or(DEFAULT_REMOTE_ICON_CACHE_BYTES),
            default_background_refresh: map
                .get("defaultBackgroundRefresh")
                .and_then(Value::as_str)
                .and_then(BackgroundRefreshMode::parse)
                .unwrap_or_default(),
            unknown_fields: map
                .iter()
                .filter(|(key, _)| !STATE_KEYS.contains(&key.as_str()))
                .map(|(key, value)| (key.clone(), value.clone()))
                .collect(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aliases_are_plain_host_aliases() {
        assert!(is_valid_alias("build-box.lan_1"));
        assert!(!is_valid_alias("-oProxyCommand=x"));
        assert!(is_valid_alias("user@host"));
        assert!(is_valid_alias("me@192.0.2.1"));
        assert!(is_valid_alias("build.bot@dev-box"));
        for invalid in [
            "user@@host",
            "-oProxyCommand=x@host",
            "user@host;id",
            "user name@host",
            "user@-host",
            "@host",
            "user@",
            "user@host:22",
            "ssh://x",
            "host*",
            "$(id)",
            "a|b",
        ] {
            assert!(!is_valid_alias(invalid), "{invalid}");
        }
        assert!(!is_valid_alias(""));
        assert!(!is_valid_alias(&"a".repeat(129)));
    }

    #[test]
    fn stored_state_round_trips_and_keeps_unknown_fields() {
        let value = json!({
            "version": 1,
            "future": {"x": 1},
            "profiles": [
                {"id": "a", "sshAlias": "host-a", "displayName": "  A  ", "extra": true,
                 "openOnStartup": true, "backgroundRefresh": "live"},
                {"id": "a", "sshAlias": "dup"},
                {"id": "b", "sshAlias": "bad alias"}
            ],
            "openTabs": ["a", "zzz", "a"],
            "activeTab": "remote:a",
            "iconCacheBytes": 12,
        });
        let state = RemoteHostsState::from_json(&value);
        assert_eq!(state.profiles.len(), 1);
        let profile = &state.profiles[0];
        assert_eq!(profile.display_name, "A");
        assert!(profile.auto_reconnect);
        assert_eq!(profile.open_on_startup, Some(true));
        assert_eq!(
            profile.background_refresh,
            Some(BackgroundRefreshMode::Live)
        );
        assert_eq!(
            profile.unknown_fields.get("extra"),
            Some(&Value::Bool(true))
        );
        assert_eq!(state.open_tabs, vec!["a"]);
        assert_eq!(state.icon_cache_bytes, DEFAULT_REMOTE_ICON_CACHE_BYTES);
        let again = RemoteHostsState::from_json(&state.to_json());
        assert_eq!(again, state);
        assert!(state.unknown_fields.contains_key("future"));
    }
}
