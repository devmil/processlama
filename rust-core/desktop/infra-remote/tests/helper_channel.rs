//! End to end against the real helper: a fake launch script prints the start
//! line and execs `processlama-remote-helper --stdio`, so the channel,
//! handshake, telemetry decoding, calls and close run exactly as over SSH.
//!
//! Set `PROCESSLAMA_TEST_HELPER` to the helper binary, or build it first with
//! `cargo build -p processlama-remote-helper`.

use processlama_application::CancelToken;
use processlama_infra_remote::channel::{Channel, ChannelConfig, ChannelFailure};
use processlama_infra_remote::codec;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::time::Duration;

fn helper() -> Option<PathBuf> {
    if let Ok(path) = std::env::var("PROCESSLAMA_TEST_HELPER") {
        return Some(PathBuf::from(path));
    }
    let target = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../target");
    ["debug", "helper-dev", "release"]
        .iter()
        .map(|profile| target.join(profile).join("processlama-remote-helper"))
        .find(|path| path.is_file())
}

fn launch(script: &str) -> std::process::Child {
    Command::new("/bin/sh")
        .args(["-c", script])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("sh")
}

#[test]
fn talks_to_the_real_helper() {
    let Some(helper) = helper() else {
        eprintln!("skipped: no processlama-remote-helper build");
        return;
    };
    let script = format!("printf 'motd\\nPROCESSLAMA-BOOTSTRAP 1 start\\n'; exec '{}' --stdio", helper.display());
    let (closed_tx, closed_rx) = mpsc::channel();
    let channel = Channel::connect(
        launch(&script),
        ChannelConfig::processlama(),
        &CancelToken::default(),
        Box::new(move |failure| {
            let _ = closed_tx.send(failure);
        }),
    )
    .expect("handshake");
    let hello = channel.hello();
    let parsed = codec::hello(&hello.body, &hello.build_id).expect("hello body");
    assert_eq!(parsed.facts.helper_build_id, processlama_wire::BUILD_ID);

    // Telemetry: two decoded samples with the first one's topology.
    let (samples_tx, samples_rx) = mpsc::channel();
    let decoder = Mutex::new(codec::TelemetryDecoder::default());
    let id = channel
        .subscribe(
            "telemetry",
            codec::telemetry_arguments(Some(250), 250),
            2,
            Arc::new(move |data| {
                let snapshot = decoder.lock().unwrap().decode(&data);
                let _ = samples_tx.send(snapshot);
            }),
        )
        .expect("subscribe");
    let first = samples_rx.recv_timeout(Duration::from_secs(10)).expect("first sample").expect("decodes");
    assert!(!first.processes.is_empty());
    assert!(first.topology.is_some());
    channel.grant(id, 1);
    let second = samples_rx.recv_timeout(Duration::from_secs(10)).expect("second sample").expect("decodes");
    assert!(!second.processes.is_empty());

    // A call: the detail of this test process.
    let me = first
        .processes
        .iter()
        .find(|process| process.pid == std::process::id() as i32)
        .expect("the test process is in the sample");
    let detail = channel
        .call(
            "process.detail",
            serde_json::json!({"pid": me.pid, "start": me.start_time_unix_ms}),
            false,
        )
        .expect("detail");
    codec::decode_detail(&detail).expect("detail decodes");

    // An unknown method answers with a typed error.
    let error = channel.call("no.such.method", serde_json::json!({}), false).unwrap_err();
    assert!(!error.is_empty());

    channel.unsubscribe(id);
    channel.close();
    assert_eq!(closed_rx.recv_timeout(Duration::from_secs(5)).expect("closed"), None);
    assert!(!channel.is_open());
}

#[test]
fn reports_bootstrap_markers() {
    let (tx, _rx) = mpsc::channel();
    let failure = Channel::connect(
        launch("printf 'PROCESSLAMA-BOOTSTRAP 1 missing linux/x86_64\\n'"),
        ChannelConfig::processlama(),
        &CancelToken::default(),
        Box::new(move |failure| {
            let _ = tx.send(failure);
        }),
    )
    .err()
    .expect("no helper");
    let ChannelFailure::BootstrapMarker(marker) = &failure else {
        panic!("expected a marker, got {failure:?}");
    };
    assert_eq!(marker.words, ["missing", "linux/x86_64"]);
    let error = processlama_infra_remote::failure_code(&failure);
    assert_eq!(error.code, processlama_domain::RemoteFailureCode::HelperNotInstalled);
    assert!(error.host_target.is_some());
}

#[test]
fn reports_ssh_connection_failures() {
    let (tx, _rx) = mpsc::channel();
    let failure = Channel::connect(
        launch("exit 255"),
        ChannelConfig::processlama(),
        &CancelToken::default(),
        Box::new(move |failure| {
            let _ = tx.send(failure);
        }),
    )
    .err()
    .expect("ssh failed");
    assert_eq!(failure, ChannelFailure::SshConnectionFailed);
}

#[test]
fn rejects_a_hello_of_another_build() {
    let Some(helper) = helper() else {
        return;
    };
    let mut config = ChannelConfig::processlama();
    config.build_id = "f".repeat(40);
    let script = format!("printf 'PROCESSLAMA-BOOTSTRAP 1 start\\n'; exec '{}' --stdio", helper.display());
    let (tx, _rx) = mpsc::channel();
    let failure = Channel::connect(launch(&script), config, &CancelToken::default(), Box::new(move |f| {
        let _ = tx.send(f);
    }))
    .err()
    .expect("mismatch");
    assert_eq!(failure, ChannelFailure::BuildMismatch);
}
