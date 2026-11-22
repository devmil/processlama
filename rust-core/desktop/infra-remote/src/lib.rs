//! Remote hosts over the system OpenSSH client.

use processlama_application::{
    CancelToken, ClosedCallback, HelperArtifact, RemoteConnection, RemoteConnector, RemoteHostError,
};
use processlama_domain::{RemoteFailureCode, RemoteHelperTarget, RemoteInstallResult};
use std::sync::Arc;

/// Placeholder until the SSH transport lands.
pub struct SshConnector;

impl RemoteConnector for SshConnector {
    fn connect(
        &self,
        _alias: &str,
        _cancel: &CancelToken,
        _on_closed: ClosedCallback,
    ) -> Result<Arc<dyn RemoteConnection>, RemoteHostError> {
        Err(RemoteHostError::new(RemoteFailureCode::SshMissing))
    }
    fn install_helper(&self, _: &str, _: &HelperArtifact, _: &CancelToken) -> Result<RemoteInstallResult, RemoteHostError> {
        Err(RemoteHostError::new(RemoteFailureCode::SshMissing))
    }
    fn prune_helpers(&self, _: &str, _: &str) -> Result<RemoteInstallResult, RemoteHostError> {
        Ok(RemoteInstallResult::Ok)
    }
    fn remove_helpers(&self, _: &str) -> Result<RemoteInstallResult, RemoteHostError> {
        Err(RemoteHostError::new(RemoteFailureCode::SshMissing))
    }
    fn bundled_helper(&self, _: RemoteHelperTarget) -> Option<HelperArtifact> {
        None
    }
}
