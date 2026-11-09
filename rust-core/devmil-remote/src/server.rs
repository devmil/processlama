//! The helper side of one connection: handshake, envelope validation, interactive and bulk
//! worker queues, a prioritized single writer and credit-limited subscriptions.
//!
//! Structure adapted from GitLama's remote helper (`gitlama/rust-core/remote-helper/src/server.rs`).
//! Control replies never wait behind data. Interactive calls never wait behind bulk calls.
//! A subscription without credit keeps only its newest unsent publication.
use crate::frame::{self, FrameClock, FrameError};
use serde_json::{Map, Value, json};
use std::collections::{HashMap, HashSet, VecDeque};
use std::io::{Read, Write};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::time::Duration;

/// Fixed parameters of one product's helper.
#[derive(Clone, Debug)]
pub struct ServerConfig {
    pub magic: &'static str,
    pub build_id: String,
    pub protocol_major: u64,
    pub protocol_minor: u64,
    /// Largest frame either peer sends after the hello.
    pub frame_bytes: usize,
    /// Calls in flight at once; more are answered `capacity`.
    pub concurrent_calls: usize,
    pub interactive_workers: usize,
    pub bulk_workers: usize,
    /// Accepted results wait for the writer while this many bytes are queued.
    pub result_buffer_bytes: usize,
}

impl ServerConfig {
    pub fn new(magic: &'static str, build_id: impl Into<String>) -> Self {
        Self {
            magic,
            build_id: build_id.into(),
            protocol_major: 1,
            protocol_minor: 0,
            frame_bytes: frame::MAX_FRAME_BYTES,
            concurrent_calls: 8,
            interactive_workers: 2,
            bulk_workers: 1,
            result_buffer_bytes: 8 * 1024 * 1024,
        }
    }
}

/// A call or subscription failed with a typed code; carries no free text.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CallError(pub &'static str);

/// What a product's helper does with requests.
pub trait Handler: Send + Sync + 'static {
    /// The product part of the hello.
    fn hello_body(&self) -> Value;

    /// Whether `method` runs on the bulk queue.
    fn is_bulk(&self, method: &str) -> bool;

    /// Answers one call. Runs on a worker thread.
    fn call(&self, method: &str, arguments: &Map<String, Value>) -> Result<Value, CallError>;

    /// Starts a subscription. The handler keeps `publisher` and publishes until it reports
    /// [`Publisher::is_closed`]. Runs on the reader thread; it must not block.
    fn subscribe(
        &self,
        topic: &str,
        arguments: &Map<String, Value>,
        publisher: Publisher,
    ) -> Result<Value, CallError>;

    /// The connection ended; stop background work.
    fn shutdown(&self) {}
}

/// Why [`serve`] returned.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ServeEnd {
    /// The client sent `shutdown`.
    Shutdown,
    /// Standard input ended.
    InputClosed,
    /// The client broke the protocol; a `fatal` frame was sent.
    ProtocolViolation,
    /// No acknowledgement, or one for another build.
    HandshakeRejected,
    /// Writing to the client failed.
    OutputFailed,
}

pub fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
    mutex
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

/// 16 random bytes as 32 lowercase hex digits.
///
/// # Errors
/// The operating system's random source failed.
pub fn random_id() -> Result<String, getrandom::Error> {
    let mut bytes = [0_u8; 16];
    getrandom::fill(&mut bytes)?;
    Ok(bytes.iter().map(|byte| format!("{byte:02x}")).collect())
}

#[derive(Clone)]
struct Identity {
    major: u64,
    nonce: String,
    incarnation: String,
}

impl Identity {
    fn envelope(&self, request_id: u64, kind: &str, payload: Value) -> Value {
        json!({
            "protocolMajor": self.major,
            "nonce": self.nonce,
            "incarnation": self.incarnation,
            "requestId": request_id,
            "kind": kind,
            "payload": payload,
        })
    }
}

