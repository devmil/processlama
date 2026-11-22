//! The client side of one helper connection over an `ssh` child's standard
//! input and output: the launch script's status lines, the hello and its
//! acknowledgement, calls with deadlines, credit-limited subscriptions,
//! pings and liveness, and a bounded graceful close.

use crate::scripts::{StatusMarker, last_non_empty_line};
use crate::ssh;
use devmil_remote::frame::{self, FrameClock, FrameError};
use processlama_application::CancelToken;
use serde_json::{Map, Value, json};
use std::collections::HashMap;
use std::io::{Cursor, Read};
use std::process::{Child, ChildStdin};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::time::{Duration, Instant};

/// Fixed protocol and timing parameters of one product's helper.
#[derive(Clone, Debug)]
pub struct ChannelConfig {
    pub magic: &'static str,
    pub build_id: String,
    pub bootstrap_prefix: &'static str,
    pub protocol_major: u64,
    pub hello_deadline: Duration,
    pub interactive_deadline: Duration,
    pub bulk_deadline: Duration,
    pub ping_interval: Duration,
    pub liveness_timeout: Duration,
    pub shutdown_grace: Duration,
    pub exit_drain_grace: Duration,
    pub max_concurrent_calls: usize,
    pub max_frame_bytes: usize,
    pub hello_frame_bytes: usize,
}

impl ChannelConfig {
    pub fn processlama() -> Self {
        use processlama_wire::contract as c;
        Self {
            magic: c::MAGIC,
            build_id: processlama_wire::BUILD_ID.to_owned(),
            bootstrap_prefix: c::BOOTSTRAP_PREFIX,
            protocol_major: c::PROTOCOL_MAJOR,
            hello_deadline: Duration::from_millis(c::HELLO_DEADLINE_MS),
            interactive_deadline: Duration::from_millis(c::INTERACTIVE_DEADLINE_MS),
            bulk_deadline: Duration::from_millis(c::BULK_DEADLINE_MS),
            ping_interval: Duration::from_millis(c::PING_DEADLINE_MS),
            liveness_timeout: Duration::from_millis(c::LIVENESS_DEADLINE_MS),
            shutdown_grace: Duration::from_secs(5),
            exit_drain_grace: Duration::from_secs(2),
            max_concurrent_calls: c::CONCURRENT_CALLS,
            max_frame_bytes: c::FRAME_BYTES,
            hello_frame_bytes: c::HELLO_BYTES,
        }
    }
}

/// Why a channel could not open or stopped.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ChannelFailure {
    /// `ssh` exited with 255 before a hello.
    SshConnectionFailed,
    /// The launch script ended with a status marker instead of a helper.
    BootstrapMarker(StatusMarker),
    /// The output before the hello was neither a marker nor a start line.
    BootstrapFailed,
    HelloTimeout,
    ProtocolMismatch,
    BuildMismatch,
    ProtocolViolation,
    FrameTooLarge,
    HeartbeatLost,
    Disconnected,
    Canceled,
    Fatal,
}

/// A validated hello. `body` is the product's part.
#[derive(Clone, Debug)]
pub struct Hello {
    pub build_id: String,
    pub incarnation: String,
    pub frame_bytes: usize,
    pub concurrent_calls: usize,
    pub body: Value,
}

pub type ClosedHandler = Box<dyn FnOnce(Option<ChannelFailure>) + Send>;
type Publication = Arc<dyn Fn(Value) + Send + Sync>;

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Stage {
    Handshake,
    Open,
    Closing,
    Closed,
}

struct Inner {
    config: ChannelConfig,
    stage: Mutex<Stage>,
    child: Mutex<Option<Child>>,
    stdin: Mutex<Option<ChildStdin>>,
    hello: Mutex<Option<Hello>>,
    nonce: Mutex<String>,
    next_request: AtomicU64,
    pending: Mutex<HashMap<u64, mpsc::SyncSender<Result<Value, String>>>>,
    subscriptions: Mutex<HashMap<u64, Publication>>,
    last_frame: Mutex<Instant>,
    last_ping: Mutex<Instant>,
    clock: FrameClock,
    goodbye: (Mutex<bool>, Condvar),
    on_closed: Mutex<Option<ClosedHandler>>,
    stdout_done: AtomicBool,
}

/// An open channel. Cloning shares it.
#[derive(Clone)]
pub struct Channel {
    inner: Arc<Inner>,
}

enum Handshake {
    Open,
    Failed(ChannelFailure),
}

