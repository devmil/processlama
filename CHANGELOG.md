# Changelog

All notable changes to ProcessLama, formerly Mimameidr are documented here.

## [Unreleased Stable]

### Added

- ProcessLama is now open source under the MIT license, with public build and contribution instructions.

- Adopt shared devmil-logging: bounded memory history, session-limited detailed capture, clear controls, and preview-gated Save/Share export; no automatic application log files or release console output.

- Upgrade Flutter to 3.47.8 to include the eMudhra certificate security fix in future builds.

### Added

- Find processes by exact local TCP/UDP port and choose process name, PID, user,
  command line, or executable path as the search aspect. Ports are listed as
  listening ports (TCP listeners and UDP on well-known ports) and other local
  ports, in the inspector for each process or its whole subtree and in a
  sortable Ports column. Selecting a port, typing `:8080`, or a bare port number
  shows every process using it; a typed `port:` search ends once its text is
  cleared. Sockets connected to a local listener link to that process. Port data
  also travels with remote and saved snapshots. Remote helper compatibility is
  now version 3; existing remote hosts require the helper update.
- Added remote hosts: open Linux (x86_64, arm64) and macOS machines in their
  own tabs through your OpenSSH configuration. After asking, ProcessLama
  installs a small helper into `~/.local/lib/processlama` on the host (never
  with sudo) and streams the process tree with metrics, icons, inspector
  details and process actions whose confirmation names the host. A dropped
  connection keeps the last sample marked stale, leaves a gap in the history
  charts and reconnects automatically; remote tabs are restored on launch.
  Preferences → Remote hosts manages the hosts, removes the helper from a
  host and sizes or clears the remote icon cache. A setup guide is on the
  website.
- Added standalone packages of the Linux network service (RPM, DEB and tar
  for x86_64 and arm64) for Linux hosts without the desktop app, built by the
  release pipeline and listed on the downloads page under "Network service for
  remote Linux hosts".
- Added a row density preference (compact, regular, comfortable) that sets
  the height of process tree and list rows; compact stays the default.
- Right-click a saved filter in the sidebar to delete it.
- Hovering an inspector history chart highlights that sample and shows its
  value.
- Added Windows x86_64 releases as an MSI and portable ZIP, built on the native
  Windows Forgejo runner alongside Windows CI coverage.
- Added manual update checks on Windows and Linux that compare the installed
  build with the selected release channel and link to the download page.
- Redesigned the downloads page with clearer release cards, native platform
  logos, and Windows, macOS, and Linux sections.
- Added per-process and subtree storage read/write throughput, sortable storage
  columns, cumulative I/O totals, and a combined storage history graph.
- Added Linux desktop distribution as RPM, AppImage, DEB, and portable tar
  bundles, including desktop-menu, AppStream, and icon metadata.
- Added native Linux `/proc` telemetry for process enumeration, CPU and memory
  metrics, process actions, file descriptors, threads, permission states, and
  localized application names, and desktop-theme application icons.
- Added system-wide Linux TCP/UDP throughput accounting through a narrowly
  scoped eBPF service installed by RPM and DEB packages. Portable Linux builds
  now include a Linux-only install or repair action, and the inspector marks
  network data unavailable when the service is missing or stopped.
- Added Linux desktop builds to Forgejo CI and Linux/macOS downloads to the
  website release archive.
- The details panel can now be resized by dragging its divider, and the chosen
  width is remembered across launches.
- Typing while the process tree is focused now starts an in-tree search that
  highlights matching rows without filtering the tree.
- Process rows now expose terminate, force-kill, suspend, and resume actions
  from the context menu; terminate, force-kill, and suspend prompt for
  confirmation before sending the signal.
- Rebuilt the desktop process explorer on Devmil's shared Meridian design
  system: a unified title bar and toolbar, a sidebar on the window ground, the
  process tree and inspector as rounded islands with an inset selection bar,
  a status bar with the live polling state and totals, Meridian menus, dialogs
  and toasts, Lucide icons, bundled Geist and Geist Mono fonts, live metric
  bars, row heat tinting, and a row-heatmap preference. Preferences gained an
  appearance setting (system, light or dark).
