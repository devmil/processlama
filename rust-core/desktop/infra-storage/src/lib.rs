//! Storage adapters. Locations match the Flutter builds, so snapshots and
//! cached icons carry over, and their preferences are imported once.

mod files;
mod icons;
mod preferences;
mod settings;
mod snapshots;

pub use files::{application_support_dir, write_atomically};
pub use icons::{FileIconCache, is_acceptable_icon};
pub use preferences::import_flutter_preferences;
pub use settings::FileSettingsStore;
pub use snapshots::FileSnapshotStore;