impl Channel {
    /// Performs the handshake on `child` and returns the open channel. On
    /// failure the child is terminated.
    pub fn connect(
        mut child: Child,
        config: ChannelConfig,
        cancel: &CancelToken,
        on_closed: ClosedHandler,
    ) -> Result<Self, ChannelFailure> {
        let stdout = child.stdout.take().ok_or(ChannelFailure::Disconnected)?;
        let stdin = child.stdin.take();
        let now = Instant::now();
        let inner = Arc::new(Inner {
            config,
            stage: Mutex::new(Stage::Handshake),
            child: Mutex::new(Some(child)),
            stdin: Mutex::new(stdin),
            hello: Mutex::new(None),
            nonce: Mutex::new(String::new()),
            next_request: AtomicU64::new(0),
            pending: Mutex::new(HashMap::new()),
            subscriptions: Mutex::new(HashMap::new()),
            last_frame: Mutex::new(now),
            last_ping: Mutex::new(now),
            clock: FrameClock::new(),
            goodbye: (Mutex::new(false), Condvar::new()),
            on_closed: Mutex::new(Some(on_closed)),
            stdout_done: AtomicBool::new(false),
        });
        let (handshake_tx, handshake_rx) = mpsc::sync_channel::<Handshake>(1);
        {
            let inner = Arc::clone(&inner);
            std::thread::Builder::new()
                .name("processlama-remote-reader".into())
                .spawn(move || reader(&inner, stdout, &handshake_tx))
                .map_err(|_| ChannelFailure::Disconnected)?;
        }
        let deadline = Instant::now() + inner.config.hello_deadline;
        let outcome = loop {
            if cancel.is_canceled() {
                break Handshake::Failed(ChannelFailure::Canceled);
            }
            let now = Instant::now();
            if now >= deadline {
                break Handshake::Failed(ChannelFailure::HelloTimeout);
            }
            match handshake_rx.recv_timeout((deadline - now).min(Duration::from_millis(100))) {
                Ok(outcome) => break outcome,
                Err(mpsc::RecvTimeoutError::Timeout) => {}
                Err(mpsc::RecvTimeoutError::Disconnected) => break Handshake::Failed(ChannelFailure::Disconnected),
            }
        };
        let channel = Self { inner };
        match outcome {
            Handshake::Open => {
                channel.spawn_watchdog();
                Ok(channel)
            }
            Handshake::Failed(failure) => {
                {
                    let mut stage = lock(&channel.inner.stage);
                    *stage = Stage::Closed;
                }
                // The handshake failure is the caller's result, not a close.
                lock(&channel.inner.on_closed).take();
                channel.inner.terminate();
                Err(failure)
            }
        }
    }

    pub fn hello(&self) -> Hello {
        lock(&self.inner.hello).clone().expect("an open channel has a hello")
    }

    pub fn is_open(&self) -> bool {
        *lock(&self.inner.stage) == Stage::Open
    }

    /// Blocking call with the interactive or bulk deadline.
    pub fn call(&self, method: &str, arguments: Value, bulk: bool) -> Result<Value, String> {
        let deadline = if bulk { self.inner.config.bulk_deadline } else { self.inner.config.interactive_deadline };
        self.request("call", json!({"method": method, "args": arguments}), deadline, None)
    }

    /// Subscribes; publications arrive on the reader thread. Returns the
    /// subscription ID.
    pub fn subscribe(
        &self,
        topic: &str,
        arguments: Value,
        credit: u64,
        on_publication: Publication,
    ) -> Result<u64, String> {
        let deadline = self.inner.config.interactive_deadline;
        let payload = json!({"topic": topic, "args": arguments, "credit": credit});
        let mut id = 0;
        self.request("subscribe", payload, deadline, Some((&mut id, on_publication)))?;
        Ok(id)
    }

    pub fn grant(&self, subscription: u64, amount: u32) {
        if amount > 0 && lock(&self.inner.subscriptions).contains_key(&subscription) {
            let _ = self.inner.send("credit", json!({"target": subscription, "amount": amount}));
        }
    }

    pub fn unsubscribe(&self, subscription: u64) {
        if lock(&self.inner.subscriptions).remove(&subscription).is_some() {
            let _ = self.inner.send("unsubscribe", json!({"target": subscription}));
        }
    }

