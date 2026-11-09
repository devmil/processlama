//! ProcessLama telemetry constants shared by the engine configuration and the
//! Linux network service.

/// Snapshot written by `processlama-network-helper` and read by the engine.
/// `fixtures/linux_network_snapshot_path.txt` pins the same value for the Dart
/// setup repository and the network helper.
pub const LINUX_NETWORK_SNAPSHOT_PATH: &str = "/run/processlama/network.json";

#[cfg(test)]
mod tests {
    use super::LINUX_NETWORK_SNAPSHOT_PATH;

    #[test]
    fn linux_network_snapshot_path_matches_shared_fixture() {
        let fixture = include_str!("../../../fixtures/linux_network_snapshot_path.txt");
        assert_eq!(fixture.trim(), LINUX_NETWORK_SNAPSHOT_PATH);
    }
}
