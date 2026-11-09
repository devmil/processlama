//! Drives a real helper process over pipes.
#![allow(dead_code)]
use devmil_remote::frame::{self, FrameClock};
use serde_json::{Value, json};
use std::io::Write;
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};

pub const NONCE: &str = "00112233445566778899aabbccddeeff";

pub struct Helper {
    pub child: Child,
    pub stdin: Option<ChildStdin>,
    pub stdout: ChildStdout,
    pub clock: FrameClock,
    pub incarnation: String,
    pub hello: Value,
    next_id: u64,
}

impl Helper {
    pub fn command() -> Command {
        Command::new(env!("CARGO_BIN_EXE_processlama-remote-helper"))
    }

    pub fn start() -> Self {
        Self::start_with(Self::command())
    }

    pub fn start_with(mut command: Command) -> Self {
        let mut child = command
            .arg("--stdio")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .expect("helper starts");
        let stdin = child.stdin.take();
        let stdout = child.stdout.take().unwrap();
        let mut helper = Self {
            child,
            stdin,
            stdout,
            clock: FrameClock::new(),
            incarnation: String::new(),
            hello: Value::Null,
            next_id: 0,
        };
        let hello = helper.read();
        assert_eq!(hello["kind"], "hello");
        helper.incarnation = hello["incarnation"].as_str().unwrap().to_owned();
        helper.hello = hello;
        helper
    }

    pub fn acknowledge(&mut self) {
        self.acknowledge_build(processlama_wire::BUILD_ID);
    }

    pub fn acknowledge_build(&mut self, build_id: &str) {
        let ack = json!({
            "kind": "ack",
            "protocolMajor": 1,
            "buildId": build_id,
            "incarnation": self.incarnation,
            "nonce": NONCE,
        });
        self.write(&ack);
    }

    pub fn write(&mut self, value: &Value) {
        let stdin = self.stdin.as_mut().unwrap();
        frame::write_frame(stdin, &serde_json::to_vec(value).unwrap()).unwrap();
        stdin.flush().unwrap();
    }

    pub fn send(&mut self, kind: &str, payload: Value) -> u64 {
        self.next_id += 1;
        let envelope = json!({
            "protocolMajor": 1,
            "nonce": NONCE,
            "incarnation": self.incarnation,
            "requestId": self.next_id,
            "kind": kind,
            "payload": payload,
        });
        self.write(&envelope);
        self.next_id
    }

    pub fn call(&mut self, method: &str, args: Value) -> Value {
        let id = self.send("call", json!({"method": method, "args": args}));
        loop {
            let frame = self.read();
            if frame["kind"] == "result" && frame["requestId"] == id {
                return frame["payload"].clone();
            }
        }
    }

    pub fn read(&mut self) -> Value {
        let bytes = frame::read_frame(&mut self.stdout, frame::MAX_FRAME_BYTES, &self.clock)
            .expect("frame from helper");
        serde_json::from_slice(&bytes).unwrap()
    }

    pub fn try_read(&mut self) -> Option<Value> {
        frame::read_frame(&mut self.stdout, frame::MAX_FRAME_BYTES, &self.clock)
            .ok()
            .map(|bytes| serde_json::from_slice(&bytes).unwrap())
    }

    pub fn wait(mut self) -> std::process::ExitStatus {
        drop(self.stdin.take());
        self.child.wait().unwrap()
    }
}