- Integrated Linux window controls into the app toolbar.
- Exported snapshot documents can now be opened from the snapshots rail and are
  added to the saved snapshot list when opened.
- Saved snapshots can now be renamed from the snapshots rail, renamed snapshots
  use their name as the default export filename, and snapshot entries now
  include the capture date.
- Inspector metric graphs now show compact scale legends.
- Inspector tabs now show real per-process open files, sockets, threads, and
  security metadata on macOS, with restricted-process hints when macOS denies
  access instead of referencing a privileged helper.
- Process overview now includes resolved user names, thread and open-file
  counts, virtual memory, nice, and priority values.
- The inspector overview is now focused on highlight metrics and history
  graphs, with process/security metadata moved to a details tab and files plus
  sockets combined into one tab.
- Added a release-channel preference and macOS Sparkle channel handling so beta
  builds follow beta updates by default while still seeing stable releases.

### Changed

- Preferences are split into pages (Appearance, Process tree, Columns, Remote
  hosts and Updates) listed beside the selected page, instead of one long
  column. "Manage remote hosts…" in the tab strip opens the Remote hosts page.
- ProcessLama's accent is now signal green instead of blue (Meridian 1.1.0),
  so it no longer looks like GitLama. Selection, focus, the live dot, the
  About ground, the app icon (with an ivory pulse line) and the website follow.
- The Linux, Windows and macOS app icons now use the rounded desktop icon
  with a transparent margin instead of a full square. The portable Linux tar
  names the icon after the app ID, `de.devmil.processlama.png`.
- Mimameidr is now ProcessLama, with the Lama app icon and a small Lama at the
  foot of the sidebar that opens About. ProcessLama uses new application IDs,
  settings storage, and update feeds; it installs as a new app, and settings
  from Mimameidr builds are not carried over.
- Removed horizontal rules between process rows for a calmer, less grid-like
  process tree.
- The inspector overview now keeps its summary metrics in a compact two-column
  grid, with paired Network and Storage values aligned in two-line history
  headers.
- Releases now run as one protected Forgejo workflow that builds native Linux
  and macOS artifacts, publishes Forgejo Releases, mirrors GitHub Releases,
  and updates the website and Sparkle feed without committing new binaries.
- Linux now uses the desktop's native window decoration and caption buttons,
  with app actions kept in the compact ProcessLama toolbar.
- Linux now expands the `systemd` user-manager branch on first load so desktop
  processes are visible without an extra manual expansion.
- Release preparation now creates only version, notes, commit, and tag metadata;
  Linux and macOS bundles are built from that immutable tag and committed in
  separate platform publication steps.

### Fixed

- macOS process refresh now tolerates rapid process creation during builds,
  avoiding a bootstrap error when the process table grows while being read.
  Remote helper compatibility is now version 3; update existing remote helpers.

- Process tree ordering stays steady while a process context menu is open and
  when hovering the tree on macOS while another app is active.
- Linux network rates are shown again when the network service is installed;
  the telemetry core read the service snapshot from its pre-rename path.
- Reduced Linux rounded-window rendering overhead by using native rounded
  borders around an accelerated rectangular Flutter surface, with the border
  following the app theme and disappearing when maximized, tiled or fullscreen.
- Fixed release/profile builds bundling an unoptimized Rust process collector.

- Linux now picks up application names and icons for apps installed while
  ProcessLama is running.

- Website updates now load the latest design and About panel for returning visitors.

- Fixed cut-out window corners on Linux desktops such as Fedora 44 with rounded native clipping, while preserving shadows and resize borders.
- Reduced live monitoring overhead with immediate CPU-bar updates, shared
  process-tree caching, reused metric histories, and less redundant sorting
  and history storage. Process collection now handles deep trees and cyclic
  parent links safely.
