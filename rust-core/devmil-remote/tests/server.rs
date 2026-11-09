use devmil_remote::frame::{self, FrameClock};
use devmil_remote::server::{self, CallError, Handler, Publisher, ServeEnd, ServerConfig};
use serde_json::{Map, Value, json};
use std::io::{PipeReader, PipeWriter, Write};
use std::sync::atomic::AtomicBool;
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::Duration;

const BUILD: &str = "0000000000000000000000000000000000000001";
const NONCE: &str = "00112233445566778899aabbccddeeff";

#[derive(Default)]
struct TestHandler {
    publishers: Mutex<Vec<Publisher>>,
    release_bulk: Mutex<Option<mpsc::Receiver<()>>>,
    block_interactive: Mutex<Option<mpsc::Receiver<()>>>,
}

impl Handler for TestHandler {
    fn hello_body(&self) -> Value {
        json!({"os": "linux"})
    }

    fn is_bulk(&self, method: &str) -> bool {
        method == "bulk"
    }

    fn call(&self, method: &str, arguments: &Map<String, Value>) -> Result<Value, CallError> {
        match method {
            "echo" => Ok(arguments.get("value").cloned().unwrap_or(Value::Null)),
            "bulk" => {
                if let Some(release) = self.release_bulk.lock().unwrap().take() {
                    let _ = release.recv_timeout(Duration::from_secs(10));
                }
                Ok(json!("bulk-done"))
            }
            "block" => {
                if let Some(release) = self.block_interactive.lock().unwrap().take() {
                    let _ = release.recv_timeout(Duration::from_secs(10));
                }
                Ok(json!("unblocked"))
            }
            _ => Err(CallError("unsupportedCommand")),
        }
    }

    fn subscribe(
        &self,
        topic: &str,
        _arguments: &Map<String, Value>,
        publisher: Publisher,
    ) -> Result<Value, CallError> {
        if topic != "telemetry" {
            return Err(CallError("unsupportedTopic"));
        }
        self.publishers.lock().unwrap().push(publisher);
        Ok(json!({}))
    }
}

struct Client {
    to_server: PipeWriter,
    from_server: PipeReader,
    clock: FrameClock,
    incarnation: String,
    next_id: u64,
    server: Option<JoinHandle<ServeEnd>>,
}

impl Client {
    fn start(handler: Arc<TestHandler>, configure: impl FnOnce(&mut ServerConfig)) -> Self {
        let (server_in, to_server) = std::io::pipe().unwrap();
        let (from_server, server_out) = std::io::pipe().unwrap();
        let mut config = ServerConfig::new("test-helper", BUILD);
        configure(&mut config);
        let server = std::thread::spawn(move || {
            server::serve(
                &config,
                handler,
                server_in,
                server_out,
                &FrameClock::new(),
                &AtomicBool::new(false),
            )
        });
        let mut client = Self {
            to_server,
            from_server,
            clock: FrameClock::new(),
            incarnation: String::new(),
            next_id: 0,
            server: Some(server),
        };
        let hello = client.read();
        assert_eq!(hello["kind"], "hello");
        assert_eq!(hello["buildId"], BUILD);
        assert_eq!(hello["body"]["os"], "linux");
        client.incarnation = hello["incarnation"].as_str().unwrap().to_owned();
        client
    }

    fn acknowledge(&mut self) {
        let ack = json!({
            "kind": "ack",
            "protocolMajor": 1,
            "buildId": BUILD,
            "incarnation": self.incarnation,
            "nonce": NONCE,
        });
        self.write_raw(&ack);
    }

    fn write_raw(&mut self, value: &Value) {
        frame::write_frame(&mut self.to_server, &serde_json::to_vec(value).unwrap()).unwrap();
        self.to_server.flush().unwrap();
    }

    fn send(&mut self, kind: &str, payload: Value) -> u64 {
        self.next_id += 1;
        let envelope = json!({
            "protocolMajor": 1,
            "nonce": NONCE,
            "incarnation": self.incarnation,
            "requestId": self.next_id,
            "kind": kind,
            "payload": payload,
        });
        self.write_raw(&envelope);
        self.next_id
    }

    fn read(&mut self) -> Value {
        let bytes = frame::read_frame(&mut self.from_server, frame::MAX_FRAME_BYTES, &self.clock)
            .expect("frame");
        serde_json::from_slice(&bytes).unwrap()
    }

    fn finish(mut self) -> ServeEnd {
        drop(self.to_server);
        self.server.take().unwrap().join().unwrap()
    }
}

fn open(handler: Arc<TestHandler>) -> Client {
    let mut client = Client::start(handler, |_| {});
    client.acknowledge();
    client
}

#[test]
fn answers_calls_and_errors() {
    let mut client = open(Arc::default());
    let echo = client.send("call", json!({"method": "echo", "args": {"value": 7}}));
    let result = client.read();
    assert_eq!(result["kind"], "result");
    assert_eq!(result["requestId"], echo);
    assert_eq!(result["payload"], json!({"ok": 7}));
    client.send("call", json!({"method": "nope", "args": {}}));
    assert_eq!(
        client.read()["payload"],
        json!({"error": {"code": "unsupportedCommand"}})
    );
    assert_eq!(client.finish(), ServeEnd::InputClosed);
}

