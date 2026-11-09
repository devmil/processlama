import 'package:devmil_logging/devmil_logging.dart';
import '../widgets/diagnostic_settings.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:provider/provider.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../app/app_theme_data.dart';
import '../app/platform_capabilities.dart';
import '../l10n/l10n.dart';
import '../models/models.dart';
import '../services/services.dart';
import 'workspace_tabs/remote_host_dialogs.dart';
import 'workspace_tabs/remote_host_labels.dart';
import 'workspace_tabs/remote_hosts_settings_section.dart';
import 'workspace_tabs/remote_tab_banner.dart';
import 'workspace_tabs/workspace_tab_strip.dart';

part 'process_explorer_screen/about_dialog.dart';
part 'process_explorer_screen/column_definitions.dart';
part 'process_explorer_screen/inspector.dart';
part 'process_explorer_screen/navigation_rail.dart';
part 'process_explorer_screen/preferences_dialog.dart';
part 'process_explorer_screen/process_tree_table.dart';
part 'process_explorer_screen/process_tree_tile.dart';
part 'process_explorer_screen/sparkline.dart';
part 'process_explorer_screen/status_bar.dart';
part 'process_explorer_screen/toolbar.dart';

class ProcessExplorerScreen extends StatefulWidget {
  const ProcessExplorerScreen({super.key});

  @override
  State<ProcessExplorerScreen> createState() => _ProcessExplorerScreenState();
}

