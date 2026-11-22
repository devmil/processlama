//! Whether the process tree keeps its visible order instead of resorting.

/// Debounce of the release, bridging a context menu that closes right before
/// its confirmation dialog opens.
pub const ORDER_LOCK_RELEASE_MS: u64 = 150;
/// How long a direct tree interaction keeps the order.
pub const INTERACTION_HOLD_MS: u64 = 2500;

/// The single owner of the tree order lock. Inputs come from independent
/// surfaces (hover, context menu, modal dialogs, interactions); acquisition is
/// immediate, the release is debounced. Time is passed in (monotonic ms).
#[derive(Clone, Debug, Default)]
pub struct TreeOrderLock {
    hovering: bool,
    context_menu_open: bool,
    modal_overlay_open: bool,
    interaction_until: Option<u64>,
    release_at: Option<u64>,
    locked: bool,
}

impl TreeOrderLock {
    pub fn locked(&self) -> bool {
        self.locked
    }

    /// Returns whether `locked` changed.
    pub fn set_hovering(&mut self, value: bool, now: u64) -> bool {
        if self.hovering == value {
            return false;
        }
        self.hovering = value;
        self.evaluate(now)
    }

    pub fn set_context_menu_open(&mut self, value: bool, now: u64) -> bool {
        if self.context_menu_open == value {
            return false;
        }
        self.context_menu_open = value;
        self.evaluate(now)
    }

    pub fn set_modal_overlay_open(&mut self, value: bool, now: u64) -> bool {
        if self.modal_overlay_open == value {
            return false;
        }
        self.modal_overlay_open = value;
        self.evaluate(now)
    }

    pub fn mark_interaction(&mut self, now: u64) -> bool {
        self.interaction_until = Some(now + INTERACTION_HOLD_MS);
        self.evaluate(now)
    }

    /// Drops the interaction hold (entering or leaving snapshot browsing).
    pub fn reset_interaction(&mut self, now: u64) -> bool {
        if self.interaction_until.take().is_none() {
            return false;
        }
        self.evaluate(now)
    }

    pub fn next_deadline(&self) -> Option<u64> {
        match (self.interaction_until, self.release_at) {
            (Some(a), Some(b)) => Some(a.min(b)),
            (a, b) => a.or(b),
        }
    }

    /// Applies expired holds and releases. Returns whether `locked` changed.
    pub fn on_time(&mut self, now: u64) -> bool {
        if self.interaction_until.is_some_and(|until| until <= now) {
            self.interaction_until = None;
        }
        if self.release_at.is_some_and(|at| at <= now) {
            self.release_at = None;
            if !self.any_surface_active(now) && self.locked {
                self.locked = false;
                return true;
            }
            return false;
        }
        self.evaluate(now)
    }

    fn any_surface_active(&self, now: u64) -> bool {
        self.hovering
            || self.context_menu_open
            || self.modal_overlay_open
            || self.interaction_until.is_some_and(|until| until > now)
    }

    fn evaluate(&mut self, now: u64) -> bool {
        if self.any_surface_active(now) {
            self.release_at = None;
            if !self.locked {
                self.locked = true;
                return true;
            }
            return false;
        }
        if !self.locked {
            return false;
        }
        if self.release_at.is_none() {
            self.release_at = Some(now + ORDER_LOCK_RELEASE_MS);
        }
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hover_locks_immediately_and_releases_after_the_debounce() {
        let mut lock = TreeOrderLock::default();
        assert!(lock.set_hovering(true, 0));
        assert!(lock.locked());
        assert!(!lock.set_hovering(false, 10));
        assert!(lock.locked());
        assert_eq!(lock.next_deadline(), Some(10 + ORDER_LOCK_RELEASE_MS));
        assert!(!lock.on_time(100));
        assert!(lock.on_time(160));
        assert!(!lock.locked());
    }

    #[test]
    fn overlapping_surfaces_keep_the_lock_continuous() {
        let mut lock = TreeOrderLock::default();
        lock.set_context_menu_open(true, 0);
        lock.set_context_menu_open(false, 5);
        lock.set_modal_overlay_open(true, 50);
        assert!(!lock.on_time(200));
        assert!(lock.locked());
    }

    #[test]
    fn interactions_hold_for_their_duration() {
        let mut lock = TreeOrderLock::default();
        lock.mark_interaction(0);
        assert!(lock.locked());
        lock.on_time(INTERACTION_HOLD_MS);
        assert!(lock.locked());
        assert!(lock.on_time(INTERACTION_HOLD_MS + ORDER_LOCK_RELEASE_MS));
        assert!(!lock.locked());
    }
}
