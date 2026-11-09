//! ProcessLama's flutter_rust_bridge facade. `api` translates bridge types and
//! calls the use cases in `processlama_telemetry`.

#[allow(clippy::all)]
mod frb_generated;

pub mod api;
pub mod child_process;
pub mod network;

pub(crate) use processlama_telemetry::backend as process_backend;