    fn request(
        &self,
        kind: &str,
        payload: Value,
        deadline: Duration,
        subscription: Option<(&mut u64, Publication)>,
    ) -> Result<Value, String> {
        if !self.is_open() {
            return Err("disconnected".into());
        }
        let (tx, rx) = mpsc::sync_channel(1);
        let id = {
            let mut pending = lock(&self.inner.pending);
            if pending.len() >= self.hello().concurrent_calls {
                return Err("capacity".into());
            }
            let id = self.inner.next_id();
            pending.insert(id, tx);
            id
        };
        let subscribed = subscription.map(|(slot, callback)| {
            *slot = id;
            lock(&self.inner.subscriptions).insert(id, callback);
            id
        });
        if !self.inner.write_envelope(id, kind, payload) {
            lock(&self.inner.pending).remove(&id);
            if let Some(id) = subscribed {
                lock(&self.inner.subscriptions).remove(&id);
            }
            return Err("disconnected".into());
        }
        let result = match rx.recv_timeout(deadline) {
            Ok(result) => result,
            Err(mpsc::RecvTimeoutError::Timeout) => {
                lock(&self.inner.pending).remove(&id);
                let _ = self.inner.send("cancel", json!({"target": id}));
                Err("timedOut".into())
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => Err("disconnected".into()),
        };
        if result.is_err()
            && let Some(id) = subscribed
        {
            lock(&self.inner.subscriptions).remove(&id);
        }
        result
    }

    /// Graceful shutdown, bounded, followed by process termination.
    pub fn close(&self) {
        {
            let mut stage = lock(&self.inner.stage);
            match *stage {
                Stage::Open => *stage = Stage::Closing,
                Stage::Handshake => {
                    *stage = Stage::Closed;
                    drop(stage);
                    self.inner.terminate();
                    return;
                }
                Stage::Closing | Stage::Closed => {
                    drop(stage);
                    self.inner.terminate();
                    return;
                }
            }
        }
        if let Some(handler) = lock(&self.inner.on_closed).take() {
            handler(None);
        }
        self.inner.fail_pending();
        lock(&self.inner.subscriptions).clear();
        if self.inner.send("shutdown", json!({})) && !self.inner.stdout_done.load(Ordering::Acquire) {
            let (flag, condvar) = &self.inner.goodbye;
            let deadline = Instant::now() + self.inner.config.shutdown_grace;
            let mut said = lock(flag);
            while !*said && !self.inner.stdout_done.load(Ordering::Acquire) {
                let now = Instant::now();
                if now >= deadline {
                    break;
                }
                said = condvar
                    .wait_timeout(said, (deadline - now).min(Duration::from_millis(100)))
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .0;
            }
        }
        *lock(&self.inner.stage) = Stage::Closed;
        self.inner.terminate();
    }

    fn spawn_watchdog(&self) {
        let inner = Arc::clone(&self.inner);
        let _ = std::thread::Builder::new()
            .name("processlama-remote-watchdog".into())
            .spawn(move || {
                loop {
                    std::thread::sleep(Duration::from_millis(250));
                    if *lock(&inner.stage) != Stage::Open {
                        return;
                    }
                    let now = Instant::now();
                    if now.duration_since(*lock(&inner.last_frame)) >= inner.config.liveness_timeout {
                        inner.fail(ChannelFailure::HeartbeatLost);
                        return;
                    }
                    if inner.clock.expired() {
                        inner.fail(ChannelFailure::ProtocolViolation);
                        return;
                    }
                    let due = now.duration_since(*lock(&inner.last_ping)) >= inner.config.ping_interval;
                    if due {
                        *lock(&inner.last_ping) = now;
                        if !inner.send("ping", json!({})) {
                            inner.fail(ChannelFailure::Disconnected);
                            return;
                        }
                    }
                }
            });
    }
}

impl Inner {
    fn next_id(&self) -> u64 {
        self.next_request.fetch_add(1, Ordering::AcqRel) + 1
    }

    fn send(&self, kind: &str, payload: Value) -> bool {
        let id = self.next_id();
        self.write_envelope(id, kind, payload)
    }

    fn write_envelope(&self, request_id: u64, kind: &str, payload: Value) -> bool {
        let incarnation = lock(&self.hello).as_ref().map(|hello| hello.incarnation.clone()).unwrap_or_default();
        let envelope = json!({
            "protocolMajor": self.config.protocol_major,
            "nonce": *lock(&self.nonce),
            "incarnation": incarnation,
            "requestId": request_id,
            "kind": kind,
            "payload": payload,
        });
        self.write_value(&envelope)
    }

