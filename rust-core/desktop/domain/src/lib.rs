//! ProcessLama's values. This crate depends on no other workspace crate.

pub mod detail;
pub mod document;
pub mod process;
pub mod remote;
pub mod search;
pub mod settings;

pub use detail::*;
pub use document::*;
pub use process::*;
pub use remote::*;
pub use search::*;
pub use settings::*;
