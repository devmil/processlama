//! The bounded reconnect schedule after a lost connection.

/// 2, 5, 15 and 30 seconds, then every 60 seconds until ten minutes have
/// passed since the loss.
pub const RECONNECT_DELAYS_MS: [u64; 4] = [2_000, 5_000, 15_000, 30_000];
pub const RECONNECT_REPEAT_MS: u64 = 60_000;
pub const RECONNECT_WINDOW_MS: u64 = 10 * 60_000;

/// The delay before attempt `attempt` (from 0), or None when that attempt
/// would start after the window, `elapsed` ms after the loss.
pub fn reconnect_delay(attempt: usize, elapsed: u64) -> Option<u64> {
    let delay = RECONNECT_DELAYS_MS.get(attempt).copied().unwrap_or(RECONNECT_REPEAT_MS);
    (elapsed + delay <= RECONNECT_WINDOW_MS).then_some(delay)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Reconnector {
    pub lost_at: u64,
    pub attempts: usize,
    /// When the next attempt starts; None while one runs.
    pub next_at: Option<u64>,
}

impl Reconnector {
    /// Starts the schedule at `now`; None when even the first attempt is out.
    pub fn start(now: u64) -> Option<Self> {
        let delay = reconnect_delay(0, 0)?;
        Some(Self {
            lost_at: now,
            attempts: 0,
            next_at: Some(now + delay),
        })
    }

    /// Schedules the attempt after a retryable failure; false when exhausted.
    pub fn schedule_next(&mut self, now: u64) -> bool {
        match reconnect_delay(self.attempts, now.saturating_sub(self.lost_at)) {
            Some(delay) => {
                self.next_at = Some(now + delay);
                true
            }
            None => {
                self.next_at = None;
                false
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn schedule_backs_off_and_ends_with_the_window() {
        assert_eq!(reconnect_delay(0, 0), Some(2_000));
        assert_eq!(reconnect_delay(3, 0), Some(30_000));
        assert_eq!(reconnect_delay(9, 0), Some(60_000));
        assert_eq!(reconnect_delay(9, RECONNECT_WINDOW_MS - 30_000), None);
        let mut reconnector = Reconnector::start(100).unwrap();
        assert_eq!(reconnector.next_at, Some(2_100));
        reconnector.attempts = 1;
        assert!(reconnector.schedule_next(2_200));
        assert_eq!(reconnector.next_at, Some(7_200));
    }
}