    fn write_value(&self, value: &Value) -> bool {
        let Ok(bytes) = serde_json::to_vec(value) else {
            return false;
        };
        let mut stdin = lock(&self.stdin);
        match stdin.as_mut() {
            Some(stdin) => frame::write_frame(stdin, &bytes).is_ok(),
            None => false,
        }
    }

    fn fail_pending(&self) {
        let pending: Vec<_> = lock(&self.pending).drain().collect();
        for (_, sender) in pending {
            let _ = sender.try_send(Err("disconnected".into()));
        }
    }

    /// The channel became unusable: reports once and terminates the child.
    fn fail(self: &Arc<Self>, failure: ChannelFailure) {
        {
            let mut stage = lock(&self.stage);
            match *stage {
                Stage::Open => *stage = Stage::Closed,
                Stage::Closing => {
                    drop(stage);
                    self.said_goodbye();
                    return;
                }
                _ => return,
            }
        }
        if let Some(handler) = lock(&self.on_closed).take() {
            handler(Some(failure));
        }
        self.fail_pending();
        lock(&self.subscriptions).clear();
        let inner = Arc::clone(self);
        let _ = std::thread::Builder::new()
            .name("processlama-remote-terminate".into())
            .spawn(move || inner.terminate());
    }

    fn said_goodbye(&self) {
        let (flag, condvar) = &self.goodbye;
        *lock(flag) = true;
        condvar.notify_all();
    }

    fn terminate(&self) {
        lock(&self.stdin).take();
        let child = lock(&self.child).take();
        if let Some(mut child) = child {
            ssh::terminate(&mut child, self.config.exit_drain_grace);
        }
    }

