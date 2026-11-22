//! Platform adapters.

mod network;
mod updates;
#[cfg(target_os = "macos")]
pub mod macos;

pub use network::LinuxNetworkService;
pub use updates::{ReleaseUpdateChecker, parse_release_manifest};
