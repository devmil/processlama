mod common;

use common::Helper;
use serde_json::{Value, json};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64
}

/// Reads frames until one satisfies `matches`, failing after `timeout`.
fn read_until(helper: &mut Helper, timeout: Duration, matches: impl Fn(&Value) -> bool) -> Value {
    let started = Instant::now();
    loop {
        assert!(started.elapsed() < timeout, "no matching frame");
        let frame = helper.read();
        if matches(&frame) {
            return frame;
        }
    }
}

fn subscribe(helper: &mut Helper, cadence_ms: Option<u64>, credit: u64) -> u64 {
    let id = helper.send(
        "subscribe",
        json!({
            "topic": "telemetry",
            "args": {"cadenceMs": cadence_ms, "pollingMs": 1000},
            "credit": credit,
        }),
    );
    let answer = read_until(helper, Duration::from_secs(10), |frame| {
        frame["kind"] == "result" && frame["requestId"] == id
    });
    assert_eq!(answer["payload"], json!({"ok": {}}));
    id
}

fn publication(helper: &mut Helper) -> Value {
    read_until(helper, Duration::from_secs(20), |frame| {
        frame["kind"] == "publication"
    })
}

/// True when no publication arrives within `window` (pings keep frames flowing).
fn quiet_for(helper: &mut Helper, window: Duration) -> bool {
    quiet_for_rest(helper, window)
}

fn quiet_for_rest(helper: &mut Helper, window: Duration) -> bool {
    let started = Instant::now();
    loop {
        if started.elapsed() >= window {
            return true;
        }
        let ping = helper.send("ping", json!({}));
        loop {
            let frame = helper.read();
            if frame["kind"] == "publication" {
                return false;
            }
            if frame["kind"] == "pong" && frame["requestId"] == ping {
                break;
            }
        }
        std::thread::sleep(Duration::from_millis(200));
    }
}

fn row_of(sample: &Value, pid: u32) -> Option<usize> {
    sample["topology"]["pid"]
        .as_array()?
        .iter()
        .position(|value| value.as_u64() == Some(u64::from(pid)))
}

#[test]
fn the_first_sample_carries_topology_and_metrics_follow_without_backlog() {
    let mut helper = Helper::start();
    helper.acknowledge();
    let subscription = subscribe(&mut helper, Some(250), 1);
    let first = publication(&mut helper);
    let data = &first["payload"]["data"];
    assert_eq!(first["payload"]["subscription"], subscription);
    assert!(data["topology"].is_object());
    let rows = data["topology"]["pid"].as_array().unwrap().len();
    assert!(rows > 0);
    for column in ["cpu", "rss", "status", "ioAvail"] {
        assert_eq!(data["metrics"][column].as_array().unwrap().len(), rows);
    }
    let version = data["topologyVersion"].clone();

    // Without credit nothing queues up behind the client.
    assert!(quiet_for(&mut helper, Duration::from_millis(1500)));

    let granted_at = now_ms();
    helper.send("credit", json!({"target": subscription, "amount": 1}));
    let next = publication(&mut helper);
    let captured = next["payload"]["data"]["capturedAtMs"].as_u64().unwrap();
    assert!(
        captured + 600 >= granted_at,
        "the newest sample wins: captured {captured}, granted {granted_at}"
    );
    if next["payload"]["data"]["topology"].is_null() {
        assert_eq!(next["payload"]["data"]["topologyVersion"], version);
    }
    assert!(
        quiet_for(&mut helper, Duration::from_millis(800)),
        "one credit, one sample"
    );
}

#[test]
fn pausing_stops_samples_and_resuming_samples_right_away() {
    let mut helper = Helper::start();
    helper.acknowledge();
    let subscription = subscribe(&mut helper, Some(60_000), 1);
    let _first = publication(&mut helper);
    let paused = helper.call(
        "telemetry.cadence",
        json!({"cadenceMs": null, "pollingMs": 1000}),
    );
    assert_eq!(paused, json!({"ok": {}}));
    helper.send("credit", json!({"target": subscription, "amount": 4}));
    assert!(quiet_for(&mut helper, Duration::from_millis(1500)));
    let resumed = helper.call(
        "telemetry.cadence",
        json!({"cadenceMs": 60_000, "pollingMs": 1000}),
    );
    assert_eq!(resumed, json!({"ok": {}}));
    let _sample = publication(&mut helper);
}

