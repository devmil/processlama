//! macOS: Sparkle updates and the unified toolbar window chrome.
#![allow(unsafe_code)]

use processlama_domain::ReleaseChannel;
use std::ffi::CString;

unsafe extern "C" {
    fn processlama_sparkle_available() -> bool;
    fn processlama_sparkle_configure(
        feed_url: *const std::ffi::c_char,
        beta: bool,
        interval_seconds: i64,
    );
    fn processlama_sparkle_check();
    fn processlama_configure_windows(mouse_tracking: bool);
    fn processlama_system_reduce_motion() -> bool;
}

pub fn sparkle_available() -> bool {
    // SAFETY: a plain query of the bundled framework.
    unsafe { processlama_sparkle_available() }
}

pub fn configure_sparkle(feed_url: &str, channel: ReleaseChannel) {
    let Ok(feed) = CString::new(feed_url) else {
        return;
    };
    // SAFETY: `feed` outlives the call; the bridge copies it.
    unsafe { processlama_sparkle_configure(feed.as_ptr(), channel == ReleaseChannel::Beta, 86_400) }
}

pub fn check_with_sparkle() {
    // SAFETY: dispatches to the main thread inside the bridge.
    unsafe { processlama_sparkle_check() }
}

/// Gives every app window the unified toolbar: a transparent 52 pt title bar
/// with the traffic lights centred in the app's own toolbar.
pub fn configure_windows() {
    // SAFETY: runs on the main thread; only touches AppKit windows.
    unsafe { processlama_configure_windows(true) }
}

pub fn system_reduce_motion() -> bool {
    // SAFETY: a plain accessibility query.
    unsafe { processlama_system_reduce_motion() }
}
