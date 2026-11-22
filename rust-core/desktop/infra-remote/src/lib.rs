//! Remote hosts over the system OpenSSH client: the helper channel, the fixed
//! scripts, telemetry decoding and the helpers bundled with the application.

pub mod channel;
pub mod codec;
pub mod scripts;
pub mod ssh;

use channel::{Channel, ChannelConfig, ChannelFailure};
use processlama_application::{
    CancelToken, ClosedCallback, HelperArtifact, RemoteConnection, RemoteConnector, RemoteHostError,
    TelemetryResult, TelemetrySubscription,
};
use processlama_domain::{
    ProcessDetail, ProcessIdentity, ProcessSignal, RemoteFailureCode, RemoteHelperHello, RemoteHelperTarget,
    RemoteInstallResult, SignalOutcome,
};
use processlama_wire::contract::{HELPER_BYTES, HELPER_EXECUTABLE, INSTALL_DEADLINE_MS, INSTALL_PREFIX, PROBE_DEADLINE_MS, TELEMETRY_CREDIT};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet, VecDeque};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

/// Most output bytes kept from an install, prune or uninstall script; login
/// scripts may print before the status line.
const SCRIPT_OUTPUT_BYTES: usize = 4096;

/// The typed failure for a channel that could not open or stopped.
pub fn failure_code(failure: &ChannelFailure) -> RemoteHostError {
    use RemoteFailureCode as C;
    let code = match failure {
        ChannelFailure::SshConnectionFailed | ChannelFailure::Disconnected => C::SshConnectionFailed,
        ChannelFailure::BootstrapMarker(marker) => {
            let words = &marker.words;
            if marker.version == 1 && words.len() == 2 && words[0] == "missing" {
                let target = RemoteHelperTarget::ALL
                    .into_iter()
                    .find(|target| format!("{}/{}", target.os(), target.arch()) == words[1]);
                if let Some(target) = target {
                    return RemoteHostError {
                        code: C::HelperNotInstalled,
                        host_target: Some(target),
                    };
                }
            }
            if words.len() == 1 && words[0] == "unsupported" {
                C::UnsupportedPlatform
            } else {
                C::HelperStartFailed
            }
        }
        ChannelFailure::BootstrapFailed | ChannelFailure::HelloTimeout => C::HelperStartFailed,
        ChannelFailure::BuildMismatch => C::HelperOutdated,
        ChannelFailure::ProtocolMismatch | ChannelFailure::ProtocolViolation | ChannelFailure::Fatal => {
            C::ProtocolMismatch
        }
        ChannelFailure::FrameTooLarge => C::FrameTooLarge,
        ChannelFailure::HeartbeatLost => C::HeartbeatLost,
        ChannelFailure::Canceled => C::Canceled,
    };
    RemoteHostError::new(code)
}

/// [`RemoteConnector`] over the system OpenSSH client.
pub struct SshConnector {
    ssh: OnceLock<Result<PathBuf, RemoteFailureCode>>,
    config_file: Option<String>,
    helper_roots: Vec<PathBuf>,
}

impl Default for SshConnector {
    fn default() -> Self {
        Self::new()
    }
}

impl SshConnector {
    pub fn new() -> Self {
        // Test harnesses pass an isolated SSH configuration; release builds
        // never read it.
        let config_file = if cfg!(debug_assertions) {
            std::env::var("PROCESSLAMA_SSH_CONFIG").ok().filter(|path| path.starts_with('/'))
        } else {
            None
        };
        Self {
            ssh: OnceLock::new(),
            config_file,
            helper_roots: helper_roots(),
        }
    }

    /// The verified OpenSSH executable; the probe runs once per launch.
    fn executable(&self) -> Result<PathBuf, RemoteHostError> {
        let resolved = self.ssh.get_or_init(|| {
            let executable = ssh::resolve_executable().ok_or(RemoteFailureCode::SshMissing)?;
            let version = ssh::read_version(&executable).ok_or(RemoteFailureCode::SshMissing)?;
            if !ssh::is_supported(&version) {
                return Err(RemoteFailureCode::SshTooOld);
            }
            Ok(executable)
        });
        resolved.clone().map_err(RemoteHostError::new)
    }

