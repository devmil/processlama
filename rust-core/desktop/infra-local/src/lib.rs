//! Local telemetry: one sampler thread per session source over the shared
//! processtree engine, and the processtree-to-domain mapping.

mod mapping;

pub use mapping::{LocalSnapshotMapper, map_detail, map_snapshot};

use processlama_application::{
    Cadence, CoreEvent, EventSink, LocalSignals, LocalTelemetry, SessionSource, SourceId,
};
use processlama_domain::{HostOperatingSystem, ProcessIdentity, ProcessSignal, SignalOutcome};
use processlama_telemetry::backend as processtree;
use std::sync::Arc;
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::thread;
use std::time::{Duration, Instant};

/// The operating system this build runs on.
pub const fn local_operating_system() -> HostOperatingSystem {
    if cfg!(target_os = "macos") {
        HostOperatingSystem::Macos
    } else if cfg!(target_os = "linux") {
        HostOperatingSystem::Linux
    } else if cfg!(target_os = "windows") {
        HostOperatingSystem::Windows
    } else {
        HostOperatingSystem::Unknown
    }
}

/// Configures where processtree renders process icons. Call before the first
/// sample.
pub fn configure_icon_cache(directory: Option<std::path::PathBuf>) {
    processlama_telemetry::configure_shared_icon_cache(directory);
}

pub struct LocalTelemetryAdapter {
    sink: Arc<dyn EventSink>,
}

impl LocalTelemetryAdapter {
    pub fn new(sink: Arc<dyn EventSink>) -> Self {
        Self { sink }
    }
}

impl LocalTelemetry for LocalTelemetryAdapter {
    fn create_source(&self, id: SourceId) -> Box<dyn SessionSource> {
        Box::new(LocalSource::start(id, Arc::clone(&self.sink)))
    }

    fn signal_handle(&self) -> Arc<dyn LocalSignals> {
        Arc::new(Signals)
    }
}

struct Signals;

impl LocalSignals for Signals {
    fn send_signal(&self, identity: ProcessIdentity, signal: ProcessSignal) -> SignalOutcome {
        let identity = processtree::ProcessIdentity {
            pid: identity.pid,
            start_time_unix_ms: identity.start_time_unix_ms,
        };
        let signal = match signal {
            ProcessSignal::Terminate => processtree::ProcessSignal::Terminate,
            ProcessSignal::Kill => processtree::ProcessSignal::Kill,
            ProcessSignal::Suspend => processtree::ProcessSignal::Suspend,
            ProcessSignal::Resume => processtree::ProcessSignal::Resume,
        };
        match processlama_telemetry::send_signal_outcome(identity, signal) {
            processlama_telemetry::SignalOutcome::Sent => SignalOutcome::Sent,
            processlama_telemetry::SignalOutcome::Denied => SignalOutcome::Denied,
            processlama_telemetry::SignalOutcome::NotFound => SignalOutcome::NotFound,
            processlama_telemetry::SignalOutcome::Unknown => SignalOutcome::Unknown,
        }
    }
}

enum Request {
    Cadence(Cadence, u32),
    SampleNow(u32),
    Detail(ProcessIdentity, u64),
}

/// Samples on its own thread at the cadence it was given. One sample is in
/// flight at a time; a request during a sample shares it.
struct LocalSource {
    requests: Sender<Request>,
}

impl LocalSource {
    fn start(id: SourceId, sink: Arc<dyn EventSink>) -> Self {
        let (requests, receiver) = mpsc::channel();
        let detail_sink = Arc::clone(&sink);
        thread::Builder::new()
            .name("processlama-sampler".into())
            .spawn(move || sampler(id, &receiver, sink.as_ref(), detail_sink))
            .expect("start the sampler thread");
        Self { requests }
    }
}

impl SessionSource for LocalSource {
    fn set_cadence(&self, cadence: Cadence, polling_interval_ms: u32) {
        let _ = self
            .requests
            .send(Request::Cadence(cadence, polling_interval_ms));
    }

    fn sample_now(&self, polling_interval_ms: u32) {
        let _ = self.requests.send(Request::SampleNow(polling_interval_ms));
    }

    fn fetch_detail(&self, identity: ProcessIdentity, generation: u64) {
        let _ = self.requests.send(Request::Detail(identity, generation));
    }
}