    fn exit_code(&self, wait: Duration) -> Option<i32> {
        let deadline = Instant::now() + wait;
        loop {
            {
                let mut child = lock(&self.child);
                match child.as_mut().map(Child::try_wait) {
                    Some(Ok(Some(status))) => return status.code(),
                    Some(Ok(None)) => {}
                    _ => return None,
                }
            }
            if Instant::now() >= deadline {
                return None;
            }
            std::thread::sleep(Duration::from_millis(20));
        }
    }
}

const ENVELOPE_KEYS: [&str; 6] = ["protocolMajor", "nonce", "incarnation", "requestId", "kind", "payload"];
const HELLO_KEYS: [&str; 8] = ["kind", "magic", "protocolMajor", "protocolMinor", "buildId", "incarnation", "limits", "body"];

fn is_lower_hex(text: &str, length: usize) -> bool {
    text.len() == length && text.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

/// Reads the launch script's text up to and including `<prefix> 1 start`.
/// Returns the bytes after it, or the failure once the output ended.
fn bootstrap(inner: &Inner, stdout: &mut impl Read) -> Result<Vec<u8>, ChannelFailure> {
    const MAX_TEXT: usize = 64 * 1024;
    let start = format!("{} 1 start", inner.config.bootstrap_prefix);
    let mut text: Vec<u8> = Vec::new();
    let mut scanned = 0;
    let mut buffer = [0_u8; 8192];
    loop {
        let read = match stdout.read(&mut buffer) {
            Ok(0) | Err(_) => {
                inner.stdout_done.store(true, Ordering::Release);
                if inner.exit_code(inner.config.exit_drain_grace) == Some(255) {
                    return Err(ChannelFailure::SshConnectionFailed);
                }
                let marker = StatusMarker::parse(last_non_empty_line(&text).as_deref(), inner.config.bootstrap_prefix);
                return Err(marker.map_or(ChannelFailure::BootstrapFailed, ChannelFailure::BootstrapMarker));
            }
            Ok(read) => read,
        };
        text.extend_from_slice(&buffer[..read]);
        while let Some(offset) = text[scanned..].iter().position(|&byte| byte == b'\n') {
            let end = scanned + offset;
            let line = String::from_utf8_lossy(&text[scanned..end]);
            let line = line.strip_suffix('\r').unwrap_or(&line);
            if line == start {
                return Ok(text[end + 1..].to_vec());
            }
            scanned = end + 1;
        }
        if text.len() > MAX_TEXT {
            return Err(ChannelFailure::BootstrapFailed);
        }
    }
}

fn parse_hello(inner: &Inner, bytes: &[u8]) -> Result<Hello, ChannelFailure> {
    let value: Value = serde_json::from_slice(bytes).map_err(|_| ChannelFailure::BootstrapFailed)?;
    let map = value.as_object().ok_or(ChannelFailure::BootstrapFailed)?;
    if map.len() != HELLO_KEYS.len()
        || !HELLO_KEYS.iter().all(|key| map.contains_key(*key))
        || map.get("kind").and_then(Value::as_str) != Some("hello")
    {
        return Err(ChannelFailure::BootstrapFailed);
    }
    if map.get("magic").and_then(Value::as_str) != Some(inner.config.magic)
        || map.get("protocolMajor").and_then(Value::as_u64) != Some(inner.config.protocol_major)
    {
        return Err(ChannelFailure::ProtocolMismatch);
    }
    let build_id = map.get("buildId").and_then(Value::as_str).ok_or(ChannelFailure::BootstrapFailed)?;
    let incarnation = map
        .get("incarnation")
        .and_then(Value::as_str)
        .filter(|value| is_lower_hex(value, 32))
        .ok_or(ChannelFailure::BootstrapFailed)?;
    map.get("protocolMinor").and_then(Value::as_u64).ok_or(ChannelFailure::BootstrapFailed)?;
    let limits = map.get("limits").and_then(Value::as_object).ok_or(ChannelFailure::BootstrapFailed)?;
    let body = map.get("body").filter(|body| body.is_object()).ok_or(ChannelFailure::BootstrapFailed)?;
    if build_id != inner.config.build_id {
        return Err(ChannelFailure::BuildMismatch);
    }
    let frame_bytes = limits.get("frameBytes").and_then(Value::as_u64);
    let concurrent = limits.get("concurrentCalls").and_then(Value::as_u64);
    let (Some(frame_bytes), Some(concurrent), 2) = (frame_bytes, concurrent, limits.len()) else {
        return Err(ChannelFailure::BootstrapFailed);
    };
    if frame_bytes < 1024 || concurrent < 1 {
        return Err(ChannelFailure::BootstrapFailed);
    }
    Ok(Hello {
        build_id: build_id.to_owned(),
        incarnation: incarnation.to_owned(),
        frame_bytes: (frame_bytes as usize).min(inner.config.max_frame_bytes),
        concurrent_calls: (concurrent as usize).min(inner.config.max_concurrent_calls),
        body: body.clone(),
    })
}

fn reader(inner: &Arc<Inner>, mut stdout: std::process::ChildStdout, handshake: &mpsc::SyncSender<Handshake>) {
    let rest = match bootstrap(inner, &mut stdout) {
        Ok(rest) => rest,
        Err(failure) => {
            let _ = handshake.try_send(Handshake::Failed(failure));
            return;
        }
    };
    let mut input = Cursor::new(rest).chain(stdout);
    let hello = match frame::read_frame(&mut input, inner.config.hello_frame_bytes, &inner.clock) {
        Ok(bytes) => parse_hello(inner, &bytes),
        Err(FrameError::Length) => Err(ChannelFailure::FrameTooLarge),
        Err(_) => Err(ChannelFailure::BootstrapFailed),
    };
    let hello = match hello {
        Ok(hello) => hello,
        Err(failure) => {
            let _ = handshake.try_send(Handshake::Failed(failure));
            return;
        }
    };
    let Ok(nonce) = devmil_remote::server::random_id() else {
        let _ = handshake.try_send(Handshake::Failed(ChannelFailure::BootstrapFailed));
        return;
    };
    let ack = json!({
        "kind": "ack",
        "protocolMajor": inner.config.protocol_major,
        "buildId": hello.build_id,
        "incarnation": hello.incarnation,
        "nonce": nonce,
    });
    let frame_limit = hello.frame_bytes;
    *lock(&inner.nonce) = nonce;
    *lock(&inner.hello) = Some(hello);
    {
        let mut stage = lock(&inner.stage);
        if *stage != Stage::Handshake || !inner.write_value(&ack) {
            drop(stage);
            let _ = handshake.try_send(Handshake::Failed(ChannelFailure::Disconnected));
            return;
        }
        *stage = Stage::Open;
    }
    let now = Instant::now();
    *lock(&inner.last_frame) = now;
    *lock(&inner.last_ping) = now;
    if handshake.try_send(Handshake::Open).is_err() {
        // The caller gave up (timeout or cancel) at the same moment.
        return;
    }
    let mut last_sequence = 0_u64;
    loop {
        let bytes = match frame::read_frame(&mut input, frame_limit, &inner.clock) {
            Ok(bytes) => bytes,
            Err(error) => {
                inner.stdout_done.store(true, Ordering::Release);
                let failure = match error {
                    FrameError::End | FrameError::Truncated => ChannelFailure::Disconnected,
                    FrameError::Length => ChannelFailure::FrameTooLarge,
                    #[allow(unreachable_patterns)]
                    _ => ChannelFailure::ProtocolViolation,
                };
                inner.fail(failure);
                inner.said_goodbye();
                return;
            }
        };
        *lock(&inner.last_frame) = Instant::now();
        if let Err(failure) = dispatch(inner, &bytes, &mut last_sequence) {
            inner.fail(failure);
            return;
        }
    }
}

fn dispatch(inner: &Arc<Inner>, bytes: &[u8], last_sequence: &mut u64) -> Result<(), ChannelFailure> {
    let value: Value = serde_json::from_slice(bytes).map_err(|_| ChannelFailure::ProtocolViolation)?;
    let envelope = value.as_object().ok_or(ChannelFailure::ProtocolViolation)?;
    let incarnation = lock(&inner.hello).as_ref().map(|hello| hello.incarnation.clone()).unwrap_or_default();
    let valid = envelope.len() == ENVELOPE_KEYS.len()
        && ENVELOPE_KEYS.iter().all(|key| envelope.contains_key(*key))
        && envelope.get("protocolMajor").and_then(Value::as_u64) == Some(inner.config.protocol_major)
        && envelope.get("nonce").and_then(Value::as_str) == Some(lock(&inner.nonce).as_str())
        && envelope.get("incarnation").and_then(Value::as_str) == Some(incarnation.as_str());
    let request_id = envelope.get("requestId").and_then(Value::as_u64);
    let kind = envelope.get("kind").and_then(Value::as_str);
    let payload = envelope.get("payload").and_then(Value::as_object);
    let (true, Some(request_id), Some(kind), Some(payload)) = (valid, request_id, kind, payload) else {
        return Err(ChannelFailure::ProtocolViolation);
    };
    if request_id > inner.next_request.load(Ordering::Acquire) {
        return Err(ChannelFailure::ProtocolViolation);
    }
    match kind {
        "result" => result(inner, request_id, payload),
        "publication" => {
            let subscription = payload.get("subscription").and_then(Value::as_u64);
            let sequence = payload.get("sequence").and_then(Value::as_u64);
            let (0, 3, Some(subscription), Some(sequence), true) = (
                request_id,
                payload.len(),
                subscription,
                sequence,
                payload.contains_key("data"),
            ) else {
                return Err(ChannelFailure::ProtocolViolation);
            };
            if sequence <= *last_sequence {
                return Err(ChannelFailure::ProtocolViolation);
            }
            *last_sequence = sequence;
            // A publication for an ended subscription may still be in flight.
            let callback = lock(&inner.subscriptions).get(&subscription).cloned();
            if let Some(callback) = callback {
                callback(payload["data"].clone());
            }
            Ok(())
        }
        "pong" => {
            if request_id == 0 || !payload.is_empty() {
                return Err(ChannelFailure::ProtocolViolation);
            }
            Ok(())
        }
        "goodbye" => {
            inner.said_goodbye();
            Ok(())
        }
        "fatal" => Err(ChannelFailure::Fatal),
        _ => Err(ChannelFailure::ProtocolViolation),
    }
}

fn result(inner: &Inner, request_id: u64, payload: &Map<String, Value>) -> Result<(), ChannelFailure> {
    if request_id == 0 || payload.len() != 1 {
        return Err(ChannelFailure::ProtocolViolation);
    }
    // A retired, timed out or unknown request: the late result is ignored.
    let Some(sender) = lock(&inner.pending).remove(&request_id) else {
        return Ok(());
    };
    if let Some(ok) = payload.get("ok") {
        let _ = sender.try_send(Ok(ok.clone()));
        return Ok(());
    }
    let code = payload
        .get("error")
        .and_then(Value::as_object)
        .filter(|error| error.len() == 1)
        .and_then(|error| error.get("code"))
        .and_then(Value::as_str)
        .filter(|code| !code.is_empty() && code.len() <= 64);
    match code {
        Some(code) => {
            let _ = sender.try_send(Err(code.to_owned()));
            Ok(())
        }
        None => {
            let _ = sender.try_send(Err("invalidRequest".into()));
            Err(ChannelFailure::ProtocolViolation)
        }
    }
}