#[derive(Default)]
struct Slot {
    credit: u64,
    pending: Option<Value>,
}

#[derive(Default)]
struct OutState {
    control: VecDeque<Vec<u8>>,
    results: VecDeque<Vec<u8>>,
    result_bytes: usize,
    publications: VecDeque<Vec<u8>>,
    slots: HashMap<u64, Slot>,
    sequence: u64,
    closed: bool,
}

/// The single writer's queues.
struct Outbound {
    state: Mutex<OutState>,
    ready: Condvar,
    space: Condvar,
    /// Signalled when a subscription receives credit or closes.
    credit: Condvar,
    identity: Identity,
    buffer_bytes: usize,
    frame_bytes: usize,
}

impl Outbound {
    fn encode(&self, request_id: u64, kind: &str, payload: Value) -> Vec<u8> {
        serde_json::to_vec(&self.identity.envelope(request_id, kind, payload)).unwrap_or_default()
    }

    fn control(&self, request_id: u64, kind: &str, payload: Value) {
        let bytes = self.encode(request_id, kind, payload);
        let mut state = lock(&self.state);
        if state.closed {
            return;
        }
        state.control.push_back(bytes);
        self.ready.notify_all();
    }

    fn result(&self, request_id: u64, payload: Value, stopping: &AtomicBool) {
        let mut bytes = self.encode(request_id, "result", payload);
        if bytes.len() > self.frame_bytes {
            bytes = self.encode(request_id, "result", error_payload("frameTooLarge"));
        }
        let mut state = lock(&self.state);
        while state.result_bytes > self.buffer_bytes
            && !state.closed
            && !stopping.load(Ordering::Acquire)
        {
            state = self
                .space
                .wait_timeout(state, Duration::from_millis(100))
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .0;
        }
        if state.closed {
            return;
        }
        state.result_bytes += bytes.len();
        state.results.push_back(bytes);
        self.ready.notify_all();
    }

    fn publication_bytes(&self, state: &mut OutState, subscription: u64, data: Value) -> Vec<u8> {
        state.sequence += 1;
        let bytes = self.encode(
            0,
            "publication",
            json!({"subscription": subscription, "sequence": state.sequence, "data": data}),
        );
        if bytes.len() > self.frame_bytes {
            // An oversized sample is dropped; the subscription stays alive.
            return Vec::new();
        }
        bytes
    }

    fn publish(&self, subscription: u64, data: Value) -> bool {
        let mut state = lock(&self.state);
        if state.closed {
            return false;
        }
        let Some(slot) = state.slots.get_mut(&subscription) else {
            return false;
        };
        if slot.credit == 0 {
            // Newest wins: an unsent sample is replaced, never queued behind.
            slot.pending = Some(data);
            return true;
        }
        slot.credit -= 1;
        let bytes = self.publication_bytes(&mut state, subscription, data);
        if !bytes.is_empty() {
            state.publications.push_back(bytes);
            self.ready.notify_all();
        }
        true
    }

    fn grant(&self, subscription: u64, amount: u64) {
        let mut state = lock(&self.state);
        let Some(slot) = state.slots.get_mut(&subscription) else {
            return;
        };
        slot.credit = slot.credit.saturating_add(amount);
        self.credit.notify_all();
        let pending = if slot.credit > 0 {
            slot.pending.take()
        } else {
            None
        };
        if let Some(data) = pending {
            if let Some(slot) = state.slots.get_mut(&subscription) {
                slot.credit -= 1;
            }
            let bytes = self.publication_bytes(&mut state, subscription, data);
            if !bytes.is_empty() {
                state.publications.push_back(bytes);
                self.ready.notify_all();
            }
        }
    }

    fn open_slot(&self, subscription: u64, credit: u64) {
        lock(&self.state).slots.insert(
            subscription,
            Slot {
                credit,
                pending: None,
            },
        );
    }

    fn close_slot(&self, subscription: u64) {
        lock(&self.state).slots.remove(&subscription);
        self.credit.notify_all();
    }

