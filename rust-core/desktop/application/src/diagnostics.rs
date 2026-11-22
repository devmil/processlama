//! Private, bounded diagnostic history (the devmil-logging contract):
//! reviewed codes with numeric fields only, in memory, no disk or upload.
//! Detailed capture is off by default and expires after at most 15 minutes.

use std::collections::VecDeque;
use std::sync::Mutex;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

pub const MAX_EVENTS: usize = 1000;
pub const MAX_BYTES: usize = 256 * 1024;
pub const MAX_EVENT_BYTES: usize = 2048;
pub const MAX_DETAILED: Duration = Duration::from_secs(15 * 60);

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Level {
    Fine,
    Info,
    Warning,
    Severe,
}

impl Level {
    const fn name(self) -> &'static str {
        match self {
            Self::Fine => "FINE",
            Self::Info => "INFO",
            Self::Warning => "WARNING",
            Self::Severe => "SEVERE",
        }
    }
}

struct History {
    events: VecDeque<String>,
    bytes: usize,
    detailed_until: Option<Instant>,
    clear_generation: u64,
}

static HISTORY: Mutex<History> = Mutex::new(History {
    events: VecDeque::new(),
    bytes: 0,
    detailed_until: None,
    clear_generation: 0,
});

fn valid_code(code: &str) -> bool {
    let bytes = code.as_bytes();
    !bytes.is_empty()
        && bytes.len() <= 101
        && bytes[0].is_ascii_alphabetic()
        && bytes[1..]
            .iter()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'_' | b'.' | b' ' | b'-'))
}

fn iso_now() -> String {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default();
    let secs = now.as_secs() as i64;
    let millis = now.subsec_millis();
    let days = secs.div_euclid(86_400);
    let rem = secs.rem_euclid(86_400);
    // Civil from days (Howard Hinnant).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    format!(
        "{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}.{millis:03}Z",
        rem / 3600,
        (rem / 60) % 60,
        rem % 60
    )
}

/// Records a reviewed event. `detailed` events are kept only while detailed
/// capture is on; below-INFO events likewise.
pub fn record(code: &str, level: Level, fields: &[(&str, f64)], detailed: bool) {
    let Ok(mut history) = HISTORY.lock() else {
        return;
    };
    let detailed_on = history.detailed_until.is_some_and(|until| Instant::now() < until);
    if (detailed || level < Level::Info) && !detailed_on {
        return;
    }
    if !valid_code(code) {
        return;
    }
    let mut line = format!("{} {} {code}", iso_now(), level.name());
    for (key, value) in fields.iter().take(16) {
        if valid_code(key) && value.is_finite() {
            line.push_str(&format!(" {key}={value}"));
        }
    }
    if line.len() > MAX_EVENT_BYTES {
        return;
    }
    history.bytes += line.len();
    history.events.push_back(line);
    while history.events.len() > MAX_EVENTS || history.bytes > MAX_BYTES {
        if let Some(removed) = history.events.pop_front() {
            history.bytes -= removed.len();
        }
    }
}

pub fn info(code: &str) {
    record(code, Level::Info, &[], false);
}

pub fn warning(code: &str) {
    record(code, Level::Warning, &[], false);
}

pub fn is_detailed() -> bool {
    HISTORY
        .lock()
        .is_ok_and(|history| history.detailed_until.is_some_and(|until| Instant::now() < until))
}

pub fn detailed_remaining() -> Option<Duration> {
    HISTORY.lock().ok().and_then(|history| {
        history
            .detailed_until
            .and_then(|until| until.checked_duration_since(Instant::now()))
    })
}

pub fn set_detailed(enabled: bool) {
    if let Ok(mut history) = HISTORY.lock() {
        history.detailed_until = enabled.then(|| Instant::now() + MAX_DETAILED);
    }
}

pub fn clear() {
    if let Ok(mut history) = HISTORY.lock() {
        history.events.clear();
        history.bytes = 0;
        history.clear_generation += 1;
    }
}

pub fn clear_generation() -> u64 {
    HISTORY.lock().map_or(0, |history| history.clear_generation)
}

/// Replaces URIs, emails, paths and secrets.
pub fn redact(value: &str) -> String {
    value
        .split(' ')
        .map(|word| {
            let lower = word.to_lowercase();
            if lower.starts_with("http://") || lower.starts_with("https://") {
                "<uri>".to_owned()
            } else if word.contains('@') && word.contains('.') && !word.starts_with('@') {
                "<email>".to_owned()
            } else if (word.starts_with('/') && word[1..].contains('/'))
                || (word.len() > 2 && word.as_bytes()[1] == b':' && matches!(word.as_bytes()[2], b'\\' | b'/'))
            {
                "<path>".to_owned()
            } else if ["password", "passphrase", "token", "secret", "cookie", "authorization", "key"]
                .iter()
                .any(|secret| lower.starts_with(&format!("{secret}=")) || lower.starts_with(&format!("{secret}:")))
            {
                "<secret>".to_owned()
            } else {
                word.to_owned()
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// The export text: schema, app, version, platform, then the events.
pub fn snapshot(application: &str, version: &str, platform: &str) -> String {
    let Ok(history) = HISTORY.lock() else {
        return String::new();
    };
    let mut text = format!(
        "Diagnostics schema 1\nApp: {}\nVersion: {}\nPlatform: {platform}\nMemory history: {} events, {} bytes\n\n",
        redact(application),
        redact(version),
        history.events.len(),
        history.bytes
    );
    text.push_str(
        &history
            .events
            .iter()
            .map(|line| redact(line))
            .collect::<Vec<_>>()
            .join("\n"),
    );
    text
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn records_reviewed_events_and_redacts_exports() {
        clear();
        info("startup");
        record("bad code!", Level::Info, &[], false);
        record("detail", Level::Info, &[], true);
        record("sample", Level::Info, &[("count", 3.0), ("nan", f64::NAN)], false);
        let text = snapshot("processlama", "1.0", "linux");
        assert!(text.contains("INFO startup"));
        assert!(text.contains("sample count=3"));
        assert!(!text.contains("nan="));
        assert!(!text.contains("bad code"));
        assert!(!text.contains("detail"));
        assert_eq!(redact("see /home/x/y token=abc https://a.b"), "see <path> <secret> <uri>");
    }
}
