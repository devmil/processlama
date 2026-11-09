# Release Notes

## [Unreleased Stable]

### Added

- ProcessLama is now open source under the MIT license, with public build and contribution instructions.

- Diagnostics now keep bounded recent history in memory instead of writing logs automatically. Settings lets you temporarily enable detailed diagnostics, review an export, save it, or share it where supported. Nothing is sent automatically.

- Upgrade Flutter to 3.47.8 to include the eMudhra certificate security fix in future builds.

### Added

- See which ports each process listens on in the inspector and a sortable
  Ports column. Click a port, or type `:8080`, to find every process using it,
  and jump from a local connection to the process on the other end.
- Watch Linux and macOS machines in their own tabs over SSH: click **+** in
  the new tab strip, add a host from your `~/.ssh/config`, and ProcessLama
  installs a small helper on it once you agree. Remote tabs show the same
  tree, inspector and process actions, stay readable while a connection
  drops, and reconnect on their own.
- The Linux network service is now available on its own for x86_64 and arm64
  hosts, so machines without ProcessLama can report per-process network rates.
- Choose compact, regular, or comfortable row density in Preferences.
- Right-click a saved filter in the sidebar to delete it.
- Hover a history chart to see the value of any sample.
- ProcessLama now ships for 64-bit Windows as an installer and portable ZIP.
- Windows and Linux can check the selected release channel and open the
  downloads page when a new build is available.
- The downloads page now groups files by operating system with clear platform
  logos and package details.
- Process rows and the inspector now show storage read/write activity, subtree
  totals, cumulative I/O, and a combined storage history graph.
- ProcessLama is now distributed for Linux as RPM, AppImage, DEB, and portable
  tar downloads, with RPM recommended for Fedora.
- Linux now shows the native process tree with CPU and memory metrics, process
  actions, open files, threads, application names and icons, and clear
  permission states.
- RPM and DEB installs now show live per-process Linux network throughput and
  open the nested `systemd` branch automatically. Portable Linux builds can
  install or repair the network service from the app, and missing service data
  is clearly marked unavailable.
- The details panel can now be resized by dragging its divider; the width is
  remembered between launches.
- Typing in the process tree now searches and highlights matching rows without
  hiding the rest of the tree.
- Process rows now include terminate, force-kill, suspend, and resume actions,
  with a confirmation prompt before destructive signals are sent.
- Exported snapshot documents can now be opened from the snapshots rail and are
  kept in the saved snapshot list.
- Saved snapshots can now be renamed, use their name when exported, and the
  snapshots rail now shows the capture date as well as the time.
- ProcessLama now looks and feels like the rest of the Devmil apps: a unified
  toolbar with integrated Linux window controls, a calm sidebar, the process
  tree and inspector as rounded panels,
  a status bar with the live state, consistent menus and dialogs, live
  metrics, row heat tinting, and a light, dark or system appearance setting.
- Inspector metric graphs now show compact scale labels.
- Inspector tabs now show real macOS process details for files, sockets,
  threads, and security, and clearly label restricted processes when macOS
  denies access.
- The inspector is cleaner: overview focuses on key metrics and graphs, details
  holds metadata and security, and files plus sockets share one tab.
- Beta builds now follow beta updates by default, and Preferences can switch
  update checks back to stable.

### Changed

- Preferences are now organized into pages, so each setting is easier to find.
- ProcessLama is now green: a new accent colour and app icon tell it apart
  from the other Lama apps at a glance.
- The app icon is now rounded on Linux, Windows and macOS, matching other
  apps in the dock, taskbar and launcher.
- Mimameidr is now ProcessLama, with the Lama app icon and a small Lama at the
  foot of the sidebar that opens About. ProcessLama installs as a new app with
  its own settings; settings from Mimameidr builds are not carried over.
- The process tree no longer draws a line between every row, making it easier
  to scan without looking like a spreadsheet.
- The process details overview is shorter and easier to scan, with aligned
  summary metrics and paired Network and Storage values above their charts.
- Linux now uses native desktop window controls and keeps ProcessLama actions in
  the compact app toolbar.

### Fixed

- Fixed a macOS process refresh error during busy builds or other bursts of
  process activity. Existing remote hosts require a helper update.

- Process tree ordering stays steady while a process context menu is open and
  when hovering the tree on macOS while another app is active.
- Linux network rates are shown again when the network service is installed.
- Reduced Linux CPU usage while retaining smooth rounded window corners,
  shadows and resize edges. Distributed builds now use the optimized native
  process collector.

- Linux now picks up application names and icons for apps installed while
  ProcessLama is running.

- Website updates now load the latest design and About panel for returning visitors.

- Fixed cut-out window corners on Linux while keeping the rounded appearance.
- Reduced CPU overhead while monitoring processes, with CPU bars updating
  immediately with each sample and more reliable handling of deep or unusual
  process trees.
- A locked process tree now stays in place instead of re-sorting while
  values update.
- Storage graphs now show reads above writes. Network graphs label outbound
  traffic before inbound traffic to match the chart.
