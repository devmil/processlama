//! The local Linux network telemetry service.

use processlama_application::{NetworkServiceSetup, NetworkSetupFailure};
use std::path::PathBuf;
use std::time::{Duration, SystemTime};

/// Shared with the Rust engine and the network helper.
pub const SNAPSHOT_PATH: &str = "/run/processlama/network.json";
const MAXIMUM_SNAPSHOT_AGE: Duration = Duration::from_secs(5);

pub struct LinuxNetworkService;

impl LinuxNetworkService {
    fn installer() -> Option<PathBuf> {
        let executable = std::env::current_exe().ok()?.canonicalize().ok()?;
        let directory = executable.parent()?;
        // The portable bundle keeps the installer next to the executable;
        // packaged layouts under lib/processlama.
        [
            directory.join("network/install-network-service.sh"),
            directory.join("../lib/processlama/network/install-network-service.sh"),
        ]
        .into_iter()
        .find(|candidate| candidate.is_file())
    }
}

impl NetworkServiceSetup for LinuxNetworkService {
    fn is_supported(&self) -> bool {
        cfg!(target_os = "linux")
    }

    fn is_available(&self) -> bool {
        let Ok(metadata) = std::fs::metadata(SNAPSHOT_PATH) else {
            return false;
        };
        let Ok(modified) = metadata.modified() else {
            return false;
        };
        SystemTime::now()
            .duration_since(modified)
            .is_ok_and(|age| age <= MAXIMUM_SNAPSHOT_AGE)
    }

    fn install_or_repair(&self) -> Result<(), NetworkSetupFailure> {
        let installer = Self::installer().ok_or(NetworkSetupFailure::InstallerMissing)?;
        let status = std::process::Command::new("pkexec")
            .arg(&installer)
            .status()
            .map_err(|_| NetworkSetupFailure::AuthorizationUnavailable)?;
        match status.code() {
            Some(0) => Ok(()),
            Some(126) => Err(NetworkSetupFailure::AuthorizationCancelled),
            _ => Err(NetworkSetupFailure::InstallFailed),
        }
    }
}