    fn has_credit(&self, subscription: u64) -> bool {
        lock(&self.state)
            .slots
            .get(&subscription)
            .is_some_and(|slot| slot.credit > 0)
    }

    /// Waits up to `timeout` for credit; true when there is credit now.
    fn wait_for_credit(&self, subscription: u64, timeout: Duration) -> bool {
        let deadline = std::time::Instant::now() + timeout;
        let mut state = lock(&self.state);
        loop {
            match state.slots.get(&subscription) {
                None => return false,
                Some(slot) if slot.credit > 0 => return true,
                Some(_) => {}
            }
            let now = std::time::Instant::now();
            if now >= deadline || state.closed {
                return false;
            }
            state = self
                .credit
                .wait_timeout(state, deadline - now)
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .0;
        }
    }

    fn has_slot(&self, subscription: u64) -> bool {
        lock(&self.state).slots.contains_key(&subscription)
    }

    fn close(&self) {
        let mut state = lock(&self.state);
        state.closed = true;
        state.slots.clear();
        self.ready.notify_all();
        self.space.notify_all();
        self.credit.notify_all();
    }

    /// The writer loop. Returns when output fails or the queues are closed and drained of
    /// control frames.
    fn write_all(&self, output: &mut impl Write, failed: &AtomicBool) {
        loop {
            let frame = {
                let mut state = lock(&self.state);
                loop {
                    if let Some(frame) = state.control.pop_front() {
                        break Some(frame);
                    }
                    if !state.closed {
                        if let Some(frame) = state.results.pop_front() {
                            state.result_bytes -= frame.len();
                            self.space.notify_all();
                            break Some(frame);
                        }
                        if let Some(frame) = state.publications.pop_front() {
                            break Some(frame);
                        }
                    }
                    if state.closed {
                        break None;
                    }
                    state = self
                        .ready
                        .wait(state)
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                }
            };
            let Some(frame) = frame else {
                let _ = output.flush();
                return;
            };
            if frame::write_frame(output, &frame).is_err() {
                failed.store(true, Ordering::Release);
                self.close();
                return;
            }
        }
    }
}

/// Publishes to one subscription.
#[derive(Clone)]
pub struct Publisher {
    id: u64,
    outbound: Arc<Outbound>,
}

impl Publisher {
    /// The subscription's request ID.
    pub fn id(&self) -> u64 {
        self.id
    }

    /// Publishes `data`. Without credit it replaces the unsent sample. Returns false once the
    /// subscription or connection ended.
    pub fn publish(&self, data: Value) -> bool {
        self.outbound.publish(self.id, data)
    }

    pub fn is_closed(&self) -> bool {
        !self.outbound.has_slot(self.id)
    }

    /// Whether a publication now would be sent rather than held back.
    pub fn has_credit(&self) -> bool {
        self.outbound.has_credit(self.id)
    }

    /// Waits up to `timeout` for credit. Returns true when there is credit, false on timeout
    /// or when the subscription ended.
    pub fn wait_for_credit(&self, timeout: Duration) -> bool {
        self.outbound.wait_for_credit(self.id, timeout)
    }
}

fn error_payload(code: &str) -> Value {
    json!({"error": {"code": code}})
}

struct Job {
    request_id: u64,
    method: String,
    arguments: Map<String, Value>,
}

#[derive(Default)]
struct Queues {
    interactive: VecDeque<Job>,
    bulk: VecDeque<Job>,
    stopped: bool,
}

struct Shared<H: Handler> {
    handler: Arc<H>,
    outbound: Arc<Outbound>,
    queues: Mutex<Queues>,
    work: Condvar,
    in_flight: Mutex<HashSet<u64>>,
    stopping: AtomicBool,
    write_failed: AtomicBool,
    concurrent_calls: usize,
}