    fn start(&self, alias: &str, script: &str) -> Result<std::process::Child, RemoteHostError> {
        let executable = self.executable()?;
        let arguments = ssh::arguments(alias, &ssh::posix_shell_command(script), self.config_file.as_deref())
            .ok_or(RemoteHostError::new(RemoteFailureCode::Internal))?;
        ssh::spawn(&executable, &arguments).map_err(|_| RemoteHostError::new(RemoteFailureCode::SshMissing))
    }

    /// Runs a fixed script and reads its `PROCESSLAMA-INSTALL 1 <result>` line.
    fn run_script(
        &self,
        alias: &str,
        script: &str,
        stdin: Option<Vec<u8>>,
        deadline: Duration,
        cancel: Option<&CancelToken>,
    ) -> Result<RemoteInstallResult, RemoteHostError> {
        let mut child = self.start(alias, script)?;
        let mut stdout = child.stdout.take().ok_or(RemoteHostError::new(RemoteFailureCode::Internal))?;
        let reader = std::thread::spawn(move || {
            let mut output: VecDeque<u8> = VecDeque::new();
            let mut buffer = [0_u8; 4096];
            while let Ok(read) = stdout.read(&mut buffer) {
                if read == 0 {
                    break;
                }
                output.extend(&buffer[..read]);
                while output.len() > SCRIPT_OUTPUT_BYTES {
                    output.pop_front();
                }
            }
            output.into_iter().collect::<Vec<u8>>()
        });
        if let Some(mut input) = child.stdin.take() {
            let writer = std::thread::spawn(move || {
                if let Some(bytes) = stdin {
                    let _ = input.write_all(&bytes);
                }
                drop(input);
            });
            let _ = writer;
        }
        let started = Instant::now();
        let status = loop {
            if cancel.is_some_and(CancelToken::is_canceled) {
                ssh::terminate(&mut child, Duration::from_secs(2));
                return Err(RemoteHostError::new(RemoteFailureCode::Canceled));
            }
            match child.try_wait() {
                Ok(Some(status)) => break status,
                Ok(None) if started.elapsed() < deadline => std::thread::sleep(Duration::from_millis(50)),
                _ => {
                    ssh::terminate(&mut child, Duration::from_secs(2));
                    return Err(RemoteHostError::new(RemoteFailureCode::InstallFailed));
                }
            }
        };
        let output = reader.join().unwrap_or_default();
        let marker = scripts::StatusMarker::parse(scripts::last_non_empty_line(&output).as_deref(), INSTALL_PREFIX);
        match marker {
            Some(marker) if marker.version == 1 && marker.words.len() == 1 => RemoteInstallResult::parse(&marker.words[0])
                .ok_or(RemoteHostError::new(RemoteFailureCode::InstallFailed)),
            _ => Err(RemoteHostError::new(if status.code() == Some(255) {
                RemoteFailureCode::SshConnectionFailed
            } else {
                RemoteFailureCode::InstallFailed
            })),
        }
    }
}

impl RemoteConnector for SshConnector {
    fn connect(
        &self,
        alias: &str,
        cancel: &CancelToken,
        on_closed: ClosedCallback,
    ) -> Result<Arc<dyn RemoteConnection>, RemoteHostError> {
        let config = ChannelConfig::processlama();
        let script = scripts::bootstrap(&config.build_id).ok_or(RemoteHostError::new(RemoteFailureCode::Internal))?;
        let child = self.start(alias, &script)?;
        let channel = Channel::connect(
            child,
            config,
            cancel,
            Box::new(move |failure| on_closed(failure.map(|failure| failure_code(&failure).code))),
        )
        .map_err(|failure| failure_code(&failure))?;
        let hello = channel.hello();
        match codec::hello(&hello.body, &hello.build_id) {
            Ok(parsed) => Ok(Arc::new(SshConnection { channel, hello: parsed })),
            Err(_) => {
                channel.close();
                Err(RemoteHostError::new(RemoteFailureCode::ProtocolMismatch))
            }
        }
    }