fn sampler(
    id: SourceId,
    requests: &Receiver<Request>,
    sink: &dyn EventSink,
    detail_sink: Arc<dyn EventSink>,
) {
    let mut cadence = Cadence::Paused;
    // The native polling interval: its rates span it.
    let mut polling_ms: u32 = 1000;
    let mut next_sample: Option<Instant> = None;
    let mut mapper = LocalSnapshotMapper::default();
    let (detail_tx, detail_rx) = mpsc::channel::<(ProcessIdentity, u64)>();
    thread::Builder::new()
        .name("processlama-inspector".into())
        .spawn(move || {
            while let Ok((identity, generation)) = detail_rx.recv() {
                // Only the newest request matters.
                let (mut identity, mut generation) = (identity, generation);
                while let Ok(newer) = detail_rx.try_recv() {
                    (identity, generation) = newer;
                }
                let detail = processlama_telemetry::inspect(processtree::ProcessIdentity {
                    pid: identity.pid,
                    start_time_unix_ms: identity.start_time_unix_ms,
                });
                detail_sink.post(CoreEvent::Detail {
                    source: id,
                    identity,
                    generation,
                    detail: Some(map_detail(detail)),
                });
            }
        })
        .expect("start the inspector thread");
    loop {
        let request = match next_sample {
            Some(at) => {
                let now = Instant::now();
                if at <= now {
                    Err(RecvTimeoutError::Timeout)
                } else {
                    requests.recv_timeout(at - now)
                }
            }
            None => requests.recv().map_err(|_| RecvTimeoutError::Disconnected),
        };
        let mut sample = false;
        match request {
            Ok(Request::Cadence(next, polling)) => {
                if let Cadence::Live(ms) = next {
                    polling_ms = ms;
                } else if polling > 0 && matches!(cadence, Cadence::Paused) {
                    polling_ms = polling;
                }
                if next != cadence {
                    cadence = next;
                    next_sample = cadence.interval_ms().map(|ms| {
                        Instant::now() + Duration::from_millis(u64::from(ms.clamp(250, 10_000)))
                    });
                }
            }
            Ok(Request::SampleNow(polling)) => {
                if matches!(cadence, Cadence::Paused) && polling > 0 {
                    polling_ms = polling;
                }
                sample = true;
            }
            Ok(Request::Detail(identity, generation)) => {
                let _ = detail_tx.send((identity, generation));
            }
            Err(RecvTimeoutError::Timeout) => {
                sample = true;
                next_sample = cadence.interval_ms().map(|ms| {
                    Instant::now() + Duration::from_millis(u64::from(ms.clamp(250, 10_000)))
                });
            }
            Err(RecvTimeoutError::Disconnected) => return,
        }
        if sample {
            // Coalesce further immediate requests into this sample.
            while let Ok(request) = requests.try_recv() {
                match request {
                    Request::Cadence(next, polling) => {
                        if let Cadence::Live(ms) = next {
                            polling_ms = ms;
                        } else if polling > 0 && matches!(cadence, Cadence::Paused) {
                            polling_ms = polling;
                        }
                        if next != cadence {
                            cadence = next;
                            next_sample = cadence.interval_ms().map(|ms| {
                                Instant::now()
                                    + Duration::from_millis(u64::from(ms.clamp(250, 10_000)))
                            });
                        }
                    }
                    Request::SampleNow(_) => {}
                    Request::Detail(identity, generation) => {
                        let _ = detail_tx.send((identity, generation));
                    }
                }
            }
            let result = {
                let mut engine = processlama_telemetry::shared_engine();
                engine.sample(u64::from(polling_ms), mapper.known_topology_version())
            };
            match result {
                Ok(sample) => match mapper.map(sample) {
                    Some(snapshot) => sink.post(CoreEvent::Sample {
                        source: id,
                        snapshot: Arc::new(snapshot),
                    }),
                    None => {
                        // A missing topology: ask for the full structure next time.
                        next_sample = Some(Instant::now());
                    }
                },
                Err(error) => sink.post(CoreEvent::SampleFailed {
                    source: id,
                    error: error.to_string(),
                }),
            }
        }
    }
}
