//! ProcessLama's use cases. Qt-free and synchronous: the shell drives them on
//! its GUI thread and executes their requests through ports.

pub mod core;
pub mod diagnostics;
pub mod events;
pub mod history;
pub mod icons;
pub mod order_lock;
pub mod ports;
pub mod reconnect;
pub mod remote;
pub mod remote_ports;
pub mod session;
mod session_types;
pub mod time;

pub use crate::core::*;
pub use events::*;
pub use ports::*;
pub use remote::{
    ConnectionState, InstallChoice, InstallPrompt, ProbeOutcome, ProfileDraft, RemoteCommand,
    RemoteEvent,
};
pub use remote_ports::*;
pub use session::*;
