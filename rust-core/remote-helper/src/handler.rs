//! Answers the protocol's calls and subscriptions.
use crate::icons::IconStore;
use crate::telemetry::{Cadence, IconHasher, TelemetryStream};
use devmil_remote::server::{CallError, Handler, Publisher, lock};
use processlama_telemetry::SignalOutcome;
use processlama_telemetry::backend::{ProcessIdentity, ProcessSignal};
use processlama_wire::contract::{Method, Signal, Target, Topic};
use serde_json::{Map, Value, json};
use std::sync::{Arc, Mutex};

pub struct HelperHandler {
    target: Target,
    telemetry: Mutex<Option<Arc<TelemetryStream>>>,
    icons: Arc<IconStore>,
}

impl HelperHandler {
    pub fn new(target: Target) -> Self {
        Self {
            target,
            telemetry: Mutex::new(None),
            icons: IconStore::start(),
        }
    }
}

fn identity(arguments: &Map<String, Value>) -> Result<ProcessIdentity, CallError> {
    let pid = arguments
        .get("pid")
        .and_then(Value::as_i64)
        .and_then(|pid| i32::try_from(pid).ok())
        .filter(|pid| *pid > 0)
        .ok_or(CallError("invalidRequest"))?;
    let start = arguments
        .get("start")
        .and_then(Value::as_u64)
        .ok_or(CallError("invalidRequest"))?;
    Ok(ProcessIdentity {
        pid,
        start_time_unix_ms: start,
    })
}

fn signal(arguments: &Map<String, Value>) -> Result<ProcessSignal, CallError> {
    let name = arguments
        .get("signal")
        .and_then(Value::as_str)
        .and_then(Signal::parse)
        .ok_or(CallError("invalidRequest"))?;
    Ok(match name {
        Signal::Terminate => ProcessSignal::Terminate,
        Signal::Kill => ProcessSignal::Kill,
        Signal::Suspend => ProcessSignal::Suspend,
        Signal::Resume => ProcessSignal::Resume,
    })
}

impl Handler for HelperHandler {
    fn hello_body(&self) -> Value {
        crate::host::hello_body(self.target, true).to_value()
    }

    fn is_bulk(&self, method: &str) -> bool {
        Method::parse(method).is_some_and(Method::is_bulk)
    }

    fn call(&self, method: &str, arguments: &Map<String, Value>) -> Result<Value, CallError> {
        match Method::parse(method) {
            Some(Method::TelemetryCadence) => {
                let cadence = Cadence::parse(arguments).ok_or(CallError("invalidRequest"))?;
                let stream = lock(&self.telemetry).clone();
                match stream {
                    Some(stream) if !stream.is_stopped() => {
                        stream.set_cadence(cadence);
                        Ok(json!({}))
                    }
                    _ => Err(CallError("notFound")),
                }
            }
            Some(Method::ProcessDetail) => {
                let identity = identity(arguments)?;
                Ok(crate::detail::encode(processlama_telemetry::inspect(
                    identity,
                )))
            }
            Some(Method::ProcessSignal) => {
                let identity = identity(arguments)?;
                let signal = signal(arguments)?;
                let outcome = match processlama_telemetry::send_signal_outcome(identity, signal) {
                    SignalOutcome::Sent => "sent",
                    SignalOutcome::Denied => "denied",
                    SignalOutcome::NotFound => "notFound",
                    SignalOutcome::Unknown => "unknown",
                };
                Ok(json!({"outcome": outcome}))
            }
            Some(Method::HostFacts) => Ok(crate::host::facts()),
            Some(Method::HelperRemoveState) => Ok(json!({"removed": crate::host::remove_state()})),
            Some(Method::IconsFetch) => self
                .icons
                .fetch(arguments)
                .ok_or(CallError("invalidRequest")),
            None => Err(CallError("unsupportedCommand")),
        }
    }

    fn subscribe(
        &self,
        topic: &str,
        arguments: &Map<String, Value>,
        publisher: Publisher,
    ) -> Result<Value, CallError> {
        if Topic::parse(topic) != Some(Topic::Telemetry) {
            return Err(CallError("unsupportedTopic"));
        }
        let cadence = Cadence::parse(arguments).ok_or(CallError("invalidRequest"))?;
        let mut slot = lock(&self.telemetry);
        if let Some(existing) = slot.as_ref() {
            if !existing.is_stopped() {
                return Err(CallError("capacity"));
            }
        }
        let icons: Arc<dyn IconHasher> = self.icons.clone();
        *slot = Some(TelemetryStream::start(
            publisher,
            cadence,
            crate::host::icon_cache_dir(),
            icons,
        ));
        Ok(json!({}))
    }

    fn shutdown(&self) {
        if let Some(stream) = lock(&self.telemetry).take() {
            stream.stop();
        }
        self.icons.stop();
    }
}