#[test]
fn one_telemetry_subscription_per_connection() {
    let mut helper = Helper::start();
    helper.acknowledge();
    subscribe(&mut helper, Some(1000), 1);
    let id = helper.send(
        "subscribe",
        json!({"topic": "telemetry", "args": {"cadenceMs": 1000, "pollingMs": 1000}, "credit": 1}),
    );
    let answer = read_until(&mut helper, Duration::from_secs(10), |frame| {
        frame["kind"] == "result" && frame["requestId"] == id
    });
    assert_eq!(answer["payload"]["error"]["code"], "capacity");
    let other = helper.send(
        "subscribe",
        json!({"topic": "other", "args": {}, "credit": 1}),
    );
    let refused = read_until(&mut helper, Duration::from_secs(10), |frame| {
        frame["kind"] == "result" && frame["requestId"] == other
    });
    assert_eq!(refused["payload"]["error"]["code"], "unsupportedTopic");
}

#[test]
fn signals_details_and_host_facts() {
    let mut child = Command::new("sleep")
        .arg("60")
        .stdin(Stdio::null())
        .spawn()
        .unwrap();
    let mut helper = Helper::start();
    helper.acknowledge();
    let subscription = subscribe(&mut helper, Some(250), 1);
    let mut sample = publication(&mut helper);
    // The child may start after the first sample's topology.
    while row_of(&sample["payload"]["data"], child.id()).is_none() {
        helper.send("credit", json!({"target": subscription, "amount": 1}));
        sample = publication(&mut helper);
    }
    let data = &sample["payload"]["data"];
    let row = row_of(data, child.id()).unwrap();
    let start = data["topology"]["start"][row].as_u64().unwrap();
    let pid = child.id();

    let detail = helper.call("process.detail", json!({"pid": pid, "start": start}));
    let detail = &detail["ok"];
    assert_eq!(detail["pid"], pid);
    for section in ["files", "sockets", "threads", "security"] {
        let state = detail[section]["state"].as_str().unwrap();
        assert!(
            ["available", "restricted", "unsupported", "notFound"].contains(&state),
            "{section}: {state}"
        );
    }
    assert_eq!(detail["files"]["state"], "available");

    let wrong = helper.call(
        "process.signal",
        json!({"pid": pid, "start": start + 1, "signal": "terminate"}),
    );
    assert_eq!(wrong["ok"]["outcome"], "notFound");
    let sent = helper.call(
        "process.signal",
        json!({"pid": pid, "start": start, "signal": "terminate"}),
    );
    assert_eq!(sent["ok"]["outcome"], "sent");
    let status = child.wait().unwrap();
    assert!(!status.success());

    if let Some(init_row) = row_of(data, 1) {
        // SIGCONT permissions differ across Unix hosts. Compare the remote
        // response with the same native operation, rather than assuming Linux
        // /proc or an unprivileged runner. No test suspends this process.
        let expected = match rustix::process::kill_process(
            rustix::process::Pid::INIT,
            rustix::process::Signal::CONT,
        ) {
            Ok(()) => "sent",
            Err(rustix::io::Errno::PERM) => "denied",
            Err(error) => panic!("unexpected native resume result: {error}"),
        };
        let init_start = data["topology"]["start"][init_row].as_u64().unwrap();
        let result = helper.call(
            "process.signal",
            json!({"pid": 1, "start": init_start, "signal": "resume"}),
        );
        assert_eq!(result["ok"]["outcome"], expected);
    }

    let invalid = helper.call(
        "process.signal",
        json!({"pid": pid, "start": start, "signal": "hup"}),
    );
    assert_eq!(invalid["error"]["code"], "invalidRequest");

    let facts = helper.call("host.facts", json!({}));
    assert!(facts["ok"]["cpuCount"].as_u64().unwrap() >= 1);
    assert!(facts["ok"]["kernel"].as_str().is_some());
}