- Locking the process tree now also keeps the row order still while CPU and
  other metrics keep updating, instead of only holding back new and exited
  processes.
- Storage history now shows reads above the axis and writes below it; Network
  history labels and paired rates now list outbound traffic before inbound.
- macOS now shows a native, system-colored launch screen that fades in, remains
  visible long enough to recognize, and fades out after Flutter initializes.
  The macOS build temporarily uses Skia to avoid a Flutter Impeller crash.
- The macOS launch screen no longer flashes the process list before appearing,
  and the app identity now aligns vertically with the traffic lights.
- Reduced Linux monitoring overhead by caching stable process metadata,
  inspecting file descriptors only for the selected process, and limiting
  network-helper lifetime checks to network-active processes. Resize work now
  excludes a large off-screen table cache and pauses telemetry publication
  during the drag.
- The custom macOS window header now supports native-feeling drag and
  double-click zoom/restore behavior without changing its design.
- Holding the up or down arrow in the process tree now keeps moving the
  selection instead of only scrolling the list.
- Process tree hover highlighting now covers the full row, matching selection.
- The toolbar search field hover state now covers the whole field instead of
  only the text-editing area.
- Network history graphs now show outbound traffic above the axis and inbound
  traffic below it in one combined chart.
- Process rows now select immediately on primary click instead of waiting for
  double-click detection.
- Inspector metric history now renders as bar charts instead of flat line
  sparklines.
- The process-name column no longer stretches to fill the whole table on wide
  windows; it caps at a comfortable width until manually resized.
- Search match navigation now scrolls the selected process row into view more
  reliably.
- Process tree cell content is vertically centered more consistently.
- Release DMGs now include an Applications shortcut for drag-and-drop install.
- Per-process network metrics now recover automatically if the macOS sampler
  stalls or exits unexpectedly.
- Snapshot export now works from signed release builds by preserving the
  macOS user-selected read/write entitlement.
- Bundled command-line helper processes now show their executable name in the
  process tree instead of looking like another copy of the parent app bundle.

## [Unreleased Beta]

## [1.0.0-beta.35] - 2026-11-09

### Added

- ProcessLama is now open source under the MIT license, with public build and contribution instructions.

- Adopt shared devmil-logging: bounded memory history, session-limited detailed capture, clear controls, and preview-gated Save/Share export; no automatic application log files or release console output.

## [1.0.0-beta.34] - 2026-10-29

- Upgrade Flutter to 3.47.8 to include the eMudhra certificate security fix in future builds.

## [1.0.0-beta.33] - 2026-10-28

### Changed

- The overview's port list starts collapsed again behind its port count, and
  collapses again when another process is selected; expand it to see the
  listening and other local port chips.

## [1.0.0-beta.32] - 2026-10-27

### Added

- A sortable Ports column shows each process's listening ports and how many
  other local ports it uses.
- Sockets connected to a port another local process listens on link to that
  process in the Files & Sockets tab.

### Changed

- Ports are split into listening ports (TCP listeners and UDP sockets on
  well-known ports below 1024) and other local ports, mostly outgoing
  connections. The inspector lists them as chips instead of behind a count;
  selecting one shows every process using that port.
- Typing `:8080` searches by port, and a bare port number in the default search
  also finds the processes using that port. A typed `port:` search returns to
  the chosen search aspect once the text is cleared or is no longer a port.
- The remote helper now reports listening ports; it stays at compatibility
  version 3, so update helpers from earlier betas.

### Fixed

- macOS process refresh now tolerates rapid process creation during builds,
  avoiding a bootstrap error when the process table grows while being read.
  Remote helper compatibility is now version 3; update existing remote helpers.

## [1.0.0-beta.31] - 2026-10-26

### Fixed

- The inspector’s Tree mode now lists ports from the selected process and all
  subprocesses, including collapsed descendants. Process mode shows only the
  selected process’s ports. The overview starts with a compact port count;
  expand it to see the full list.

