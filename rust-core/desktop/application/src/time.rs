//! Local wall-clock formatting.

use chrono::{Local, TimeZone};

/// `HH:mm:ss` in local time, or `Unknown` for a missing time.
pub fn format_clock(unix_ms: u64) -> String {
    if unix_ms == 0 {
        return "Unknown".into();
    }
    match Local.timestamp_millis_opt(unix_ms as i64).single() {
        Some(time) => time.format("%H:%M:%S").to_string(),
        None => "Unknown".into(),
    }
}

/// `yyyy-MM-dd HH:mm` in local time, or `Unknown`.
pub fn format_snapshot_time(unix_ms: u64) -> String {
    if unix_ms == 0 {
        return "Unknown".into();
    }
    match Local.timestamp_millis_opt(unix_ms as i64).single() {
        Some(time) => time.format("%Y-%m-%d %H:%M").to_string(),
        None => "Unknown".into(),
    }
}