- ProcessLama now opens with a smoothly fading native macOS launch screen, and
  avoids a Flutter rendering crash that could occur after updating.
- The macOS launch screen no longer flashes the process list before appearing,
  and the app name and icon now align with the traffic lights.
- Linux process monitoring now uses less CPU, and the process table does less
  work while the window is being resized.
- The macOS window header now behaves more like a native titlebar when dragging
  or double-clicking it.
- Keyboard navigation in the process tree now keeps moving selection while you
  hold the up or down arrow.
- Hover states now cover the full process row and the full toolbar search field.
- Network history now combines inbound and outbound traffic into one graph.
- Process selection now responds immediately when clicking a row.
- Inspector metric history now uses bar charts that better show changing
  samples.
- The process-name column no longer stretches too wide on large windows.
- Search match navigation now scrolls to the selected result more reliably.
- Release DMGs now include an Applications shortcut.
- Per-process network metrics now recover automatically if macOS stops
  reporting samples.
- Snapshot export now works correctly in signed release builds.
- Command-line tools launched from app bundles now keep their own names in the
  process tree.

## [Unreleased Beta]

## [1.0.0-beta.35] - 2026-11-09

### Added

- ProcessLama is now open source under the MIT license, with public build and contribution instructions.

- Diagnostics now keep bounded recent history in memory instead of writing logs automatically. Settings lets you temporarily enable detailed diagnostics, review an export, save it, or share it where supported. Nothing is sent automatically.

## [1.0.0-beta.34] - 2026-10-29

- Upgrade Flutter to 3.47.8 to include the eMudhra certificate security fix in future builds.

## [1.0.0-beta.33] - 2026-10-28

### Changed

- The overview's port list starts collapsed again; expand it to see the ports.

## [1.0.0-beta.32] - 2026-10-27

### Added

- A sortable Ports column shows the ports each process listens on.
- Jump from a local socket to the process listening on the other end.

### Changed

- Ports are now split into listening ports and other local ports, shown as
  chips you can click to find every process using that port. Typing `:8080`
  or just `8080` in the search finds them too.

### Fixed

- Fixed a macOS process refresh error during busy builds or other bursts of
  process activity. Existing remote hosts require a helper update.

## [1.0.0-beta.31] - 2026-10-26

### Fixed

- The inspector’s Tree mode now lists ports from the selected process and all
  subprocesses, including collapsed descendants. Process mode shows only the
  selected process’s ports. The overview starts with a compact port count;
  expand it to see the full list.

## [1.0.0-beta.30] - 2026-10-26

### Added

- Find the process using a local port, choose what to search, and see a clean
  list of each process’s occupied ports in the inspector.

## [1.0.0-beta.29] - 2026-10-21

### Fixed

- Process tree ordering stays steady while a process context menu is open and
  when hovering the tree on macOS while another app is active.

## [1.0.0-beta.28] - 2026-10-15

### Changed

- Preferences are now organized into pages, and "Manage remote hosts…" opens
  the Remote hosts page directly.

### Fixed

- The portable Windows ZIP is available again.

## [1.0.0-beta.27] - 2026-10-15

### Added

- Watch Linux and macOS machines in their own tabs over SSH: click **+** in
  the new tab strip, add a host from your `~/.ssh/config`, and ProcessLama
  installs a small helper on it once you agree. Remote tabs show the same
  tree, inspector and process actions, stay readable while a connection
  drops, and reconnect on their own.
- The Linux network service is now available on its own for x86_64 and arm64
  hosts, so machines without ProcessLama can report per-process network rates.

### Fixed

- Linux network rates are shown again when the network service is installed.

## [1.0.0-beta.26] - 2026-10-05

### Fixed

- Reduced Linux CPU usage while retaining smooth rounded window corners,
  shadows and resize edges. Distributed builds now use the optimized native
  process collector.

## [1.0.0-beta.25] - 2026-10-05

### Changed

- ProcessLama is now green: a new accent colour and app icon tell it apart
  from the other Lama apps at a glance.

## [1.0.0-beta.24] - 2026-10-05

### Changed

- The app icon is now rounded on Linux, Windows and macOS, matching other
  apps in the dock, taskbar and launcher.

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

- Fixed cut-out window corners on Linux while keeping the rounded appearance.

## [1.0.0-beta.20] - 2026-09-29

### Added

- Portable Linux builds can install or repair network telemetry from the app.

### Changed

- Linux window controls now sit in the app toolbar.

### Fixed

- Missing or stopped Linux network telemetry now shows as unavailable instead
  of zero activity, with a repair action in the inspector.

## [1.0.0-beta.19] - 2026-09-28

### Fixed

- Reduced CPU overhead while monitoring processes, with CPU bars updating
  immediately with each sample and more reliable handling of deep or unusual
  process trees.

## [1.0.0-beta.18] - 2026-09-27

### Added

- Choose compact, regular, or comfortable row density in Preferences.

## [1.0.0-beta.17] - 2026-09-26

### Added

- Right-click a saved filter in the sidebar to delete it.

## [1.0.0-beta.16] - 2026-09-26

### Fixed