#[test]
fn a_wrong_acknowledgement_is_rejected() {
    let mut client = Client::start(Arc::default(), |_| {});
    client.write_raw(&json!({
        "kind": "ack",
        "protocolMajor": 1,
        "buildId": "0000000000000000000000000000000000000002",
        "incarnation": client.incarnation,
        "nonce": NONCE,
    }));
    let fatal = client.read();
    assert_eq!(fatal["kind"], "fatal");
    assert_eq!(fatal["payload"]["code"], "handshakeRejected");
    assert_eq!(client.finish(), ServeEnd::HandshakeRejected);
}

#[test]
fn interactive_calls_do_not_wait_behind_bulk_calls() {
    let handler = Arc::new(TestHandler::default());
    let (release, waiting) = mpsc::channel();
    *handler.release_bulk.lock().unwrap() = Some(waiting);
    let mut client = open(Arc::clone(&handler));
    let bulk = client.send("call", json!({"method": "bulk", "args": {}}));
    let echo = client.send("call", json!({"method": "echo", "args": {"value": 1}}));
    let first = client.read();
    assert_eq!(first["requestId"], echo);
    release.send(()).unwrap();
    let second = client.read();
    assert_eq!(second["requestId"], bulk);
    client.finish();
}

#[test]
fn calls_beyond_the_limit_are_answered_capacity() {
    let handler = Arc::new(TestHandler::default());
    let (release, waiting) = mpsc::channel();
    *handler.block_interactive.lock().unwrap() = Some(waiting);
    let mut client = Client::start(Arc::clone(&handler), |config| config.concurrent_calls = 1);
    client.acknowledge();
    let blocked = client.send("call", json!({"method": "block", "args": {}}));
    let refused = client.send("call", json!({"method": "echo", "args": {}}));
    let answer = client.read();
    assert_eq!(answer["requestId"], refused);
    assert_eq!(answer["payload"]["error"]["code"], "capacity");
    release.send(()).unwrap();
    assert_eq!(client.read()["requestId"], blocked);
    client.finish();
}

#[test]
fn a_queued_call_can_be_canceled() {
    let handler = Arc::new(TestHandler::default());
    let (release, waiting) = mpsc::channel();
    *handler.block_interactive.lock().unwrap() = Some(waiting);
    let mut client = Client::start(Arc::clone(&handler), |config| {
        config.interactive_workers = 1;
    });
    client.acknowledge();
    let blocked = client.send("call", json!({"method": "block", "args": {}}));
    let queued = client.send("call", json!({"method": "echo", "args": {}}));
    std::thread::sleep(Duration::from_millis(100));
    client.send("cancel", json!({"target": queued}));
    let canceled = client.read();
    assert_eq!(canceled["requestId"], queued);
    assert_eq!(canceled["payload"]["error"]["code"], "canceled");
    release.send(()).unwrap();
    assert_eq!(client.read()["requestId"], blocked);
    client.finish();
}

#[test]
fn publications_respect_credit_and_keep_only_the_newest() {
    let handler = Arc::new(TestHandler::default());
    let mut client = open(Arc::clone(&handler));
    let subscription = client.send(
        "subscribe",
        json!({"topic": "telemetry", "args": {}, "credit": 1}),
    );
    assert_eq!(client.read()["payload"], json!({"ok": {}}));
    let publisher = handler.publishers.lock().unwrap()[0].clone();
    assert_eq!(publisher.id(), subscription);
    assert!(publisher.has_credit());
    for sample in 1..=5 {
        assert!(publisher.publish(json!(sample)));
    }
    let first = client.read();
    assert_eq!(first["kind"], "publication");
    assert_eq!(first["payload"]["data"], 1);
    assert_eq!(first["payload"]["sequence"], 1);
    assert!(!publisher.has_credit());
    assert!(!publisher.wait_for_credit(Duration::from_millis(50)));
    let waiter = {
        let publisher = publisher.clone();
        std::thread::spawn(move || publisher.wait_for_credit(Duration::from_secs(10)))
    };
    client.send("credit", json!({"target": subscription, "amount": 2}));
    let newest = client.read();
    assert_eq!(newest["payload"]["data"], 5);
    assert_eq!(newest["payload"]["sequence"], 2);
    assert!(waiter.join().unwrap(), "credit wakes a waiting publisher");
    assert!(publisher.publish(json!(6)));
    assert_eq!(client.read()["payload"]["data"], 6);
    client.send("unsubscribe", json!({"target": subscription}));
    client.send("ping", json!({}));
    assert_eq!(client.read()["kind"], "pong");
    assert!(publisher.is_closed());
    assert!(!publisher.publish(json!(7)));
    client.finish();
}

#[test]
fn ping_shutdown_and_violations() {
    let mut client = open(Arc::default());
    let ping = client.send("ping", json!({}));
    let pong = client.read();
    assert_eq!(
        (pong["kind"].as_str(), pong["requestId"].as_u64()),
        (Some("pong"), Some(ping))
    );
    client.send("shutdown", json!({}));
    assert_eq!(client.read()["kind"], "goodbye");
    assert_eq!(client.finish(), ServeEnd::Shutdown);

    let mut client = open(Arc::default());
    client.write_raw(&json!({
        "protocolMajor": 1,
        "nonce": "ffffffffffffffffffffffffffffffff",
        "incarnation": client.incarnation,
        "requestId": 1,
        "kind": "ping",
        "payload": {},
    }));
    let fatal = client.read();
    assert_eq!(fatal["payload"]["code"], "protocolViolation");
    assert_eq!(client.finish(), ServeEnd::ProtocolViolation);
}
