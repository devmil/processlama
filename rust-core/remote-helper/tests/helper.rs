mod common;

use common::Helper;
use processlama_wire::messages::HelloBody;
use serde_json::{Value, json};
use std::time::{Duration, Instant};

#[test]
fn version_reports_the_build_id() {
    let output = Helper::command().arg("--version").output().unwrap();
    assert!(output.status.success());
    let version: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(version["buildId"], processlama_wire::BUILD_ID);
    assert_eq!(version["protocolMajor"], 1);
}

#[test]
fn unknown_arguments_are_a_usage_error() {
    let output = Helper::command().arg("--bogus").output().unwrap();
    assert_eq!(output.status.code(), Some(2));
    assert!(output.stdout.is_empty());
}

#[test]
fn hello_carries_a_valid_body_and_the_session_answers_pings() {
    let mut helper = Helper::start();
    assert_eq!(helper.hello["magic"], processlama_wire::contract::MAGIC);
    assert_eq!(helper.hello["buildId"], processlama_wire::BUILD_ID);
    HelloBody::parse(&helper.hello["body"]).expect("hello body validates");
    helper.acknowledge();
    let ping = helper.send("ping", json!({}));
    let pong = helper.read();
    assert_eq!(pong["kind"], "pong");
    assert_eq!(pong["requestId"], ping);
    let unknown = helper.call("process.nothing", json!({}));
    assert_eq!(unknown["error"]["code"], "unsupportedCommand");
    helper.send("shutdown", json!({}));
    assert_eq!(helper.read()["kind"], "goodbye");
    assert!(helper.wait().success());
}

#[test]
fn another_build_id_is_answered_with_fatal() {
    let mut helper = Helper::start();
    helper.acknowledge_build("0000000000000000000000000000000000009999");
    let fatal = helper.read();
    assert_eq!(fatal["kind"], "fatal");
    assert_eq!(fatal["payload"]["code"], "handshakeRejected");
    assert_eq!(helper.wait().code(), Some(2));
}

#[test]
fn a_helper_without_acknowledgement_exits_after_the_hello_deadline() {
    let started = Instant::now();
    let mut helper = Helper::start();
    // Keep stdin open but silent.
    let status = loop {
        if let Some(status) = helper.child.try_wait().unwrap() {
            break status;
        }
        assert!(
            started.elapsed() < Duration::from_secs(20),
            "helper did not exit"
        );
        std::thread::sleep(Duration::from_millis(100));
    };
    assert_eq!(status.code(), Some(2));
    assert!(started.elapsed() >= Duration::from_secs(9));
}

#[test]
fn end_of_input_ends_the_helper() {
    let mut helper = Helper::start();
    helper.acknowledge();
    assert!(helper.wait().success());
}

#[test]
fn self_check_samples_processes() {
    let output = Helper::command().arg("--self-check").output().unwrap();
    assert!(output.status.success());
    let report: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(report["ok"], true);
    assert!(report["processes"].as_u64().unwrap() > 0);
}

#[test]
fn remove_state_deletes_only_the_helper_cache() {
    let home = std::env::temp_dir().join(format!("processlama-helper-home-{}", std::process::id()));
    let cache = home
        .join(processlama_wire::contract::CACHE_ROOT)
        .join("icons");
    std::fs::create_dir_all(&cache).unwrap();
    std::fs::write(cache.join("x.png"), b"png").unwrap();
    let keep = home.join(".cache/other");
    std::fs::create_dir_all(&keep).unwrap();
    let output = Helper::command()
        .arg("--remove-state")
        .env("HOME", &home)
        .output()
        .unwrap();
    assert!(output.status.success());
    let report: Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(report["removed"], true);
    assert!(!home.join(processlama_wire::contract::CACHE_ROOT).exists());
    assert!(keep.exists());
    // Removing again is still a success.
    let again = Helper::command()
        .arg("--remove-state")
        .env("HOME", &home)
        .output()
        .unwrap();
    assert!(again.status.success());
    std::fs::remove_dir_all(&home).unwrap();
}