## [1.0.0-beta.30] - 2026-10-26

### Added

- Find processes by exact local TCP/UDP port and choose process name, PID, user,
  command line, or executable path as the search aspect. The inspector lists
  each process’s occupied local ports; port data also travels with remote and
  saved snapshots. Remote helper compatibility is now version 2; existing remote
  hosts require the helper update.

## [1.0.0-beta.29] - 2026-10-21

### Fixed

- Process tree ordering stays steady while a process context menu is open and
  when hovering the tree on macOS while another app is active.

## [1.0.0-beta.28] - 2026-10-15

### Changed

- Preferences are split into pages (Appearance, Process tree, Columns, Remote
  hosts and Updates) listed beside the selected page, instead of one long
  column, using Meridian 1.13's settings dialog. "Manage remote hosts…" in the
  tab strip opens the Remote hosts page directly.

### Fixed

- The Windows portable ZIP is published again; 1.0.0-beta.27 shipped only the
  installer because the ZIP could not store the bundled remote helpers.

## [1.0.0-beta.27] - 2026-10-15

### Added

- Added remote hosts: open Linux (x86_64, arm64) and macOS machines in their
  own tabs through your OpenSSH configuration. After asking, ProcessLama
  installs a small helper into `~/.local/lib/processlama` on the host (never
  with sudo) and streams the process tree with metrics, icons, inspector
  details and process actions whose confirmation names the host. A dropped
  connection keeps the last sample marked stale, leaves a gap in the history
  charts and reconnects automatically; remote tabs are restored on launch.
  Preferences → Remote hosts manages the hosts, removes the helper from a
  host and sizes or clears the remote icon cache. A setup guide is on the
  website.
- Added standalone packages of the Linux network service (RPM, DEB and tar
  for x86_64 and arm64) for Linux hosts without the desktop app, built by the
  release pipeline and listed on the downloads page under "Network service for
  remote Linux hosts".

### Fixed

- Linux network rates are shown again when the network service is installed;
  the telemetry core read the service snapshot from its pre-rename path.

## [1.0.0-beta.26] - 2026-10-05

### Fixed

- Reduced Linux rounded-window rendering overhead by using native rounded
  borders around an accelerated rectangular Flutter surface, with the border
  following the app theme and disappearing when maximized, tiled or fullscreen.
- Fixed release/profile builds bundling an unoptimized Rust process collector.

## [1.0.0-beta.25] - 2026-10-05

### Changed

- ProcessLama's accent is now signal green instead of blue (Meridian 1.1.0),
  so it no longer looks like GitLama. Selection, focus, the live dot, the
  About ground, the app icon (with an ivory pulse line) and the website follow.

## [1.0.0-beta.24] - 2026-10-05

### Changed

- The Linux, Windows and macOS app icons now use the rounded desktop icon
  with a transparent margin instead of a full square. The portable Linux tar
  names the icon after the app ID, `de.devmil.processlama.png`.

### Fixed

- Linux now picks up application names and icons for apps installed while
  ProcessLama is running.

## [1.0.0-beta.23] - 2026-10-04

### Fixed

- Website updates now load the latest design and About panel for returning visitors.

## [1.0.0-beta.22] - 2026-10-04

### Changed

- Mimameidr is now ProcessLama, with the Lama icon and an About button at the sidebar foot. This development build makes a clean switch to ProcessLama application IDs and settings.

## [1.0.0-beta.21] - 2026-10-03

### Fixed

- Fixed cut-out window corners on Linux desktops such as Fedora 44 with rounded native clipping, while preserving shadows and resize borders.

## [1.0.0-beta.20] - 2026-09-29

### Added

- Portable Linux builds now include an install or repair action for the network
  service, accessible from Preferences and the unavailable network indicator.

### Changed

- Integrated Linux window controls into the app toolbar.

### Fixed

- Network metrics now show an unavailable state when the Linux telemetry
  service is missing or stopped instead of reporting zero traffic.

