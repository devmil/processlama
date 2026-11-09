//! `processlama-remote-helper`: ProcessLama's headless telemetry helper. The desktop client
//! starts it over SSH for one connection; it speaks the devmil_remote protocol on its
//! standard input and output. See docs/10_remote_hosts.md.
mod detail;
mod handler;
mod host;
mod icons;
mod telemetry;

use std::process::ExitCode;
use std::sync::Arc;
use std::sync::atomic::AtomicBool;

const USAGE: &str =
    "usage: processlama-remote-helper --stdio | --version | --self-check | --remove-state\n";

fn main() -> ExitCode {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    let Some(target) = host::TARGET else {
        eprintln!("processlama-remote-helper: unsupported platform");
        return ExitCode::from(3);
    };
    match arguments
        .iter()
        .map(String::as_str)
        .collect::<Vec<_>>()
        .as_slice()
    {
        ["--version"] => {
            println!("{}", version(target));
            ExitCode::SUCCESS
        }
        ["--self-check"] => self_check(target),
        ["--remove-state"] => remove_state(),
        ["--stdio"] => serve(target),
        _ => {
            eprint!("{USAGE}");
            ExitCode::from(2)
        }
    }
}

fn version(target: processlama_wire::contract::Target) -> serde_json::Value {
    serde_json::json!({
        "buildId": processlama_wire::BUILD_ID,
        "compatibility": processlama_wire::COMPATIBILITY.parse::<u64>().unwrap_or(0),
        "protocolMajor": processlama_wire::contract::PROTOCOL_MAJOR,
        "protocolMinor": processlama_wire::contract::PROTOCOL_MINOR,
        "target": target.as_str(),
        "processtreeRevision": processlama_wire::PROCESSTREE_REVISION,
    })
}

/// Samples telemetry twice and reports what this host supports. Exit 0 when a sample with
/// at least one process arrived.
fn self_check(target: processlama_wire::contract::Target) -> ExitCode {
    let mut engine = processlama_telemetry::TelemetryEngine::new(1_000, None);
    let first = engine.sample(1_000, None);
    std::thread::sleep(std::time::Duration::from_millis(300));
    let second = engine.sample(1_000, None);
    let processes = second
        .as_ref()
        .or(first.as_ref())
        .map(|sample| sample.snapshot.processes.len())
        .unwrap_or(0);
    let body = host::hello_body(target, false);
    let report = serde_json::json!({
        "ok": processes > 0,
        "buildId": processlama_wire::BUILD_ID,
        "target": target.as_str(),
        "processes": processes,
        "network": body.capabilities.network.source.as_str(),
        "hidepid": body.capabilities.hidepid,
    });
    println!("{report}");
    if processes > 0 {
        ExitCode::SUCCESS
    } else {
        ExitCode::from(1)
    }
}

/// Deletes the helper's caches. The install directory is removed by the client's uninstall
/// script after this returns, because a running binary cannot reliably delete itself.
fn remove_state() -> ExitCode {
    let removed = host::remove_state();
    println!("{}", serde_json::json!({"removed": removed}));
    if removed {
        ExitCode::SUCCESS
    } else {
        ExitCode::from(1)
    }
}

/// Marks the helper's build directory as in use while it serves, so a client pruning old
/// builds never deletes a running helper. Removed when dropped.
struct RunningMarker(Option<std::path::PathBuf>);

impl RunningMarker {
    fn create() -> Self {
        let marker = std::env::current_exe().ok().and_then(|executable| {
            let directory = executable.parent()?;
            let build = directory.file_name()?.to_str()?;
            let installed = processlama_wire::is_build_id(build)
                && directory
                    .parent()
                    .is_some_and(|parent| parent.ends_with("processlama/remote"));
            installed.then(|| directory.join(format!(".running.{}", std::process::id())))
        });
        if let Some(path) = &marker {
            let _ = std::fs::write(path, b"");
        }
        Self(marker)
    }
}

impl Drop for RunningMarker {
    fn drop(&mut self) {
        if let Some(path) = &self.0 {
            let _ = std::fs::remove_file(path);
        }
    }
}

#[cfg(unix)]
fn serve(target: processlama_wire::contract::Target) -> ExitCode {
    use devmil_remote::{frame::FrameClock, server};
    let Ok((input, output)) = devmil_remote::streams::protocol_streams() else {
        return ExitCode::from(4);
    };
    let _running = RunningMarker::create();
    let clock = FrameClock::new();
    let acknowledged = Arc::new(AtomicBool::new(false));
    server::spawn_watchdog(
        clock.clone(),
        Arc::clone(&acknowledged),
        std::time::Duration::from_millis(processlama_wire::contract::HELLO_DEADLINE_MS),
        || std::process::exit(2),
    );
    let mut config = server::ServerConfig::new(
        processlama_wire::contract::MAGIC,
        processlama_wire::BUILD_ID,
    );
    config.protocol_major = processlama_wire::contract::PROTOCOL_MAJOR;
    config.protocol_minor = processlama_wire::contract::PROTOCOL_MINOR;
    config.frame_bytes = processlama_wire::contract::FRAME_BYTES;
    config.concurrent_calls = processlama_wire::contract::CONCURRENT_CALLS;
    let handler = Arc::new(handler::HelperHandler::new(target));
    match server::serve(&config, handler, input, output, &clock, &acknowledged) {
        server::ServeEnd::Shutdown | server::ServeEnd::InputClosed => ExitCode::SUCCESS,
        _ => ExitCode::from(2),
    }
}

#[cfg(not(unix))]
fn serve(_target: processlama_wire::contract::Target) -> ExitCode {
    eprintln!("processlama-remote-helper: unsupported platform");
    ExitCode::from(3)
}
