//! ProcessLama's use cases. Qt-free and synchronous: the shell drives them on
//! its GUI thread and executes their requests through ports.

pub mod history;
pub mod order_lock;
pub mod session;
mod session_types;
pub mod time;
