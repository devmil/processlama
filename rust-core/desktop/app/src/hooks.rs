//! Native window hooks the QML window calls once it is shown.

use qtbridge::qobject;

#[qobject(ConvertToCamelCase)]
mod platform_hooks {
    #[derive(Default)]
    pub struct PlatformHooks {}

    impl PlatformHooks {
        /// Gives macOS windows the unified, transparent toolbar title bar.
        #[qslot]
        fn configure_window(&self) {
            #[cfg(target_os = "macos")]
            processlama_infra_platform::macos::configure_windows();
        }

        /// Development: `PROCESSLAMA_SCREENSHOT=<png>[;<action>]` saves the
        /// window after startup (optionally after an action) and quits.
        #[qslot]
        fn screenshot_request(&self) -> String {
            std::env::var("PROCESSLAMA_SCREENSHOT").unwrap_or_default()
        }

        /// The desktop's text scale. Linux follows GTK's text-scaling-factor
        /// like the GTK and Flutter apps beside it; elsewhere 1.
        #[qslot]
        fn text_scale(&self) -> f64 {
            #[cfg(target_os = "linux")]
            {
                std::process::Command::new("gsettings")
                    .args(["get", "org.gnome.desktop.interface", "text-scaling-factor"])
                    .output()
                    .ok()
                    .filter(|output| output.status.success())
                    .and_then(|output| String::from_utf8_lossy(&output.stdout).trim().parse::<f64>().ok())
                    .filter(|scale| scale.is_finite())
                    .map_or(1.0, |scale| scale.clamp(0.5, 3.0))
            }
            #[cfg(not(target_os = "linux"))]
            {
                1.0
            }
        }

        /// The platform's reduce-motion accessibility setting.
        #[qslot]
        fn reduce_motion(&self) -> bool {
            #[cfg(target_os = "macos")]
            {
                processlama_infra_platform::macos::system_reduce_motion()
            }
            #[cfg(not(target_os = "macos"))]
            {
                false
            }
        }
    }
}

pub use platform_hooks::PlatformHooks;