    fn install_helper(
        &self,
        alias: &str,
        artifact: &HelperArtifact,
        cancel: &CancelToken,
    ) -> Result<RemoteInstallResult, RemoteHostError> {
        let bytes = read_verified(&artifact.path, artifact.size, &artifact.sha256)
            .ok_or(RemoteHostError::new(RemoteFailureCode::HelperDamaged))?;
        let script = scripts::install(&artifact.build_id, &artifact.sha256, artifact.size)
            .ok_or(RemoteHostError::new(RemoteFailureCode::Internal))?;
        self.run_script(alias, &script, Some(bytes), Duration::from_millis(INSTALL_DEADLINE_MS), Some(cancel))
    }

    fn prune_helpers(&self, alias: &str, keep_build_id: &str) -> Result<RemoteInstallResult, RemoteHostError> {
        let script = scripts::prune(keep_build_id).ok_or(RemoteHostError::new(RemoteFailureCode::Internal))?;
        self.run_script(alias, &script, None, Duration::from_millis(PROBE_DEADLINE_MS), None)
    }

    fn remove_helpers(&self, alias: &str) -> Result<RemoteInstallResult, RemoteHostError> {
        let script =
            scripts::uninstall(processlama_wire::BUILD_ID).ok_or(RemoteHostError::new(RemoteFailureCode::Internal))?;
        self.run_script(alias, &script, None, Duration::from_millis(PROBE_DEADLINE_MS), None)
    }

    fn bundled_helper(&self, target: RemoteHelperTarget) -> Option<HelperArtifact> {
        self.helper_roots
            .iter()
            .find_map(|root| artifact_in(&root.join(target.wire_name()), target))
    }
}

/// Directories holding `<target>/` helper folders, in lookup order:
/// macOS `Contents/Resources/remote-helper`, Linux `lib/remote-helper` next to
/// the executable (or `../lib/processlama/remote-helper` for a system
/// install), Windows `remote-helper`; debug builds also look in
/// `PROCESSLAMA_REMOTE_HELPER_DIR` and the checkout's `build/` folders.
fn helper_roots() -> Vec<PathBuf> {
    let mut roots = Vec::new();
    if let Some(directory) = std::env::current_exe().ok().and_then(|exe| exe.parent().map(Path::to_path_buf)) {
        if cfg!(target_os = "macos") {
            roots.push(directory.join("../Resources/remote-helper"));
        } else if cfg!(windows) {
            roots.push(directory.join("remote-helper"));
        } else {
            roots.push(directory.join("lib/remote-helper"));
            roots.push(directory.join("../lib/processlama/remote-helper"));
        }
    }
    if cfg!(debug_assertions) {
        if let Some(directory) = std::env::var_os("PROCESSLAMA_REMOTE_HELPER_DIR").filter(|dir| !dir.is_empty()) {
            roots.push(PathBuf::from(directory));
        }
        if let Ok(current) = std::env::current_dir() {
            roots.push(current.join("build/remote-helper-dev"));
            roots.push(current.join("build/remote-helper"));
        }
    }
    roots
}

const DESCRIPTOR_KEYS: [&str; 8] = ["schema", "target", "buildId", "compatibility", "size", "sha256", "glibcFloor", "minimumSystem"];

fn sha256_hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes).iter().map(|byte| format!("{byte:02x}")).collect()
}

fn read_verified(path: &Path, size: u64, digest: &str) -> Option<Vec<u8>> {
    let bytes = std::fs::read(path).ok()?;
    (bytes.len() as u64 == size && sha256_hex(&bytes) == digest).then_some(bytes)
}

