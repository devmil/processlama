//! Opt-in: the whole connector against a real host over the system OpenSSH.
//!
//!   PROCESSLAMA_SSH_CONFIG=/abs/ssh_config PROCESSLAMA_TEST_SSH_ALIAS=host \
//!   PROCESSLAMA_REMOTE_HELPER_DIR=/abs/build/remote-helper \
//!   cargo test -p processlama-infra-remote --test ssh_host -- --ignored
//!
//! Removes any installed helper first, installs the bundled one, streams
//! telemetry, calls the helper, and removes the helper again.

use processlama_application::{CancelToken, RemoteConnector};
use processlama_domain::{RemoteFailureCode, RemoteInstallResult};
use processlama_infra_remote::SshConnector;
use std::sync::mpsc;
use std::time::Duration;

#[test]
#[ignore = "needs a reachable SSH host"]
fn installs_streams_and_removes_on_a_real_host() {
    let alias = std::env::var("PROCESSLAMA_TEST_SSH_ALIAS").expect("PROCESSLAMA_TEST_SSH_ALIAS");
    let connector = SshConnector::new();
    assert_eq!(
        connector.remove_helpers(&alias).expect("clean start"),
        RemoteInstallResult::Ok
    );

    let cancel = CancelToken::default();
    let Err(missing) = connector.connect(&alias, &cancel, Box::new(|_| {})) else {
        panic!("no helper yet");
    };
    assert_eq!(missing.code, RemoteFailureCode::HelperNotInstalled);
    let target = missing.host_target.expect("the host's platform");

    let artifact = connector
        .bundled_helper(target)
        .expect("a bundled helper for the host");
    assert_eq!(
        connector
            .install_helper(&alias, &artifact, &cancel)
            .expect("install"),
        RemoteInstallResult::Ok
    );

    let (closed_tx, closed_rx) = mpsc::channel();
    let connection = connector
        .connect(
            &alias,
            &cancel,
            Box::new(move |failure| {
                let _ = closed_tx.send(failure);
            }),
        )
        .expect("connect");
    assert_eq!(connection.hello().facts.target, target);

    let (samples_tx, samples_rx) = mpsc::channel();
    let subscription = connection
        .subscribe_telemetry(
            Some(500),
            500,
            Box::new(move |sample| {
                let _ = samples_tx.send(sample);
            }),
        )
        .expect("subscribe");
    let first = samples_rx
        .recv_timeout(Duration::from_secs(20))
        .expect("a sample")
        .expect("decodes");
    assert!(!first.processes.is_empty());
    subscription.grant(1);
    samples_rx
        .recv_timeout(Duration::from_secs(20))
        .expect("a second sample")
        .expect("decodes");
    subscription.set_cadence(None, 1000).expect("pause");

    let process = &first.processes[0];
    connection.fetch_detail(process.identity()).expect("detail");
    let hashes: Vec<String> = first
        .processes
        .iter()
        .filter_map(|process| match &process.icon {
            Some(processlama_domain::ProcessIconRef::Remote(hash)) => Some(hash.clone()),
            _ => None,
        })
        .take(4)
        .collect();
    if !hashes.is_empty() {
        let icons = connection.fetch_icons(&hashes).expect("icons");
        assert!(!icons.is_empty());
    }

    subscription.cancel();
    connection.close();
    assert_eq!(
        closed_rx
            .recv_timeout(Duration::from_secs(10))
            .expect("closed"),
        None
    );
    assert_eq!(
        connector.remove_helpers(&alias).expect("remove"),
        RemoteInstallResult::Ok
    );
}