## [1.0.0-beta.19] - 2026-09-28

### Fixed

- Reduced live monitoring overhead with immediate CPU-bar updates, shared
  process-tree caching, reused metric histories, and less redundant sorting
  and history storage. Process collection now handles deep trees and cyclic
  parent links safely.

## [1.0.0-beta.18] - 2026-09-27

### Added

- Added a row density preference (compact, regular, comfortable) that sets
  the height of process tree and list rows; compact stays the default.

## [1.0.0-beta.17] - 2026-09-26

### Added

- Right-click a saved filter in the sidebar to delete it.

## [1.0.0-beta.16] - 2026-09-26

### Fixed

- Updated the Meridian design system to 0.6.0: the details-panel divider now
  follows the pointer from where the drag started instead of lagging behind,
  clicking a toolbar button no longer pulls keyboard focus out of the process
  tree, and the polling-interval picker keeps a fixed width sized to its
  longest option.

## [1.0.0-beta.15] - 2026-09-26

### Added

- Hovering an inspector history chart highlights that sample and shows its
  value.

### Changed

- Rebuilt the whole interface on Devmil's shared Meridian design system: a
  unified title bar and toolbar (lock, snapshot, updates, inspector and
  preferences), a sidebar on the window ground, the process tree and inspector
  as rounded islands, an inset rounded selection that turns solid while the
  tree has keyboard focus, and a status bar showing the polling state, the
  paused live ordering and the process count.
- Context menus, confirmations, the rename dialog and notifications now use
  Meridian menus, dialogs and toasts; destructive process actions sit at the
  end of the process menu.
- The inspector shows details as aligned label and value lists and explains
  restricted or unsupported sections in banners.
- Preferences are a settings form with an appearance choice (system, light or
  dark) and column visibility and order.

### Fixed

- Locking the process tree now also keeps the row order still while CPU and
  other metrics keep updating, instead of only holding back new and exited
  processes.

## [1.0.0-beta.14] - 2026-09-23

### Fixed

- Storage history now shows reads above the axis and writes below it, while
  Network history lists outbound traffic before inbound.

### Added

- Added Windows x86_64 MSI and portable ZIP releases, native Windows CI, and
  update notifications for Windows and Linux.
- Redesigned the downloads page around platform-specific download sections and
  OS logos.

## [1.0.0-beta.13] - 2026-09-20

### Fixed

- The macOS launch screen no longer flashes the process list before appearing,
  and the app identity now aligns vertically with the traffic lights.

## [1.0.0-beta.12] - 2026-09-20

### Changed

- Removed horizontal rules between process rows for a calmer, less grid-like
  process tree.

## [1.0.0-beta.11] - 2026-09-20

### Fixed

- Animated the macOS launch screen and temporarily switched the macOS renderer
  to Skia to prevent an Impeller crash seen immediately after updating.

## [1.0.0-beta.10] - 2026-09-20

### Added

- Added process and subtree storage read/write columns, cumulative I/O details,
  and a combined storage history graph.
- Added RPM, AppImage, DEB, and portable tar downloads for Linux, alongside the
  existing macOS DMG.
- Added native Linux process enumeration, metrics, actions, open-file details,
  thread inspection, localized application names, and desktop-theme
  application icons.
- Added system-wide Linux TCP/UDP throughput metrics to RPM and DEB installs.

### Changed

- The inspector overview now uses a shorter detail layout with paired Network
  and Storage values aligned above their charts.
- Release builds now publish through Forgejo and mirror downloadable artifacts
  to GitHub Releases.
- Linux now uses native desktop window decorations and caption buttons, with
  app actions kept in Mimameidr's compact toolbar.
- Release tags are now created independently of platform builds, allowing Linux
  and macOS bundles to be produced and published from separate machines.
- Linux expands the nested `systemd` branch by default.

### Fixed

- macOS now shows the Mimameidr icon on a native background while Flutter
  initializes instead of briefly showing a black window.