/// A verified helper in `directory`, or None.
fn artifact_in(directory: &Path, target: RemoteHelperTarget) -> Option<HelperArtifact> {
    let binary = directory.join(HELPER_EXECUTABLE);
    let descriptor: Value =
        serde_json::from_slice(&std::fs::read(directory.join(format!("{HELPER_EXECUTABLE}.json"))).ok()?).ok()?;
    let map = descriptor.as_object()?;
    if map.len() != DESCRIPTOR_KEYS.len()
        || !DESCRIPTOR_KEYS.iter().all(|key| map.contains_key(*key))
        || map.get("schema").and_then(Value::as_u64) != Some(1)
        || map.get("target").and_then(Value::as_str) != Some(target.wire_name())
        || map.get("buildId").and_then(Value::as_str) != Some(processlama_wire::BUILD_ID)
    {
        return None;
    }
    let size = map.get("size").and_then(Value::as_u64).filter(|&size| size > 0 && size <= HELPER_BYTES as u64)?;
    let digest = map.get("sha256").and_then(Value::as_str).filter(|digest| scripts::is_valid_sha256(digest))?;
    // Validate now so a damaged bundle is reported before any install.
    read_verified(&binary, size, digest)?;
    Some(HelperArtifact {
        target,
        build_id: processlama_wire::BUILD_ID.to_owned(),
        size,
        sha256: digest.to_owned(),
        path: binary,
    })
}

struct SshConnection {
    channel: Channel,
    hello: RemoteHelperHello,
}

impl RemoteConnection for SshConnection {
    fn hello(&self) -> &RemoteHelperHello {
        &self.hello
    }

    fn is_open(&self) -> bool {
        self.channel.is_open()
    }

    fn subscribe_telemetry(
        &self,
        cadence_ms: Option<u32>,
        polling_ms: u32,
        on_sample: Box<dyn Fn(TelemetryResult) + Send + Sync>,
    ) -> Result<Arc<dyn TelemetrySubscription>, String> {
        let decoder = Mutex::new(codec::TelemetryDecoder::default());
        let id = self.channel.subscribe(
            processlama_wire::contract::Topic::Telemetry.as_str(),
            codec::telemetry_arguments(cadence_ms, polling_ms),
            TELEMETRY_CREDIT as u64,
            Arc::new(move |data| {
                let result = decoder.lock().unwrap_or_else(std::sync::PoisonError::into_inner).decode(&data);
                on_sample(result.map_err(|_| ()));
            }),
        )?;
        Ok(Arc::new(SshTelemetry {
            channel: self.channel.clone(),
            id,
        }))
    }

    fn fetch_detail(&self, identity: ProcessIdentity) -> Result<ProcessDetail, String> {
        let value = self.channel.call(
            processlama_wire::contract::Method::ProcessDetail.as_str(),
            serde_json::json!({"pid": identity.pid, "start": identity.start_time_unix_ms}),
            false,
        )?;
        codec::decode_detail(&value).map_err(|_| "invalidRequest".to_owned())
    }

    fn send_signal(&self, identity: ProcessIdentity, signal: ProcessSignal) -> Result<SignalOutcome, String> {
        let value = self.channel.call(
            processlama_wire::contract::Method::ProcessSignal.as_str(),
            codec::signal_arguments(identity, signal),
            false,
        )?;
        codec::decode_signal_outcome(&value).map_err(|_| "invalidRequest".to_owned())
    }

    fn fetch_icons(&self, hashes: &[String]) -> Result<HashMap<String, Vec<u8>>, String> {
        let value = self.channel.call(
            processlama_wire::contract::Method::IconsFetch.as_str(),
            serde_json::json!({"hashes": hashes}),
            true,
        )?;
        let requested: HashSet<String> = hashes.iter().cloned().collect();
        codec::decode_icons(&value, &requested).map_err(|_| "invalidRequest".to_owned())
    }

    fn close(&self) {
        self.channel.close();
    }
}

struct SshTelemetry {
    channel: Channel,
    id: u64,
}

impl TelemetrySubscription for SshTelemetry {
    fn grant(&self, amount: u32) {
        self.channel.grant(self.id, amount);
    }

    fn set_cadence(&self, cadence_ms: Option<u32>, polling_ms: u32) -> Result<(), String> {
        self.channel
            .call(
                processlama_wire::contract::Method::TelemetryCadence.as_str(),
                codec::telemetry_arguments(cadence_ms, polling_ms),
                false,
            )
            .map(|_| ())
    }

    fn cancel(&self) {
        self.channel.unsubscribe(self.id);
    }
}