- Dragging the details-panel divider now tracks the pointer precisely.
- Clicking a toolbar button no longer moves keyboard focus away from the
  process tree.

## [1.0.0-beta.15] - 2026-09-26

### Added

- Hover a history chart to see the value of any sample.

### Changed

- A redesigned interface in the Devmil style: a unified toolbar, rounded
  panels for the process tree and inspector, a status bar with the live
  state and process count, and new menus, dialogs and notifications.
- Preferences now include a light, dark or system appearance setting.

### Fixed

- A locked process tree now stays in place instead of re-sorting while
  values update.

## [1.0.0-beta.14] - 2026-09-23

### Fixed

- Storage graphs now show reads above writes, and Network labels match their
  graph direction.

### Added

- Added 64-bit Windows installer and portable downloads, plus update checks on
  Windows and Linux.
- Reworked the downloads page with OS logos and clearer platform sections.

## [1.0.0-beta.13] - 2026-09-20

### Fixed

- The macOS launch screen no longer flashes the process list before appearing,
  and the app name and icon now align with the traffic lights.

## [1.0.0-beta.12] - 2026-09-20

### Changed

- The process tree no longer draws a line between every row, making it easier
  to scan without looking like a spreadsheet.

## [1.0.0-beta.11] - 2026-09-20

### Fixed

- The macOS launch screen now fades in and out, stays visible long enough to
  recognize, and avoids a Flutter rendering crash seen after updating.

## [1.0.0-beta.10] - 2026-09-20

### Added

- Process rows and the inspector now show storage read/write activity, subtree
  totals, cumulative I/O, and a combined storage history graph.
- Added Linux downloads in RPM, AppImage, DEB, and portable tar formats.
- Added native Linux process telemetry, actions, open files, thread details,
  and application names and icons.
- RPM and DEB installs now include per-process Linux network throughput, and
  the nested `systemd` branch opens automatically.

### Changed

- The process details overview is now more compact, with paired Network and
  Storage values aligned above their charts.
- Linux now uses native desktop window controls and keeps Mimameidr actions in
  the compact app toolbar.
- Linux and macOS builds now share one release tag while being published from
  their respective build machines.

### Fixed

- Mimameidr now opens without a brief black window on macOS.
- Reduced Linux monitoring CPU use and resize work.

## [1.0.0-beta.9] - 2026-08-09

### Fixed

- Network graph label overflow (again)

## [1.0.0-beta.8] - 2026-08-04

### Fixed

- Network graph label overflow
- Selected process rows now keep their lower divider for clearer separation.

## [1.0.0-beta.7] - 2026-07-08

### Added

- Exported snapshot documents can now be opened from the snapshots rail and are
  kept in the saved snapshot list.
- Saved snapshots can now be renamed, use their name when exported, and the
  snapshots rail now shows the capture date as well as the time.

### Fixed

- Snapshot export now works correctly in signed release builds.
- Command-line tools launched from app bundles now keep their own names in the
  process tree.

## [1.0.0-beta.6] - 2026-07-06

### Added

- Beta builds now follow beta updates by default, with a Preferences option for
  switching back to stable updates.

### Changed

- Preferences no longer show privacy mode or reduce motion controls before those
  behaviors are ready.

### Fixed

- The macOS window header now behaves more like a native titlebar when dragging
  or double-clicking it.
- Per-process network metrics now recover automatically if macOS stops
  reporting samples.

## [1.0.0-beta.5] - 2026-07-03

### Added

- The details panel can now be resized by dragging its divider; the width is
  remembered between launches.
- The inspector is cleaner: overview focuses on key metrics and graphs, details
  holds metadata and security, and files plus sockets share one tab.

### Fixed

- Keyboard navigation in the process tree now keeps moving selection while you
  hold the up or down arrow.
- Hover states now cover the full process row and the full toolbar search field,
  and network history now combines inbound and outbound traffic into one graph.

## [1.0.0-beta.4] - 2026-06-30

- Improve App icon handling

## [1.0.0-beta.3] - 2026-06-30

### Added

- Process rows now include terminate, force-kill, suspend, and resume actions,
  with a confirmation prompt before destructive signals are sent.
- Inspector metric graphs now show compact scale labels.
- Inspector tabs now show real macOS process details for files, sockets,
  threads, and security, with clear restricted-process hints.

### Fixed

- Search match navigation now scrolls to the selected result more reliably.
- Process tree rows now keep cell content aligned more cleanly.
- Release DMGs now include an Applications shortcut.

## [1.0.0-beta.2] - 2026-06-28

### Added

- The process explorer now uses Mimameidr's custom desktop design system with
  bundled Geist fonts, redesigned controls, live metric bars, row heat
  tinting, custom inspector tabs, and reduce-motion settings.

### Fixed

- The app icon now shows the real Mimameidr icon instead of a blue square.

## [1.0.0-beta.1] - 2026-06-23

### Added

- Initial beta release track scaffolding.
- Typing in the process tree now searches and highlights matching rows without
  hiding the rest of the tree.

### Fixed

- Process selection now responds immediately when clicking a row.
- Inspector metric history now uses bar charts that better show changing
  samples.