- Reduced Linux CPU use and resize stutter by caching stable process metadata,
  avoiding global file-descriptor scans, reducing off-screen table layout, and
  pausing process refresh publication during a resize.

## [1.0.0-beta.9] - 2026-08-09

### Fixed

- Network graph label overflow (again)

## [1.0.0-beta.8] - 2026-08-04

### Fixed

- Selected process rows now retain their lower separator, so they remain
  visually distinct from the following row.

## [1.0.0-beta.7] - 2026-07-08

### Added

- Exported snapshot documents can now be opened from the snapshots rail and are
  added to the saved snapshot list when opened.
- Saved snapshots can now be renamed from the snapshots rail, renamed snapshots
  use their name as the default export filename, and snapshot entries now
  include the capture date.

### Fixed

- Snapshot export now works from signed release builds by preserving the
  macOS user-selected read/write entitlement.
- Bundled command-line helper processes now show their executable name in the
  process tree instead of looking like another copy of the parent app bundle.

## [1.0.0-beta.6] - 2026-07-06

### Added

- Beta builds now follow the beta update channel by default, with a Preferences
  option to switch back to stable updates.

### Changed

- Removed the privacy mode and reduce motion preferences until those behaviors
  are fully implemented.

### Fixed

- The custom macOS window header now supports native-feeling drag and
  double-click zoom/restore behavior without changing its design.
- Per-process network metrics now recover automatically if the macOS sampler
  stalls or exits unexpectedly.

## [1.0.0-beta.5] - 2026-07-03

### Added

- The details panel can now be resized by dragging its divider, and the chosen
  width is remembered across launches.
- The inspector overview is now focused on highlight metrics and history
  graphs, with process/security metadata moved to a details tab and files plus
  sockets combined into one tab.

### Fixed

- Holding the up or down arrow in the process tree now keeps moving the
  selection instead of only scrolling the list.
- Process tree and toolbar search hover states now cover the full intended
  control, and network history uses one combined in/out chart.

## [1.0.0-beta.4] - 2026-06-30

- Improve App icon handling

## [1.0.0-beta.3] - 2026-06-30

### Added

- Added process terminate, force-kill, suspend, and resume actions to the
  process row context menu, with confirmation prompts before destructive
  signals.
- Added scale legends to inspector metric graphs.
- Added real macOS inspector data for open files, sockets, threads, and
  security metadata, plus restricted-process hints when access is denied.
- Added resolved user names, thread and open-file counts, virtual memory, nice,
  and priority values to the process overview.

### Fixed

- Search match navigation now scrolls the selected process row into view more
  reliably.
- Process tree cell content is vertically centered more consistently.
- Release DMGs now include an Applications shortcut for drag-and-drop install.

## [1.0.0-beta.2] - 2026-06-28

### Added

- Added bundled Geist and Geist Mono typography and the new Mimameidr component
  layer for toolbar buttons, search fields, popups, rail items, table headers,
  metric cells, inspector tabs, segmented controls, live indicators, and custom
  scrollbars.
- Added subtle UI motion for selection, polling status, inspector open/close,
  spawned rows, and sort indicators.
- Added reduce-motion and CPU row-heatmap preferences.

### Fixed

- The app icon now renders the Mimameidr mark instead of a solid blue square on
  macOS.

## [1.0.0-beta.1] - 2026-06-23

### Added

- Initial beta release track scaffolding.
- Typing while the process tree is focused now starts an in-tree search that
  highlights matching rows without filtering the tree.

### Fixed

- Process rows now select immediately on primary click instead of waiting for
  double-click detection.
- Inspector metric history now renders as bar charts instead of flat line
  sparklines.


[Unreleased Stable]: https://github.com/devmil/processlama/compare/v1.0.0-beta.35-42...HEAD
[Unreleased Beta]: https://github.com/devmil/processlama/compare/v1.0.0-beta.35-42...HEAD
[1.0.0-beta.35]: https://github.com/devmil/processlama/releases/tag/v1.0.0-beta.35-42