class _ProcessExplorerScreenState extends State<ProcessExplorerScreen>
    with WindowListener {
  static const _resizeEndDelay = Duration(milliseconds: 200);

  bool _inspectorOpen = true;
  int _treeSearchRequestSerial = 0;
  Timer? _resizeEndTimer;
  Timer? _networkAvailabilityTimer;
  bool _windowResizeActive = false;
  bool _linuxNetworkAvailable = true;
  final _tabStrip = GlobalKey<WorkspaceTabStripState>();

  @override
  void initState() {
    super.initState();
    if (PlatformCapabilities.isDesktop) {
      windowManager.addListener(this);
    }
    if (PlatformCapabilities.isLinux) {
      unawaited(_refreshNetworkAvailability());
      _networkAvailabilityTimer = Timer.periodic(
        LinuxNetworkSetupService.availabilityPollInterval,
        (_) => unawaited(_refreshNetworkAvailability()),
      );
    }
  }

  @override
  void dispose() {
    _resizeEndTimer?.cancel();
    _networkAvailabilityTimer?.cancel();
    if (_windowResizeActive) {
      context.read<ProcessService>().setWindowResizing(false);
    }
    if (PlatformCapabilities.isDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowResize() {
    if (!mounted) {
      return;
    }
    _resizeEndTimer?.cancel();
    if (!_windowResizeActive) {
      _windowResizeActive = true;
      context.read<ProcessService>().setWindowResizing(true);
    }
    _resizeEndTimer = Timer(_resizeEndDelay, _finishWindowResize);
  }

  @override
  void onWindowResized() {
    _finishWindowResize();
  }

  void _finishWindowResize() {
    _resizeEndTimer?.cancel();
    _resizeEndTimer = null;
    if (!mounted || !_windowResizeActive) {
      return;
    }
    _windowResizeActive = false;
    final processService = context.read<ProcessService>();
    processService.setWindowResizing(false);
    unawaited(processService.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final processService = context.read<ProcessService>();
    final settingsService = context.read<SettingsService>();
    final appUpdateService = context.read<AppUpdateService>();

    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final tabs = context.read<WorkspaceTabsService>();
    SingleActivator command(LogicalKeyboardKey key, {bool shift = false}) =>
        SingleActivator(key, meta: isMac, control: !isMac, shift: shift);
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    return CallbackShortcuts(
      bindings: {
        command(LogicalKeyboardKey.keyF): _requestTreeSearch,
        command(LogicalKeyboardKey.keyT): () =>
            _tabStrip.currentState?.openMenu(),
        for (final (index, digit) in digits.indexed)
          command(digit): () => tabs.activateIndex(index),
        command(LogicalKeyboardKey.bracketLeft, shift: true): () =>
            tabs.cycle(backwards: true),
        command(LogicalKeyboardKey.bracketRight, shift: true): tabs.cycle,
      },
      child: MeridianGround(
        child: ValueListenableBuilder<AppSettings>(
          valueListenable: settingsService.settings,
          builder: (context, settings, _) {
            return ValueListenableBuilder<ProcessTreeView>(
              valueListenable: processService.tree,
              builder: (context, tree, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WindowToolbar(
                      appUpdateService: appUpdateService,
                      processService: processService,
                      settingsService: settingsService,
                      tree: tree,
                      settings: settings,
                      inspectorOpen: _inspectorOpen,
                      onToggleInspector: _toggleInspector,
                      onCheckForUpdates: () =>
                          _checkForUpdates(appUpdateService),
                      onTakeSnapshot: () => _takeSnapshot(processService),
                      onOpenSnapshot: () => _openSnapshot(processService),
                      onPreferences: () =>
                          _showPreferences(processService, settingsService),
                      onInstallNetworkTelemetry: _installNetworkTelemetry,
                    ),
                    WorkspaceTabStrip(
                      key: _tabStrip,
                      onManageRemoteHosts: () => _showPreferences(
                        processService,
                        settingsService,
                        page: _PreferencesPage.remoteHosts,
                      ),
                    ),
                    const RemoteTabBanner(),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: MeridianSpace.space3,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: _sidebarWidth,
                              child: _buildSidebar(
                                processService,
                                settingsService,
                                tree,
                                settings,
                              ),
                            ),
                            const SizedBox(width: MeridianSpace.space3),
                            Expanded(
                              child: _buildTreeIsland(
                                processService,
                                settingsService,
                                tree,
                                settings,
                              ),
                            ),
                            if (_inspectorOpen)
                              MeridianResizeHandle(
                                semanticLabel: context.l10n.resizeInspector,
                                // The inspector is the right island: dragging
                                // left widens it.
                                onDrag: (delta) =>
                                    settingsService.updateInspectorWidth(
                                      settings.inspectorWidth - delta,
                                    ),
                                onReset: () =>
                                    settingsService.updateInspectorWidth(
                                      AppSettings.defaultInspectorWidth,
                                    ),
                              ),
                            _buildInspector(processService, tree, settings),
                          ],
                        ),
                      ),
                    ),
                    _ExplorerStatusBar(tree: tree, settings: settings),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  static const double _sidebarWidth = 216;

  Widget _buildSidebar(
    ProcessService processService,
    SettingsService settingsService,
    ProcessTreeView tree,
    AppSettings settings,
  ) {
    return ValueListenableBuilder<List<SnapshotEntry>>(
      valueListenable: processService.savedSnapshots,
      builder: (context, savedSnapshots, _) {
        return ValueListenableBuilder<String?>(
          valueListenable: processService.loadedSnapshotPath,
          builder: (context, loadedSnapshotPath, _) {
            return _NavigationSidebar(
              tree: tree,
              settings: settings,
              selectedIdentity: processService.selectedIdentity,
              savedSnapshots: savedSnapshots,
              loadedSnapshotPath: loadedSnapshotPath,
              onAbout: () => _showAbout(processService),
              onSelected: processService.selectProcess,
              onFilterSelected: processService.setFilter,
              onDeleteFilter: settingsService.removeSavedFilter,
              onTakeSnapshot: () => _takeSnapshot(processService),
              onOpenSnapshot: () => _openSnapshot(processService),
              onShowLive: processService.showLiveSnapshot,
              onLoadSnapshot: (path) => _loadSnapshot(processService, path),
              onExportSnapshot: (entry) =>
                  _exportSnapshot(processService, entry),
              onRenameSnapshot: (entry) =>
                  _renameSnapshot(processService, entry),
              onDeleteSnapshot: (entry) =>
                  _deleteSnapshot(processService, entry),
            );
          },
        );
      },
    );
  }

  Widget _buildTreeIsland(
    ProcessService processService,
    SettingsService settingsService,
    ProcessTreeView tree,
    AppSettings settings,
  ) {
    return MeridianIsland(
      expandChild: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tree.isSubtreeFocused)
            _SubtreeFocusBar(
              tree: tree,
              onBack: processService.popSubtreeFocus,
              onClear: processService.clearSubtreeFocus,
            ),
          Expanded(
            child: _ProcessTreeTable(
              tree: tree,
              settings: settings,
              selectedIdentity: processService.selectedIdentity,
              treeSearchRequestSerial: _treeSearchRequestSerial,
              onSelected: processService.selectProcess,
              onSelectNext: processService.selectNextVisible,
              onSelectPrevious: processService.selectPreviousVisible,
              onExpandSelected: processService.expandSelected,
              onCollapseSelected: processService.collapseSelected,
              onExpandSelectedSubtree: processService.expandSelectedSubtree,
              onCollapseSelectedSubtree: processService.collapseSelectedSubtree,
              onFocusSelectedSubtree: processService.focusSelectedSubtree,
              onPopSubtreeFocus: processService.popSubtreeFocus,
              onTreeSearchChanged: processService.setTreeSearch,
              onSelectNextTreeSearchMatch:
                  processService.selectNextTreeSearchMatch,
              onSelectPreviousTreeSearchMatch:
                  processService.selectPreviousTreeSearchMatch,
              onToggleExpanded: processService.toggleExpansion,
              onSort: processService.sortBy,
              onTogglePin: processService.togglePin,
              onFocusSubtree: processService.focusSubtree,
              onTerminateProcess: (identity) =>
                  _terminateProcess(processService, identity),
              onKillProcess: (identity) =>
                  _killProcess(processService, identity),
              onSuspendProcess: (identity) =>
                  _suspendProcess(processService, identity),
              onResumeProcess: (identity) =>
                  _resumeProcess(processService, identity),
              onExpandSubtree: (_) => processService.expandSelectedSubtree(),
              onCollapseSubtree: (_) =>
                  processService.collapseSelectedSubtree(),
              onTreeHoverChanged: processService.setTreeHovering,
              onTreeContextMenuChanged: processService.setTreeContextMenuOpen,
              onTreeInteraction: processService.markTreeInteraction,
              onVisibleColumnsChanged: settingsService.updateVisibleColumns,
              onColumnWidthsChanged: settingsService.updateColumnWidths,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInspector(
    ProcessService processService,
    ProcessTreeView tree,
    AppSettings settings,
  ) {
    final duration = MeridianMotion.of(context, MeridianDurations.emphasized);
    return ClipRect(
      clipper: const _IslandShadowClipper(),
      child: AnimatedContainer(
        duration: duration,
        curve: MeridianDurations.emphasizedCurve,
        width: _inspectorOpen ? settings.inspectorWidth : 0,
        child: AnimatedOpacity(
          opacity: _inspectorOpen ? 1 : 0,
          duration: duration,
          child: OverflowBox(
            alignment: AlignmentDirectional.centerStart,
            minWidth: settings.inspectorWidth,
            maxWidth: settings.inspectorWidth,
            child: ValueListenableBuilder<HostCapabilities>(
              valueListenable: processService.hostCapabilities,
              builder: (context, capabilities, _) =>
                  ValueListenableBuilder<ProcessInspectorView>(
                    valueListenable: processService.inspector,
                    builder: (context, inspector, _) {
                      final remote = processService.sourceDescriptor;
                      final live =
                          processService.loadedSnapshotPath.value == null;
                      return _Inspector(
                        tree: tree,
                        inspector: inspector,
                        settings: settings,
                        networkUnavailable:
                            live &&
                            (remote is RemoteProcessSourceDescriptor
                                ? capabilities.networkSource ==
                                      NetworkRateSource.none
                                : PlatformCapabilities.isLinux &&
                                      !_linuxNetworkAvailable),
                        onInstallNetworkTelemetry: _installNetworkTelemetry,
                        onShowPort: processService.showPort,
                        onSelectProcess: processService.selectProcess,
                        networkHint: remote is RemoteProcessSourceDescriptor
                            ? _remoteNetworkHint(remote.profileId, capabilities)
                            : null,
                      );
                    },
                  ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showPreferences(
    ProcessService processService,
    SettingsService settingsService, {
    _PreferencesPage page = _PreferencesPage.appearance,
  }) async {
    processService.setModalOverlayOpen(true);
    try {
      await showMeridianDialog<void>(
        context: context,
        builder: (_) =>
            _PreferencesDialog(service: settingsService, initialPage: page),
      );
    } finally {
      processService.setModalOverlayOpen(false);
    }
  }

  void _requestTreeSearch() {
    setState(() => _treeSearchRequestSerial++);
  }

  void _toggleInspector() {
    setState(() => _inspectorOpen = !_inspectorOpen);
  }

  void _toast(
    String message, {
    MeridianToastTone tone = MeridianToastTone.neutral,
  }) {
    if (!mounted) {
      return;
    }
    showMeridianToast(context, message: message, tone: tone);
  }

  void _failure(String message) =>
      _toast(message, tone: MeridianToastTone.error);

  Future<void> _refreshNetworkAvailability() async {
    final available = await context
        .read<LinuxNetworkSetupService>()
        .isAvailable();
    if (mounted && available != _linuxNetworkAvailable) {
      setState(() => _linuxNetworkAvailable = available);
    }
  }

  /// The network banner of a remote tab (§9.3): copy the install command of
  /// the network service package, or read the setup guide.
  _NetworkHint _remoteNetworkHint(
    String profileId,
    HostCapabilities capabilities,
  ) {
    final l10n = context.l10n;
    final installable =
        capabilities.networkUnavailableReason ==
        NetworkUnavailableReason.serviceNotInstalled;
    return _NetworkHint(
      title: l10n.networkTelemetryUnavailable,
      message: installable
          ? l10n.remoteCapabilityNetworkMissing
          : l10n.remoteCapabilityNetworkUnsupported,
      actionLabel: l10n.remoteCapabilityCopyInstallCommand,
      onAction: installable
          ? () => unawaited(_copyNetworkInstallCommand(profileId))
          : null,
      onGuide: () => unawaited(openRemoteHostsSetupGuide()),
    );
  }

  Future<void> _copyNetworkInstallCommand(String profileId) async {
    final l10n = context.l10n;
    final target = context
        .read<RemoteHostService>()
        .connectionState(profileId)
        .value
        .hello
        ?.facts
        .target;
    final installed = await context
        .read<AppUpdateService>()
        .loadInstalledVersion();
    final command = target == null
        ? null
        : networkServiceInstallCommand(
            version: installed.version,
            build: installed.build,
            target: target,
          );
    if (command == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: command));
    _toast(
      l10n.remoteCapabilityInstallCommandCopied,
      tone: MeridianToastTone.success,
    );
  }

  Future<void> _installNetworkTelemetry() async {
    final l10n = context.l10n;
    final confirmed = await showMeridianDialog<bool>(
      context: context,
      builder: (dialogContext) => MeridianDialog(
        title: l10n.installNetworkTelemetry,
        description: l10n.networkTelemetryInstallDescription,
        actions: [
          MeridianButton(
            label: l10n.later,
            variant: MeridianButtonVariant.quiet,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          MeridianButton(
            label: l10n.installNetworkTelemetry,
            variant: MeridianButtonVariant.primary,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<LinuxNetworkSetupService>().installOrRepair();
      if (!mounted) return;
      _toast(l10n.networkTelemetryInstalled, tone: MeridianToastTone.success);
      await _refreshNetworkAvailability();
    } on LinuxNetworkSetupException catch (error) {
      if (!mounted) return;
      _failure(switch (error.code) {
        'installerMissing' => l10n.networkTelemetryInstallerMissing,
        'authorizationUnavailable' =>
          l10n.networkTelemetryAuthorizationUnavailable,
        'authorizationCancelled' => l10n.networkTelemetryAuthorizationCancelled,
        _ => l10n.networkTelemetryInstallFailed,
      });
    }
  }

  Future<void> _takeSnapshot(ProcessService service) async {
    final l10n = context.l10n;
    try {
      await service.takeSnapshot();
      _toast(l10n.snapshotTaken, tone: MeridianToastTone.success);
    } on Object catch (error) {
      _failure(l10n.snapshotFailed('$error'));
    }
  }

  Future<void> _loadSnapshot(ProcessService service, String path) async {
    final l10n = context.l10n;
    try {
      await service.loadSnapshot(path);
      _toast(l10n.snapshotLoaded);
    } on Object catch (error) {
      _failure(l10n.snapshotLoadFailed('$error'));
    }
  }

  Future<void> _openSnapshot(ProcessService service) async {
    final l10n = context.l10n;
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: l10n.openSnapshot,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final files = result?.files;
      final path = files == null || files.isEmpty ? null : files.single.path;
      if (path == null) {
        return;
      }
      await service.loadSnapshot(path);
      _toast(l10n.snapshotLoaded);
    } on Object catch (error) {
      _failure(l10n.snapshotLoadFailed('$error'));
    }
  }

  Future<void> _exportSnapshot(
    ProcessService service,
    SnapshotEntry entry,
  ) async {
    final l10n = context.l10n;
    try {
      final result = await FilePicker.saveFile(
        dialogTitle: l10n.exportSnapshot,
        fileName: _snapshotExportFileName(entry),
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null) {
        return;
      }
      await service.exportSnapshot(entry, result);
      _toast(l10n.exportedPath(result), tone: MeridianToastTone.success);
    } on Object catch (error) {
      _failure(l10n.exportFailed('$error'));
    }
  }

  Future<void> _renameSnapshot(
    ProcessService service,
    SnapshotEntry entry,
  ) async {
    final l10n = context.l10n;
    final controller = TextEditingController(text: entry.name ?? '');
    service.setModalOverlayOpen(true);
    try {
      final name = await showMeridianDialog<String>(
        context: context,
        builder: (dialogContext) {
          void submit() =>
              Navigator.of(dialogContext).pop(controller.text.trim());
          return MeridianDialog(
            title: l10n.renameSnapshotTitle,
            onSubmit: submit,
            content: MeridianTextField(
              controller: controller,
              label: l10n.snapshotName,
              autofocus: true,
              onSubmitted: (_) => submit(),
            ),
            actions: [
              MeridianButton(
                label: l10n.processActionConfirmCancel,
                variant: MeridianButtonVariant.quiet,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              MeridianButton(
                label: l10n.renameSnapshotTitle,
                variant: MeridianButtonVariant.primary,
                onPressed: submit,
              ),
            ],
          );
        },
      );
      if (name == null || name.isEmpty) {
        return;
      }
      await service.renameSnapshot(entry, name);
      _toast(l10n.snapshotRenamed, tone: MeridianToastTone.success);
    } on Object catch (error) {
      _failure(l10n.snapshotRenameFailed('$error'));
    } finally {
      controller.dispose();
      service.setModalOverlayOpen(false);
    }
  }

  Future<void> _deleteSnapshot(
    ProcessService service,
    SnapshotEntry entry,
  ) async {
    final l10n = context.l10n;
    try {
      await service.deleteSnapshot(entry);
      _toast(l10n.snapshotDeleted);
    } on Object catch (error) {
      _failure(l10n.snapshotDeleteFailed('$error'));
    }
  }

  Future<void> _checkForUpdates(AppUpdateService service) async {
    final l10n = context.l10n;
    try {
      final result = await service.checkForUpdates();
      if (!mounted ||
          result.status == AppUpdateCheckStatus.nativeCheckerOpened) {
        return;
      }
      switch (result.status) {
        case AppUpdateCheckStatus.upToDate:
          _toast(
            l10n.updateUpToDate(
              result.installedVersion,
              '${result.installedBuild}',
            ),
            tone: MeridianToastTone.success,
          );
        case AppUpdateCheckStatus.noPublishedRelease:
          _toast(l10n.updateNoPublishedRelease);
        case AppUpdateCheckStatus.updateAvailable:
          await showMeridianDialog<void>(
            context: context,
            builder: (dialogContext) => MeridianDialog(
              title: l10n.updateAvailableTitle(result.availableVersion ?? ''),
              description: l10n.updateAvailableBody(
                result.installedVersion,
                '${result.installedBuild}',
                '${result.availableBuild ?? ''}',
              ),
              actions: [
                MeridianButton(
                  label: l10n.later,
                  variant: MeridianButtonVariant.quiet,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                MeridianButton(
                  label: l10n.openDownloads,
                  variant: MeridianButtonVariant.primary,
                  icon: MeridianIcons.externalLink,
                  autofocus: true,
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    final opened = await launchUrl(
                      Uri.parse('https://devmil.de/processlama/releases.html'),
                    );
                    if (!opened) {
                      _failure(l10n.updateDownloadOpenFailed);
                    }
                  },
                ),
              ],
            ),
          );
        case AppUpdateCheckStatus.nativeCheckerOpened:
          break;
      }
    } on Object catch (error) {
      _failure(l10n.updateCheckFailed('$error'));
    }
  }

  Future<void> _terminateProcess(
    ProcessService service,
    ProcessIdentity identity,
  ) async {
    final l10n = context.l10n;
    if (!await _confirmProcessAction(
      service,
      identity: identity,
      action: _DestructiveProcessAction.terminate,
    )) {
      return;
    }
    try {
      await service.terminateProcess(identity);
      _toast(l10n.processTerminated, tone: MeridianToastTone.success);
    } on Object catch (error) {
      _failure(_processActionFailure(error));
    }
  }

  Future<void> _killProcess(
    ProcessService service,
    ProcessIdentity identity,
  ) async {
    final l10n = context.l10n;
    if (!await _confirmProcessAction(
      service,
      identity: identity,
      action: _DestructiveProcessAction.kill,
    )) {
      return;
    }
    try {
      await service.killProcess(identity);
      _toast(l10n.processKilled, tone: MeridianToastTone.success);
    } on Object catch (error) {
      _failure(_processActionFailure(error));
    }
  }

  Future<void> _suspendProcess(
    ProcessService service,
    ProcessIdentity identity,
  ) async {
    final l10n = context.l10n;
    if (!await _confirmProcessAction(
      service,
      identity: identity,
      action: _DestructiveProcessAction.suspend,
    )) {
      return;
    }
    try {
      await service.suspendProcess(identity);
      _toast(l10n.processSuspended, tone: MeridianToastTone.success);
    } on Object catch (error) {
      _failure(_processActionFailure(error));
    }
  }

  Future<void> _resumeProcess(
    ProcessService service,
    ProcessIdentity identity,
  ) async {
    final l10n = context.l10n;
    try {
      await service.resumeProcess(identity);
      _toast(l10n.processResumed, tone: MeridianToastTone.success);
    } on Object catch (error) {
      _failure(_processActionFailure(error));
    }
  }

  /// The typed outcome of a signal, or the error.
  String _processActionFailure(Object error) {
    final l10n = context.l10n;
    return switch (error) {
      ProcessSignalException(outcome: SignalOutcome.denied) =>
        l10n.processSignalDenied,
      ProcessSignalException(outcome: SignalOutcome.notFound) =>
        l10n.processSignalNotFound,
      ProcessSignalException(outcome: SignalOutcome.unknown) =>
        l10n.processSignalUnknown,
      _ => l10n.processActionFailed('$error'),
    };
  }

  Future<bool> _confirmProcessAction(
    ProcessService service, {
    required ProcessIdentity identity,
    required _DestructiveProcessAction action,
  }) async {
    final l10n = context.l10n;
    final name = _resolveProcessName(service, identity);
    final pid = identity.pid.toString();
    // On a remote tab the confirmation names the host.
    final host = switch (service.sourceDescriptor) {
      RemoteProcessSourceDescriptor(:final profileId) => remoteHostName(
        context,
        profileId,
      ),
      LocalProcessSourceDescriptor() => null,
    };
    final (title, body, confirmLabel, destructive) = switch (action) {
      _DestructiveProcessAction.terminate => (
        l10n.terminateConfirmTitle,
        host == null
            ? l10n.terminateConfirmBody(name, pid)
            : l10n.remoteTerminateConfirmBody(name, pid, host),
        l10n.terminateProcessMenu,
        false,
      ),
      _DestructiveProcessAction.kill => (
        l10n.killConfirmTitle,
        host == null
            ? l10n.killConfirmBody(name, pid)
            : l10n.remoteKillConfirmBody(name, pid, host),
        l10n.killProcessMenu,
        true,
      ),
      _DestructiveProcessAction.suspend => (
        l10n.suspendConfirmTitle,
        host == null
            ? l10n.suspendConfirmBody(name, pid)
            : l10n.remoteSuspendConfirmBody(name, pid, host),
        l10n.suspendProcessMenu,
        false,
      ),
    };

    service.setModalOverlayOpen(true);
    try {
      return await showMeridianConfirm(
        context,
        title: title,
        description: body,
        confirmLabel: confirmLabel,
        cancelLabel: l10n.processActionConfirmCancel,
        destructive: destructive,
      );
    } finally {
      service.setModalOverlayOpen(false);
    }
  }

  String _resolveProcessName(ProcessService service, ProcessIdentity identity) {
    final rows = service.tree.value.visibleRows;
    for (final row in rows) {
      if (row.identity == identity) {
        return row.record.name;
      }
    }
    final processes = service.snapshot.value.processes;
    for (final process in processes) {
      if (process.identity == identity) {
        return process.name;
      }
    }
    return identity.pid.toString();
  }
}

/// Clips the sliding inspector to its animated width while leaving room
/// for the island's `shadow-pane` edge.
class _IslandShadowClipper extends CustomClipper<Rect> {
  const _IslandShadowClipper();

  @override
  Rect getClip(Size size) => (Offset.zero & size).inflate(MeridianSpace.space2);

  @override
  bool shouldReclip(covariant _IslandShadowClipper oldClipper) => false;
}

enum _DestructiveProcessAction { terminate, kill, suspend }

String _formatBytes(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }

  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }

  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

String _formatRate(double bytesPerSecond) {
  return '${_formatBytes(bytesPerSecond.round())}/s';
}

/// Listening ports, then how many other local ports: `8080, 5432 +12`.
String _formatPortsCell(ProcessRecord process) {
  final ports = ProcessPorts.ofRecord(process);
  if (ports == null) return '-';
  return [
    if (ports.listening.isNotEmpty) ports.listening.join(', '),
    if (ports.other.isNotEmpty) '+${ports.other.length}',
  ].join(' ');
}

String _formatUnixMs(int unixMs) {
  if (unixMs <= 0) {
    return 'Unknown';
  }
  final dateTime = DateTime.fromMillisecondsSinceEpoch(unixMs);
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final second = dateTime.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

String _formatSnapshotUnixMs(int unixMs) {
  if (unixMs <= 0) {
    return 'Unknown';
  }
  final dateTime = DateTime.fromMillisecondsSinceEpoch(unixMs);
  final year = dateTime.year.toString().padLeft(4, '0');
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}

String _snapshotExportFileName(SnapshotEntry entry) {
  final baseName = _sanitizeSnapshotFileName(entry.name);
  final fallback = 'snapshot-${entry.generatedAtUnixMs}';
  return '${baseName.isEmpty ? fallback : baseName}.processlama-snapshot.json';
}

String _sanitizeSnapshotFileName(String? name) {
  final trimmed = name
      ?.trim()
      .replaceAll(
        RegExp(r'\.processlama-snapshot\.json$', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'\.json$', caseSensitive: false), '');
  if (trimmed == null || trimmed.isEmpty) {
    return '';
  }
  return trimmed
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'-+'), '-')
      .trim();
}

String _formatPercent(double value) {
  if (value <= 0) {
    return '0.0%';
  }
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)}%';
}