impl<H: Handler> Shared<H> {
    fn worker(&self, bulk: bool) {
        loop {
            let job = {
                let mut queues = lock(&self.queues);
                loop {
                    if queues.stopped {
                        return;
                    }
                    let next = if bulk {
                        queues.bulk.pop_front()
                    } else {
                        queues.interactive.pop_front()
                    };
                    if let Some(job) = next {
                        break job;
                    }
                    queues = self
                        .work
                        .wait(queues)
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                }
            };
            let payload = match self.handler.call(&job.method, &job.arguments) {
                Ok(value) => json!({"ok": value}),
                Err(CallError(code)) => error_payload(code),
            };
            if lock(&self.in_flight).remove(&job.request_id) {
                self.outbound
                    .result(job.request_id, payload, &self.stopping);
            }
        }
    }

    fn admit(&self, job: Job) {
        let request_id = job.request_id;
        {
            let mut in_flight = lock(&self.in_flight);
            if in_flight.len() >= self.concurrent_calls {
                drop(in_flight);
                self.outbound
                    .result(request_id, error_payload("capacity"), &self.stopping);
                return;
            }
            in_flight.insert(request_id);
        }
        let bulk = self.handler.is_bulk(&job.method);
        let mut queues = lock(&self.queues);
        if bulk {
            queues.bulk.push_back(job);
        } else {
            queues.interactive.push_back(job);
        }
        self.work.notify_all();
    }

    /// Drops a queued call and answers it `canceled`. A running call cannot be preempted;
    /// its late result is still sent.
    fn cancel(&self, target: u64) {
        let removed = {
            let mut queues = lock(&self.queues);
            let before = queues.interactive.len() + queues.bulk.len();
            queues.interactive.retain(|job| job.request_id != target);
            queues.bulk.retain(|job| job.request_id != target);
            before != queues.interactive.len() + queues.bulk.len()
        };
        if removed && lock(&self.in_flight).remove(&target) {
            self.outbound
                .result(target, error_payload("canceled"), &self.stopping);
        }
    }

    fn stop(&self) {
        self.stopping.store(true, Ordering::Release);
        let mut queues = lock(&self.queues);
        queues.stopped = true;
        queues.interactive.clear();
        queues.bulk.clear();
        self.work.notify_all();
    }
}

/// Reads the next frame as a JSON object.
fn read_object(
    input: &mut impl Read,
    limit: usize,
    clock: &FrameClock,
) -> Result<Map<String, Value>, Option<FrameError>> {
    let bytes = frame::read_frame(input, limit, clock).map_err(Some)?;
    match serde_json::from_slice::<Value>(&bytes) {
        Ok(Value::Object(map)) => Ok(map),
        _ => Err(None),
    }
}

