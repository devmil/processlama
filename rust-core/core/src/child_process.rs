//! Child processes the application owns outside the telemetry engine, such as the SSH
//! transport of a remote host. The Dart VM reaps every child while a `dart:io` process runs;
//! starting these children in Rust keeps their exit status (see `devmil_remote::child`).
use crate::frb_generated::StreamSink;
use devmil_remote::child::{self, ChildEvent, ChildEventKind, ChildEventSink};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NativeChildEventKind {
    /// The child runs; `child_id` names it for writes and signals.
    Started,
    /// The executable could not be started.
    StartFailed,
    /// Bytes from standard output.
    Stdout,
    /// Standard output reached its end.
    StdoutClosed,
    /// The child exited; `exit_code` follows `dart:io` (a negative signal number when killed).
    Exited,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeChildEvent {
    pub kind: NativeChildEventKind,
    pub child_id: u64,
    pub bytes: Vec<u8>,
    pub exit_code: Option<i32>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeEnvironmentVariable {
    pub name: String,
    pub value: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NativeCapturedProcess {
    pub started: bool,
    pub timed_out: bool,
    pub exit_code: Option<i32>,
    pub stderr: Vec<u8>,
}

#[derive(Clone)]
struct BridgeSink(StreamSink<NativeChildEvent>);

impl ChildEventSink for BridgeSink {
    fn add(&self, event: ChildEvent) -> bool {
        self.0
            .add(NativeChildEvent {
                kind: match event.kind {
                    ChildEventKind::Started => NativeChildEventKind::Started,
                    ChildEventKind::StartFailed => NativeChildEventKind::StartFailed,
                    ChildEventKind::Stdout => NativeChildEventKind::Stdout,
                    ChildEventKind::StdoutClosed => NativeChildEventKind::StdoutClosed,
                    ChildEventKind::Exited => NativeChildEventKind::Exited,
                },
                child_id: event.child_id,
                bytes: event.bytes,
                exit_code: event.exit_code,
            })
            .is_ok()
    }
}

pub fn start(
    executable: String,
    arguments: Vec<String>,
    environment: Vec<NativeEnvironmentVariable>,
    sink: StreamSink<NativeChildEvent>,
) {
    child::start(
        executable,
        arguments,
        environment
            .into_iter()
            .map(|variable| child::EnvironmentVariable {
                name: variable.name,
                value: variable.value,
            })
            .collect(),
        BridgeSink(sink),
    );
}

pub fn write(child_id: u64, bytes: Vec<u8>) -> bool {
    child::write(child_id, bytes)
}

pub fn close_stdin(child_id: u64) {
    child::close_stdin(child_id);
}

pub fn signal(child_id: u64, kill: bool) -> bool {
    child::signal(child_id, kill)
}

pub fn run_capture(
    executable: String,
    arguments: Vec<String>,
    timeout_ms: u32,
    maximum_bytes: u32,
) -> NativeCapturedProcess {
    let captured = child::run_capture(executable, arguments, timeout_ms, maximum_bytes);
    NativeCapturedProcess {
        started: captured.started,
        timed_out: captured.timed_out,
        exit_code: captured.exit_code,
        stderr: captured.stderr,
    }
}
