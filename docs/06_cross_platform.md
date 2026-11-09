# Cross-Platform Preparation

ProcessLama supports Windows, Linux, and macOS. Each platform uses the shared
Flutter UI and Rust `processtree` backend, with explicit capability states for
detail modules that are not available everywhere.

## Current Shape

- Rust process enumeration uses the native `processtree` backend on Windows,
  Linux, and macOS, with explicit capability states for unavailable detail modules.
- Flutter renders a platform capability matrix from
  `PlatformCapabilities.matrix`.
- Snapshot documents and tree synthesis are platform-neutral.
- Network telemetry remains Rust-owned. macOS uses `nettop`; Linux RPM and DEB
  packages install a root-owned eBPF service that publishes read-only cumulative
  counters under `/run/processlama` for the unprivileged app to consume.

## Distribution

Windows releases provide an x86_64 MSI and portable ZIP. Linux releases provide
RPM, AppImage, DEB, and portable tar bundles with a
FreeDesktop launcher, AppStream metadata, and a hicolor application icon. RPM
is the primary Fedora/KDE artifact. macOS continues to use a signed, notarized
DMG and Sparkle. Flatpak and Snap are deferred because their sandbox process
namespaces prevent full process-explorer behavior without a host escape or
external service.

Full system-wide Linux TCP/UDP throughput requires Linux 6.3 or newer and the
system service installed automatically by RPM and DEB packages. AppImage and
portable tar downloads include the service but remain unprivileged until the
user chooses the Linux-only install action in the app and authorizes it.

## Next Native Modules

- Linux: deepen `/proc` inspection and validate the eBPF sampler across common
  distributions and kernel configurations.
- Windows: add Toolhelp/PDH or ETW-backed process and metric ingestion.
- macOS: deepen inspector modules for files, sockets, signatures, Mach task
  state, and helper/elevation reporting.

All platform-specific fields should remain optional in shared models and should
be rendered through explicit capability or permission states when unavailable.