fn is_lower_hex(text: &str, length: usize) -> bool {
    text.len() == length
        && text
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

/// Runs the hello handshake and serves one connection until shutdown, end of input or a
/// protocol violation. `acknowledged` is set once a valid acknowledgement arrived; see
/// [`spawn_watchdog`].
pub fn serve<H: Handler>(
    config: &ServerConfig,
    handler: Arc<H>,
    mut input: impl Read,
    mut output: impl Write + Send + 'static,
    clock: &FrameClock,
    acknowledged: &AtomicBool,
) -> ServeEnd {
    let Ok(incarnation) = random_id() else {
        return ServeEnd::OutputFailed;
    };
    let hello = json!({
        "kind": "hello",
        "magic": config.magic,
        "protocolMajor": config.protocol_major,
        "protocolMinor": config.protocol_minor,
        "buildId": config.build_id,
        "incarnation": incarnation,
        "limits": {"frameBytes": config.frame_bytes, "concurrentCalls": config.concurrent_calls},
        "body": handler.hello_body(),
    });
    let hello_bytes = serde_json::to_vec(&hello).unwrap_or_default();
    if hello_bytes.len() > frame::MAX_HELLO_BYTES
        || frame::write_frame(&mut output, &hello_bytes).is_err()
    {
        return ServeEnd::OutputFailed;
    }

    let Ok(ack) = read_object(&mut input, frame::MAX_HELLO_BYTES, clock) else {
        return ServeEnd::HandshakeRejected;
    };
    let nonce = ack.get("nonce").and_then(Value::as_str).unwrap_or_default();
    let accepted = ack.len() == 5
        && ack.get("kind").and_then(Value::as_str) == Some("ack")
        && ack.get("protocolMajor").and_then(Value::as_u64) == Some(config.protocol_major)
        && ack.get("buildId").and_then(Value::as_str) == Some(config.build_id.as_str())
        && ack.get("incarnation").and_then(Value::as_str) == Some(incarnation.as_str())
        && is_lower_hex(nonce, 32);
    let identity = Identity {
        major: config.protocol_major,
        nonce: nonce.to_owned(),
        incarnation: incarnation.clone(),
    };
    if !accepted {
        let fatal = identity.envelope(0, "fatal", json!({"code": "handshakeRejected"}));
        let _ = frame::write_frame(&mut output, &serde_json::to_vec(&fatal).unwrap_or_default());
        return ServeEnd::HandshakeRejected;
    }
    acknowledged.store(true, Ordering::Release);

    let outbound = Arc::new(Outbound {
        state: Mutex::new(OutState::default()),
        ready: Condvar::new(),
        space: Condvar::new(),
        credit: Condvar::new(),
        identity,
        buffer_bytes: config.result_buffer_bytes,
        frame_bytes: config.frame_bytes,
    });
    let shared = Arc::new(Shared {
        handler: Arc::clone(&handler),
        outbound: Arc::clone(&outbound),
        queues: Mutex::new(Queues::default()),
        work: Condvar::new(),
        in_flight: Mutex::new(HashSet::new()),
        stopping: AtomicBool::new(false),
        write_failed: AtomicBool::new(false),
        concurrent_calls: config.concurrent_calls,
    });

    let writer = {
        let shared = Arc::clone(&shared);
        std::thread::spawn(move || shared.outbound.write_all(&mut output, &shared.write_failed))
    };
    let mut workers = Vec::new();
    for bulk in std::iter::repeat_n(false, config.interactive_workers.max(1))
        .chain(std::iter::repeat_n(true, config.bulk_workers.max(1)))
    {
        let shared = Arc::clone(&shared);
        workers.push(std::thread::spawn(move || shared.worker(bulk)));
    }

    let end = read_loop(config, &shared, &mut input, clock);

    shared.stop();
    handler.shutdown();
    if end == ServeEnd::ProtocolViolation {
        outbound.control(0, "fatal", json!({"code": "protocolViolation"}));
    }
    // Closing still writes queued control frames (goodbye, fatal) before the writer stops.
    outbound.close();
    let _ = writer.join();
    for worker in workers {
        let _ = worker.join();
    }
    if shared.write_failed.load(Ordering::Acquire) && end != ServeEnd::Shutdown {
        return ServeEnd::OutputFailed;
    }
    end
}

const CLIENT_KEYS: [&str; 6] = [
    "protocolMajor",
    "nonce",
    "incarnation",
    "requestId",
    "kind",
    "payload",
];

fn read_loop<H: Handler>(
    config: &ServerConfig,
    shared: &Arc<Shared<H>>,
    input: &mut impl Read,
    clock: &FrameClock,
) -> ServeEnd {
    let outbound = &shared.outbound;
    let identity = &outbound.identity;
    let last_request = AtomicU64::new(0);
    loop {
        if shared.write_failed.load(Ordering::Acquire) {
            return ServeEnd::OutputFailed;
        }
        let envelope = match read_object(input, config.frame_bytes, clock) {
            Ok(envelope) => envelope,
            Err(Some(FrameError::End)) => return ServeEnd::InputClosed,
            Err(_) => return ServeEnd::ProtocolViolation,
        };
        let valid_identity = envelope.len() == CLIENT_KEYS.len()
            && CLIENT_KEYS.iter().all(|key| envelope.contains_key(*key))
            && envelope.get("protocolMajor").and_then(Value::as_u64) == Some(identity.major)
            && envelope.get("nonce").and_then(Value::as_str) == Some(identity.nonce.as_str())
            && envelope.get("incarnation").and_then(Value::as_str)
                == Some(identity.incarnation.as_str());
        let request_id = envelope.get("requestId").and_then(Value::as_u64);
        let kind = envelope.get("kind").and_then(Value::as_str);
        let payload = envelope.get("payload").and_then(Value::as_object);
        let (Some(request_id), Some(kind), Some(payload), true) =
            (request_id, kind, payload, valid_identity)
        else {
            return ServeEnd::ProtocolViolation;
        };
        if request_id <= last_request.load(Ordering::Relaxed) {
            return ServeEnd::ProtocolViolation;
        }
        last_request.store(request_id, Ordering::Relaxed);
        let target = || payload.get("target").and_then(Value::as_u64);
        match kind {
            "call" => {
                let method = payload.get("method").and_then(Value::as_str);
                let arguments = payload.get("args").and_then(Value::as_object);
                let (Some(method), Some(arguments)) = (method, arguments) else {
                    return ServeEnd::ProtocolViolation;
                };
                shared.admit(Job {
                    request_id,
                    method: method.to_owned(),
                    arguments: arguments.clone(),
                });
            }
            "subscribe" => {
                let topic = payload.get("topic").and_then(Value::as_str);
                let arguments = payload.get("args").and_then(Value::as_object);
                let credit = payload.get("credit").and_then(Value::as_u64);
                let (Some(topic), Some(arguments), Some(credit)) = (topic, arguments, credit)
                else {
                    return ServeEnd::ProtocolViolation;
                };
                outbound.open_slot(request_id, credit);
                let publisher = Publisher {
                    id: request_id,
                    outbound: Arc::clone(outbound),
                };
                let answer = match shared.handler.subscribe(topic, arguments, publisher) {
                    Ok(value) => json!({"ok": value}),
                    Err(CallError(code)) => {
                        outbound.close_slot(request_id);
                        error_payload(code)
                    }
                };
                outbound.result(request_id, answer, &shared.stopping);
            }
            "unsubscribe" => {
                let Some(target) = target() else {
                    return ServeEnd::ProtocolViolation;
                };
                outbound.close_slot(target);
            }
            "credit" => {
                let amount = payload.get("amount").and_then(Value::as_u64);
                let (Some(target), Some(amount)) = (target(), amount) else {
                    return ServeEnd::ProtocolViolation;
                };
                outbound.grant(target, amount);
            }
            "cancel" => {
                let Some(target) = target() else {
                    return ServeEnd::ProtocolViolation;
                };
                shared.cancel(target);
            }
            "ping" => outbound.control(request_id, "pong", json!({})),
            "shutdown" => {
                outbound.control(request_id, "goodbye", json!({}));
                return ServeEnd::Shutdown;
            }
            _ => return ServeEnd::ProtocolViolation,
        }
    }
}

/// Calls `on_expire` once when no acknowledgement arrived within `hello_deadline` or a frame
/// stayed incomplete past its deadline. Helpers pass a function that ends the process; a
/// blocked read cannot be interrupted otherwise.
pub fn spawn_watchdog(
    clock: FrameClock,
    acknowledged: Arc<AtomicBool>,
    hello_deadline: Duration,
    on_expire: fn(),
) {
    std::thread::spawn(move || {
        let started = std::time::Instant::now();
        loop {
            std::thread::sleep(Duration::from_millis(200));
            let unacknowledged =
                !acknowledged.load(Ordering::Acquire) && started.elapsed() > hello_deadline;
            if unacknowledged || clock.expired() {
                on_expire();
                return;
            }
        }
    });
}
