//! Platform adapters.

mod appimage;
#[cfg(target_os = "macos")]
pub mod macos;
mod network;
mod updates;

pub use network::LinuxNetworkService;
pub use updates::{ReleaseUpdateChecker, parse_release_manifest};
