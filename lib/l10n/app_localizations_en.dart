// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'ProcessLama';

  @override
  String get processExplorer => 'Process Explorer';

  @override
  String get hideInspector => 'Hide inspector';

  @override
  String get showInspector => 'Show inspector';

  @override
  String get checkForUpdates => 'Check for updates';

  @override
  String updateCheckFailed(String error) {
    return 'Update check failed: $error';
  }

  @override
  String updateUpToDate(String version, String build) {
    return 'ProcessLama $version (build $build) is up to date.';
  }

  @override
  String get updateNoPublishedRelease =>
      'No release is published for this channel yet.';

  @override
  String updateAvailableTitle(String version) {
    return 'ProcessLama $version is available';
  }

  @override
  String updateAvailableBody(
    String installedVersion,
    String installedBuild,
    String availableBuild,
  ) {
    return 'You have $installedVersion (build $installedBuild). Build $availableBuild is ready on the downloads page.';
  }

  @override
  String get later => 'Later';

  @override
  String get openDownloads => 'Open downloads';

  @override
  String get updateDownloadOpenFailed =>
      'The downloads page could not be opened.';

  @override
  String focusedOnSubtree(String name) {
    return 'Focused on $name';
  }

  @override
  String get subtree => 'subtree';

  @override
  String get leaveSubtreeFocus => 'Leave subtree focus';

  @override
  String get backOneSubtree => 'Back one subtree';

  @override
  String get showFullTree => 'Show full tree';

  @override
  String get pollingInterval => 'Polling interval';

  @override
  String get searchHint => 'Search name, PID, path, or :port';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get previousSearchMatch => 'Previous match';

  @override
  String get nextSearchMatch => 'Next match';

  @override
  String get matchCase => 'Match case';

  @override
  String get wholeWord => 'Whole word';

  @override
  String get saveCurrentFilter => 'Save current filter';

  @override
  String get savedFilters => 'Saved filters';

  @override
  String get unlockProcessTree => 'Unlock process tree';

  @override
  String get lockProcessTree => 'Lock process tree';

  @override
  String get refreshProcessSnapshot => 'Refresh process snapshot';

  @override
  String get takeSnapshot => 'Take snapshot';

  @override
  String get openSnapshot => 'Open snapshot…';

  @override
  String get preferences => 'Preferences';

  @override
  String processCount(String count) {
    return '$count processes';
  }

  @override
  String queuedCount(String count) {
    return ' - queued $count';
  }

  @override
  String get columnPid => 'PID';

  @override
  String get columnName => 'Name';

  @override
  String get columnCpu => 'CPU';

  @override
  String get columnTreeCpu => 'Tree CPU';

  @override
  String get columnGpu => 'GPU';

  @override
  String get columnTreeGpu => 'Tree GPU';

  @override
  String get columnRss => 'RSS';

  @override
  String get columnTreeRss => 'Tree RSS';

  @override
  String get columnNetIn => 'Net In';

  @override
  String get columnNetOut => 'Net Out';

  @override
  String get columnTreeNetIn => 'Tree Net In';

  @override
  String get columnTreeNetOut => 'Tree Net Out';

  @override
  String get columnStorageRead => 'Storage Read';

  @override
  String get columnStorageWrite => 'Storage Write';

  @override
  String get columnTreeStorageRead => 'Tree Storage Read';

  @override
  String get columnTreeStorageWrite => 'Tree Storage Write';

  @override
  String get columnStarted => 'Started';

  @override
  String get columnState => 'State';

  @override
  String get columnUid => 'UID';

  @override
  String get showAllColumns => 'Show all columns';

  @override
  String get resetColumnOrder => 'Reset column order';

  @override
  String get noProcessesMatchFilter => 'Nothing matches that filter.';

  @override
  String get liveOrderingPausedTooltip =>
      'Live ordering is paused while the pointer is over the tree';

  @override
  String get liveOrderingPaused => 'Live ordering paused';

  @override
  String get collapse => 'Collapse';

  @override
  String get expand => 'Expand';

  @override
  String get unpinProcess => 'Unpin process';

  @override
  String get pinProcess => 'Pin process';

  @override
  String get spawned => 'Spawned';

  @override
  String get terminated => 'Terminated';

  @override
  String get unpinProcessMenu => 'Unpin process';

  @override
  String get pinProcessMenu => 'Pin process';

  @override
  String get focusSubtree => 'Focus subtree';

  @override
  String get expandSubtree => 'Expand subtree';

  @override
  String get collapseSubtree => 'Collapse subtree';

  @override
  String get terminateProcessMenu => 'Terminate process';

  @override
  String get killProcessMenu => 'Force kill process';

  @override
  String get suspendProcessMenu => 'Suspend process';

  @override
  String get resumeProcessMenu => 'Resume process';

  @override
  String get processTerminated => 'Terminate signal sent.';

  @override
  String get processKilled => 'Kill signal sent.';

  @override
  String get processSuspended => 'Suspend signal sent.';

  @override
  String get processResumed => 'Resume signal sent.';

  @override
  String processActionFailed(String error) {
    return 'Process action failed: $error';
  }

  @override
  String get processActionConfirmCancel => 'Cancel';

  @override
  String get terminateConfirmTitle => 'Terminate process?';

  @override
  String terminateConfirmBody(String name, String pid) {
    return 'Send SIGTERM to \"$name\" (pid $pid). The process can clean up before exiting.';
  }

  @override
  String get killConfirmTitle => 'Force kill process?';

  @override
  String killConfirmBody(String name, String pid) {
    return 'Send SIGKILL to \"$name\" (pid $pid). The process is killed immediately and may leave data in an inconsistent state.';
  }

  @override
  String get suspendConfirmTitle => 'Suspend process?';

  @override
  String suspendConfirmBody(String name, String pid) {
    return 'Send SIGSTOP to \"$name\" (pid $pid). The process pauses until it is resumed.';
  }

  @override
  String copyPid(String pid) {
    return 'Copy PID $pid';
  }

  @override
  String copyName(String name) {
    return 'Copy $name';
  }

  @override
  String get copyExecutablePath => 'Copy executable path';

  @override
  String get rememberTreeExpansion => 'Remember tree expansion';

  @override
  String get rowHeatmap => 'CPU row heatmap';

  @override
  String get rowDensity => 'Row density';

  @override
  String get rowDensityCompact => 'Compact';

  @override
  String get rowDensityRegular => 'Regular';

  @override
  String get rowDensityComfortable => 'Comfortable';

  @override
  String get releaseChannel => 'Release channel';

  @override
  String get releaseChannelStable => 'Stable';

  @override
  String get releaseChannelBeta => 'Beta';

  @override
  String get system => 'System';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get close => 'Close';

  @override
  String get columns => 'Columns';

  @override
  String get moveColumnEarlier => 'Move column earlier';

  @override
  String get moveColumnLater => 'Move column later';

  @override
  String pollingIntervalLabel(String value) {
    return 'Polling interval: ${value}ms';
  }

  @override
  String get unknown => 'Unknown';

  @override
  String get inspector => 'Inspector';

  @override
  String get noProcessSelected => 'No process selected';

  @override
  String pidPlatform(String pid, String platform) {
    return 'pid $pid · $platform';
  }

  @override
  String get tabOverview => 'Overview';

  @override
  String get tabDetails => 'Details';

  @override
  String get tabFiles => 'Files';

  @override
  String get tabSockets => 'Sockets';

  @override
  String get tabFilesAndSockets => 'Files & Sockets';

  @override
  String get tabNetwork => 'Network';

  @override
  String get tabThreads => 'Threads';

  @override
  String get tabSecurity => 'Security';

  @override
  String get networkIn => 'Network In';

  @override
  String get networkOut => 'Network Out';

  @override
  String get totalIn => 'Total In';

  @override
  String get totalOut => 'Total Out';

  @override
  String get treeNetworkIn => 'Tree Network In';

  @override
  String get treeNetworkOut => 'Tree Network Out';

  @override
  String get storageRead => 'Storage Read';

  @override
  String get storageWrite => 'Storage Write';

  @override
  String get totalStorageRead => 'Total Storage Read';

  @override
  String get totalStorageWrite => 'Total Storage Write';

  @override
  String get storageHistory => 'Storage history';

  @override
  String get networkHistory => 'Network history';

  @override
  String get networkOutIn => 'Out / In';

  @override
  String get storageReadWrite => 'Read / Write';

  @override
  String get overviewMemory => 'Memory';

  @override
  String get overviewStorage => 'Storage';

  @override
  String get metricUnavailable => 'Unavailable';

  @override
  String get tree => 'Tree';

  @override
  String get processScope => 'Process';

  @override
  String get descendants => 'Descendants';

  @override
  String get parentPid => 'Parent PID';

  @override
  String get userId => 'User ID';

  @override
  String get status => 'Status';

  @override
  String get threads => 'Threads';

  @override
  String get openFiles => 'Open Files';

  @override
  String get virtualMemory => 'Virtual Memory';

  @override
  String get nice => 'Nice';

  @override
  String get priority => 'Priority';

  @override
  String get summary => 'Summary';

  @override
  String get signing => 'Signing';

  @override
  String get authority => 'Authority';

  @override
  String get teamId => 'Team ID';

  @override
  String get bundleId => 'Bundle ID';

  @override
  String get entitlements => 'Entitlements';

  @override
  String get origin => 'Origin';

  @override
  String get sandbox => 'Sandbox';

  @override
  String get hardenedRuntime => 'Hardened RT';

  @override
  String get architecture => 'Architecture';

  @override
  String get rosetta => 'Rosetta';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get noPathAvailable => '-';

  @override
  String get noOpenFilesReported => 'No open files reported for this process.';

  @override
  String get openFilesTruncated => 'Showing the first 500 open files.';

  @override
  String get noSocketsReported => 'No sockets reported for this process.';

  @override
  String get noThreadsReported => 'No threads reported for this process.';

  @override
  String get noSecurityMetadataReported =>
      'No security metadata reported for this process.';

  @override
  String restrictedByMacos(String reason) {
    return 'Restricted access: $reason';
  }

  @override
  String get gpu => 'GPU';

  @override
  String get netIn => 'Net in';

  @override
  String get netOut => 'Net out';

  @override
  String get identity => 'Identity';

  @override
  String get executable => 'Executable';

  @override
  String get applicationBundle => 'Application bundle';

  @override
  String get commandLine => 'Command line';

  @override
  String get pinned => 'Pinned';

  @override
  String get pinRowsForQuickAccess => 'Pin rows for quick access.';

  @override
  String get snapshots => 'Snapshots';

  @override
  String livePlatform(String platform) {
    return 'Live · $platform';
  }

  @override
  String get now => 'now';

  @override
  String get filters => 'Filters';

  @override
  String pollingStatus(String interval) {
    return 'Polling every $interval ms';
  }

  @override
  String exportedPath(String path) {
    return 'Exported $path';
  }

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get exportSnapshot => 'Export snapshot…';

  @override
  String get renameSnapshot => 'Rename snapshot…';

  @override
  String get renameSnapshotTitle => 'Rename snapshot';

  @override
  String get snapshotName => 'Snapshot name';

  @override
  String get deleteSnapshot => 'Delete snapshot';

  @override
  String get deleteFilter => 'Delete filter';

  @override
  String get snapshotTaken => 'Snapshot taken';

  @override
  String snapshotFailed(String error) {
    return 'Snapshot failed: $error';
  }

  @override
  String get snapshotLoaded => 'Snapshot loaded';

  @override
  String snapshotLoadFailed(String error) {
    return 'Load failed: $error';
  }

  @override
  String get snapshotDeleted => 'Snapshot deleted';

  @override
  String get snapshotRenamed => 'Snapshot renamed';

  @override
  String snapshotRenameFailed(String error) {
    return 'Rename failed: $error';
  }

  @override
  String snapshotDeleteFailed(String error) {
    return 'Delete failed: $error';
  }

  @override
  String get bootstrapErrorTitle => 'ProcessLama could not finish starting.';

  @override
  String get bootstrapErrorDescription =>
      'The app window is alive, but one of the startup services failed.';

  @override
  String get featureProcessEnumeration => 'Process enumeration';

  @override
  String get featureProcessTreeSynthesis => 'Process tree synthesis';

  @override
  String get featureFilesAndSockets => 'Files and sockets';

  @override
  String get featureNetworkThroughput => 'Network throughput';

  @override
  String get featureSecurityMetadata => 'Security metadata';

  @override
  String get featureRestrictedProcessHints => 'Restricted process hints';

  @override
  String get featureSnapshotDocuments => 'Snapshot documents';

  @override
  String get noSavedFilters => 'No saved filters.';

  @override
  String get statusTreeLocked => 'Process tree locked';

  @override
  String get toolbarLock => 'Lock';

  @override
  String get toolbarSnapshot => 'Snapshot';

  @override
  String get toolbarUpdates => 'Updates';

  @override
  String get snapshotOptions => 'More snapshot options';

  @override
  String get appearance => 'Appearance';

  @override
  String get selectProcessToInspect => 'Select a process to inspect it.';

  @override
  String get selectProcessToInspectNetwork =>
      'Select a process to inspect its network throughput.';

  @override
  String bootstrapModeMessage(String error) {
    return 'Bootstrap mode: $error';
  }

  @override
  String get sortedAscending => 'sorted ascending';

  @override
  String get sortedDescending => 'sorted descending';

  @override
  String get resizeInspector => 'Resize inspector';

  @override
  String get morePreferencesOptions => 'More preferences options';

  @override
  String get minimizeWindow => 'Minimize window';

  @override
  String get maximizeWindow => 'Maximize or restore window';

  @override
  String get closeWindow => 'Close window';

  @override
  String get installNetworkTelemetry => 'Install network telemetry…';

  @override
  String get networkTelemetryInstallDescription =>
      'Linux network activity needs a system service. Installing or repairing it requires administrator authorization and enables per-process network throughput for all users on this machine.';

  @override
  String get networkTelemetryUnavailable => 'Network telemetry unavailable';

  @override
  String get networkTelemetryUnavailableDescription =>
      'The Linux network service is missing or has stopped. Install or repair it to see live network activity.';

  @override
  String get networkTelemetryInstalled =>
      'Network service installed and started.';

  @override
  String get networkTelemetryInstallerMissing =>
      'This build does not include the network service. Install a current ProcessLama package or portable bundle.';

  @override
  String get networkTelemetryAuthorizationUnavailable =>
      'System authorization is unavailable. Install the DEB or RPM package to enable network telemetry.';

  @override
  String get networkTelemetryAuthorizationCancelled =>
      'Network service installation was cancelled.';

  @override
  String get networkTelemetryInstallFailed =>
      'Network service installation failed. Check the system journal for processlama-network.service.';

  @override
  String searchMatchPosition(String current, String count) {
    return '$current of $count matches';
  }

  @override
  String get aboutApp => 'About ProcessLama';

  @override
  String get makerLine => 'by Devmil Solutions';

  @override
  String get brandTooltip => 'ProcessLama · by Devmil Solutions';

  @override
  String get aboutProductName => 'ProcessLama';

  @override
  String aboutVersion(String version, String build) {
    return 'Version $version · build $build';
  }

  @override
  String get lamaFamily => 'The Lama family';

  @override
  String get closeAbout => 'Close';

  @override
  String get aboutLicenses => 'Licenses';

  @override
  String get filterNoMatchesHelp =>
      'Try a broader name or clear the CPU threshold.';

  @override
  String get remoteTabLocal => 'Local';

  @override
  String get remoteTabOpenMenu => 'Open remote host';

  @override
  String remoteTabClose(String tab) {
    return 'Close $tab';
  }

  @override
  String get remoteTabMoveLeft => 'Move tab left';

  @override
  String get remoteTabMoveRight => 'Move tab right';

  @override
  String get remoteTabMore => 'All tabs';

  @override
  String remoteTabTooltip(String alias, String platform, String version) {
    return '$alias · $platform · helper $version';
  }

  @override
  String remoteTabSemantics(String name, String status) {
    return '$name, $status';
  }

  @override
  String remoteTabLimit(String count) {
    return 'You can open up to $count remote tabs.';
  }

  @override
  String get remoteHostAddMenu => 'Add remote host…';

  @override
  String get remoteHostManageMenu => 'Manage remote hosts…';

  @override
  String get remoteHostMenuEmpty => 'No other saved hosts';

  @override
  String get remotePhaseIdle => 'Not connected';

  @override
  String get remotePhaseConnecting => 'Connecting';

  @override
  String get remotePhaseInstalling => 'Installing helper';

  @override
  String get remotePhaseLive => 'Connected';

  @override
  String get remotePhaseReconnecting => 'Reconnecting';

  @override
  String get remotePhaseDisconnected => 'Disconnected';

  @override
  String get remotePhaseFailed => 'Failed';

  @override
  String get remoteFailureSshMissing =>
      'OpenSSH is not installed on this computer.';

  @override
  String get remoteFailureSshTooOld =>
      'OpenSSH on this computer is older than 8.9.';

  @override
  String get remoteFailureSshConnectionFailed =>
      'SSH could not connect. Check the host, the network and your ~/.ssh/config.';

  @override
  String get remoteFailureHostKeyUntrusted =>
      'The host key is not trusted yet. Connect once with ssh in a terminal.';

  @override
  String get remoteFailureAuthenticationInteractive =>
      'SSH asks for a password or a confirmation. Set up key-based login or an agent.';

  @override
  String get remoteFailureUnsupportedPlatform =>
      'This host\'s system is not supported.';

  @override
  String get remoteFailureHelperNotInstalled =>
      'The ProcessLama helper is not installed on this host.';

  @override
  String get remoteFailureHelperOutdated =>
      'The helper on this host is outdated.';

  @override
  String get remoteFailureHelperDamaged =>
      'The helper on this host is damaged.';

  @override
  String get remoteFailureHelperStartFailed =>
      'The helper did not start. A login script may print text or read input.';

  @override
  String get remoteFailureInstallFailed => 'Installing the helper failed.';

  @override
  String get remoteFailureInstallNoSpace =>
      'The host has no space left for the helper.';

  @override
  String get remoteFailureInstallNoexec =>
      'The home directory on this host does not allow running programs (noexec).';

  @override
  String get remoteFailureInstallRefused =>
      'The install directory is unsafe: a symbolic link or a directory owned by someone else.';

  @override
  String get remoteFailureProtocolMismatch =>
      'The helper speaks a different protocol version.';

  @override
  String get remoteFailureHeartbeatLost => 'The host stopped responding.';

  @override
  String get remoteFailureFrameTooLarge =>
      'The host sent more data than allowed.';

  @override
  String get remoteFailureRemoteRestricted => 'The host denied the request.';

  @override
  String get remoteFailureCanceled => 'Canceled.';

  @override
  String get remoteFailureInternal => 'An unexpected error occurred.';

  @override
  String get remoteHostProbeSshUnreachable => 'SSH unreachable';

  @override
  String get remoteHostProbeHostKeyUntrusted => 'Host key not trusted';

  @override
  String get remoteHostProbeAuthenticationInteractive =>
      'Authentication needs interaction';

  @override
  String get remoteHostProbeUnsupportedPlatform => 'Unsupported platform';

  @override
  String get remoteHostProbeHelperMissing => 'Helper missing';

  @override
  String get remoteHostProbeHelperOutdated => 'Helper outdated';

  @override
  String remoteHostProbeReady(String platform, String version) {
    return 'Ready: $platform, helper $version';
  }

  @override
  String get remoteHostProbeRunning => 'Testing the connection…';

  @override
  String get remoteHostEditorAddTitle => 'Add remote host';

  @override
  String get remoteHostEditorEditTitle => 'Edit remote host';

  @override
  String get remoteHostDisplayName => 'Display name';

  @override
  String get remoteHostAlias => 'SSH host alias';

  @override
  String get remoteHostAliasHelp =>
      'A Host entry of your ~/.ssh/config. User names, ports, keys and jump hosts belong there; ProcessLama stores only the alias.';

  @override
  String get remoteHostAliasInvalid =>
      'Use letters, digits, dots, dashes and underscores, starting with a letter or digit.';

  @override
  String get remoteHostDisplayNameInvalid => 'Use 1 to 64 characters.';

  @override
  String get remoteHostAutoInstall => 'Install helper automatically';

  @override
  String get remoteHostAutoReconnect => 'Reconnect automatically';

  @override
  String get remoteHostOpenOnStartup => 'Open on startup';

  @override
  String get remoteHostOpenOnStartupRemember => 'As at quit';

  @override
  String get remoteHostOpenOnStartupAlways => 'Always';

  @override
  String get remoteHostOpenOnStartupNever => 'Never';

  @override
  String get remoteHostBackgroundRefresh => 'Background refresh';

  @override
  String get remoteHostBackgroundRefreshDefault => 'Default';

  @override
  String get remoteRefreshSlow => 'Slow (5 s)';

  @override
  String get remoteRefreshLive => 'Live';

  @override
  String get remoteRefreshPaused => 'Paused';

  @override
  String get remoteHostTestConnection => 'Test connection';

  @override
  String get remoteHostSetupGuide => 'Setup guide';

  @override
  String get remoteHostSave => 'Save';

  @override
  String get remoteHostCancel => 'Cancel';

  @override
  String get remoteHostSaveFailed => 'The remote host could not be saved.';

  @override
  String get remoteHostTooMany =>
      'You have reached the maximum number of remote hosts.';

  @override
  String remoteHelperInstallTitle(String host) {
    return 'Install helper on $host?';
  }

  @override
  String remoteHelperUpdateTitle(String host) {
    return 'Update helper on $host?';
  }

  @override
  String get remoteHelperInstallBody =>
      'ProcessLama copies a small helper program to this host and runs it as your SSH user. It never uses sudo.';

  @override
  String get remoteHelperInstallPath => 'Path';

  @override
  String get remoteHelperInstallVersion => 'Version';

  @override
  String get remoteHelperInstallSize => 'Size';

  @override
  String get remoteHelperInstallChecksum => 'SHA-256';

  @override
  String get remoteHelperInstallAction => 'Install';

  @override
  String get remoteHelperInstallAlways =>
      'Install and always install for this host';

  @override
  String get remoteHelperUpdateAction => 'Update';

  @override
  String get remoteHelperUpdateAlways =>
      'Update and always install for this host';

  @override
  String remoteHelperInstalled(String host) {
    return 'Helper installed on $host.';
  }

  @override
  String remoteHelperInstallFailed(String host, String reason) {
    return 'Could not install the helper on $host. $reason';
  }

  @override
  String remoteHelperInstallUnavailable(String host) {
    return 'This build of ProcessLama has no helper for $host.';
  }

  @override
  String get remoteHelperRemoveMenu => 'Remove helper from host…';

  @override
  String remoteHelperRemoveTitle(String host) {
    return 'Remove helper from $host?';
  }

  @override
  String get remoteHelperRemoveBody =>
      'ProcessLama disconnects and deletes its helper and caches under ~/.local/lib/processlama and ~/.cache/processlama on this host.';

  @override
  String get remoteHelperRemoveAction => 'Remove helper';

  @override
  String remoteHelperRemoved(String host) {
    return 'Helper removed from $host.';
  }

  @override
  String remoteHelperRemoveFailed(String host) {
    return 'Could not remove the helper from $host.';
  }

  @override
  String remoteHostConnectFailed(String host, String reason) {
    return 'Could not connect to $host. $reason';
  }

  @override
  String get remoteHostsEmpty =>
      'No remote hosts yet. Add one to watch its processes in a tab.';

  @override
  String get remoteHostAdd => 'Add remote host';

  @override
  String get remoteHostEdit => 'Edit';

  @override
  String get remoteHostConnect => 'Connect';

  @override
  String get remoteHostDisconnect => 'Disconnect';

  @override
  String get remoteHostDuplicate => 'Duplicate';

  @override
  String get remoteHostRemove => 'Remove';

  @override
  String remoteHostRemoveTitle(String host) {
    return 'Remove $host?';
  }

  @override
  String get remoteHostRemoveBody =>
      'The profile and its tab are removed. The helper stays on the host until you remove it.';

  @override
  String remoteHostActions(String host) {
    return 'Actions for $host';
  }

  @override
  String remoteHostLastSeen(String platform, String version) {
    return '$platform · helper $version';
  }

  @override
  String get remoteHostNeverConnected => 'Not connected yet';

  @override
  String get remoteHostAutoInstallOn => 'Installs the helper automatically';

  @override
  String get remoteHostsDefaultRefresh => 'Default background refresh';

  @override
  String get remoteIconCache => 'Remote icon cache';

  @override
  String remoteIconCacheUsage(String used, String limit) {
    return '$used used of $limit';
  }

  @override
  String get remoteIconCacheClear => 'Clear icon cache';

  @override
  String get remoteIconCacheCleared => 'Icon cache cleared.';

  @override
  String remoteTabConnecting(String host) {
    return 'Connecting to $host…';
  }

  @override
  String remoteTabStaleTitle(String host) {
    return '$host is not responding';
  }

  @override
  String remoteTabReconnectingTitle(String host) {
    return 'Reconnecting to $host…';
  }

  @override
  String remoteTabStaleMessage(String time, String reason) {
    return 'Showing data from $time. $reason';
  }

  @override
  String remoteTabFailedTitle(String host) {
    return 'Could not connect to $host';
  }

  @override
  String get remoteTabReconnect => 'Reconnect';

  @override
  String get remoteTabInstallHelper => 'Install helper…';

  @override
  String get remoteTabHidepid =>
      'Showing only your processes: this host hides other users\' processes.';

  @override
  String remoteStatusConnected(String host, String duration) {
    return '$host · connected $duration';
  }

  @override
  String remoteStatusLastUpdated(String host, String time) {
    return '$host · last updated $time';
  }

  @override
  String remoteStatusRefreshLive(String interval) {
    return 'refresh: live · $interval';
  }

  @override
  String remoteStatusRefreshBackground(String interval) {
    return 'background · $interval';
  }

  @override
  String get remoteStatusRefreshPaused => 'refresh: paused';

  @override
  String remoteDurationSeconds(String count) {
    return '$count s';
  }

  @override
  String remoteDurationMinutes(String count) {
    return '$count min';
  }

  @override
  String remoteDurationHours(String hours, String minutes) {
    return '$hours h $minutes min';
  }

  @override
  String remoteTerminateConfirmBody(String name, String pid, String host) {
    return 'Send SIGTERM to \"$name\" (pid $pid) on $host. The process can clean up before exiting.';
  }

  @override
  String remoteKillConfirmBody(String name, String pid, String host) {
    return 'Send SIGKILL to \"$name\" (pid $pid) on $host. The process stops immediately and cannot clean up.';
  }

  @override
  String remoteSuspendConfirmBody(String name, String pid, String host) {
    return 'Send SIGSTOP to \"$name\" (pid $pid) on $host. The process pauses until it is resumed.';
  }

  @override
  String get processSignalDenied =>
      'Not allowed: the process belongs to another user.';

  @override
  String get processSignalNotFound => 'The process has already exited.';

  @override
  String get processSignalUnknown =>
      'The signal may not have arrived. It was not sent again.';

  @override
  String get remoteCapabilityNetworkMissing =>
      'Per-process network rates need the ProcessLama network service on this host.';

  @override
  String get remoteCapabilityNetworkUnsupported =>
      'This host cannot report per-process network rates.';

  @override
  String get remoteCapabilityCopyInstallCommand => 'Copy install command';

  @override
  String get remoteCapabilityInstallCommandCopied =>
      'Install command copied. Run it on the host.';

  @override
  String get remoteHostsProfiles => 'Hosts';

  @override
  String get remoteHostConnection => 'Connection';

  @override
  String get preferencesPageAppearanceDetail =>
      'How ProcessLama looks and how tightly it packs the process rows.';

  @override
  String get preferencesPageProcessTree => 'Process tree';

  @override
  String get preferencesPageProcessTreeDetail =>
      'How often processes refresh and what the tree remembers.';

  @override
  String get preferencesPageColumnsDetail =>
      'Which columns the process tree shows, and in which order.';

  @override
  String get preferencesPageRemoteHosts => 'Remote hosts';

  @override
  String get preferencesPageRemoteHostsDetail =>
      'Computers ProcessLama reaches through your SSH configuration, how often their background tabs refresh and how many of their icons it keeps.';

  @override
  String get preferencesPageUpdates => 'Updates';

  @override
  String get preferencesPageUpdatesDetail =>
      'Which ProcessLama builds the updater offers you.';

  @override
  String get preferencesTheme => 'Theme';

  @override
  String get searchAspect => 'Search aspect';

  @override
  String get searchAll => 'Process text';

  @override
  String get searchName => 'Process name';

  @override
  String get searchPid => 'Process ID';

  @override
  String get searchUser => 'User';

  @override
  String get searchCommand => 'Command line';

  @override
  String get searchPath => 'Executable path';

  @override
  String get searchPort => 'Local port';

  @override
  String get searchPortHint => 'Local port (e.g. 8080)';

  @override
  String get occupiedPorts => 'Occupied ports';

  @override
  String get localPorts => 'Local TCP / UDP ports';

  @override
  String get portsNotReported =>
      'No ports reported (none or access restricted)';

  @override
  String get noOccupiedPorts => 'No occupied ports';

  @override
  String get localPortsExplanation =>
      'Listening ports accept connections: TCP listeners and UDP sockets on well-known ports (below 1024). Other local ports are mostly outgoing connections. Select a port to show every process using it. Permissions may hide ports owned by other users.';

  @override
  String get listeningPorts => 'Listening';

  @override
  String get listeningPortsLabel => 'Listening ports';

  @override
  String get otherLocalPorts => 'Other local ports';

  @override
  String showPortProcesses(int port) {
    return 'Show processes using port $port';
  }

  @override
  String goToPortOwner(String name, int pid) {
    return '$name ($pid)';
  }

  @override
  String goToPortOwnerLabel(String name, int pid, int port) {
    return 'Go to $name, PID $pid, listening on port $port';
  }

  @override
  String get columnPorts => 'Ports';

  @override
  String get socketPeers => 'Local processes these sockets connect to';

  @override
  String get diagnosticsTitle => 'Diagnostics';

  @override
  String get diagnosticsDescription =>
      'Recent safe events stay in memory only (up to 1,000 events or 256 KiB). Detailed capture lasts up to 15 minutes or until the session ends. No credentials or private content are included. Preview before saving or sharing. Nothing is uploaded automatically. Clear history does not remove copies you saved or shared.';

  @override
  String get diagnosticsEnable => 'Enable detailed diagnostics for 15 minutes';

  @override
  String get diagnosticsDisable =>
      'Detailed diagnostics active — stop recording details';

  @override
  String get diagnosticsClear => 'Clear history';

  @override
  String get diagnosticsPreview => 'Preview export';

  @override
  String get diagnosticsCancel => 'Close preview';

  @override
  String get diagnosticsSave => 'Save to file';

  @override
  String get diagnosticsShare => 'Share…';

  @override
  String get diagnosticsFailed =>
      'Could not export diagnostics. Try another destination.';

  @override
  String get diagnosticsSaved => 'Diagnostics saved.';
}
