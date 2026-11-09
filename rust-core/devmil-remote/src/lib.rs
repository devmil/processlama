//! Product-neutral helper transport shared by Devmil desktop applications:
//! length-prefixed frames, the stdio server runtime with interactive and bulk queues and
//! credit-limited subscriptions, descriptor isolation, and child processes owned by Rust.
//!
//! This crate must not depend on any application crate.
pub mod child;
pub mod frame;
pub mod server;
#[cfg(unix)]
pub mod streams;
