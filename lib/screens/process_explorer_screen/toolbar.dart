part of '../process_explorer_screen.dart';

/// Shows the tree's focused subtree with the way back, inside the tree
/// island above the table.
class _SubtreeFocusBar extends StatelessWidget {
  const _SubtreeFocusBar({
    required this.tree,
    required this.onBack,
    required this.onClear,
  });

  final ProcessTreeView tree;
  final VoidCallback onBack;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final meridian = context.meridian;
    final colors = meridian.colors;
    return Container(
      height: MeridianSize.islandHeader,
      padding: const EdgeInsetsDirectional.only(
        start: MeridianSpace.space5,
        end: MeridianSpace.space3,
      ),
      decoration: BoxDecoration(
        color: colors.accentSoft,
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: MeridianSurfaceScope.withFill(
        context,
        fill: colors.accentSoft,
        child: Row(
          children: [
            MeridianIcon(
              MeridianIcons.listTree,
              size: MeridianIconSize.small,
              color: colors.accentInk,
            ),
            const SizedBox(width: MeridianSpace.space4),
            Expanded(
              child: Text(
                context.l10n.focusedOnSubtree(
                  tree.focusedProcessName ?? context.l10n.subtree,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: meridian.text.bodyStrong,
              ),
            ),
            MeridianIconButton(
              label: tree.focusStack.isEmpty
                  ? context.l10n.leaveSubtreeFocus
                  : context.l10n.backOneSubtree,
              icon: tree.focusStack.isEmpty
                  ? MeridianIcons.x
                  : MeridianIcons.arrowLeft,
              size: MeridianControlSize.small,
              onPressed: tree.focusStack.isEmpty ? onClear : onBack,
            ),
            const SizedBox(width: MeridianSpace.space1),
            MeridianButton(
              label: context.l10n.showFullTree,
              icon: MeridianIcons.listTree,
              size: MeridianControlSize.small,
              variant: MeridianButtonVariant.quiet,
              onPressed: onClear,
            ),
          ],
        ),
      ),
    );
  }
}

/// The unified desktop title bar and toolbar on `ground`: the window's
/// name and source, the filter field, and the commands. On macOS it sits
/// beside the traffic lights and moves the window. Linux uses controls at the
/// right edge of the same toolbar.
class _WindowToolbar extends StatefulWidget {
  const _WindowToolbar({
    required this.appUpdateService,
    required this.processService,
    required this.settingsService,
    required this.tree,
    required this.settings,
    required this.inspectorOpen,
    required this.onToggleInspector,
    required this.onCheckForUpdates,
    required this.onTakeSnapshot,
    required this.onOpenSnapshot,
    required this.onPreferences,
    required this.onInstallNetworkTelemetry,
  });

  final AppUpdateService appUpdateService;
  final ProcessService processService;
  final SettingsService settingsService;
  final ProcessTreeView tree;
  final AppSettings settings;
  final bool inspectorOpen;
  final VoidCallback onToggleInspector;
  final VoidCallback onCheckForUpdates;
  final VoidCallback onTakeSnapshot;
  final VoidCallback onOpenSnapshot;
  final VoidCallback onPreferences;
  final VoidCallback onInstallNetworkTelemetry;

  @override
  State<_WindowToolbar> createState() => _WindowToolbarState();
}

class _WindowToolbarState extends State<_WindowToolbar> {
  /// Below this width the toolbar buttons drop their captions (the label
  /// stays the tooltip).
  static const double _labelBreakpoint = 1120;
  static const double _searchMaxWidth = 440;
  static const List<int> _pollingIntervals = [500, 1000, 2000, 5000];

  /// The macOS window uses a unified toolbar (see MainFlutterWindow.swift):
  /// the traffic lights are centred in this toolbar and end at 79 pt. The
  /// title keeps the lights' own 19 pt edge margin after them.
  static const double _macOSTrafficLightsEnd = 79;
  static const double _macOSTitleInset =
      _macOSTrafficLightsEnd + MeridianSpace.space7;

  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.processService.filter.value,
    );
    widget.processService.filter.addListener(_syncSearchController);
  }

  @override
  void dispose() {
    widget.processService.filter.removeListener(_syncSearchController);
    _searchController.dispose();
    super.dispose();
  }

  void _syncSearchController() {
    final value = widget.processService.filter.value;
    if (_searchController.text != value) {
      _searchController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final processService = widget.processService;
    final settingsService = widget.settingsService;
    final l10n = context.l10n;
    final tree = widget.tree;
    final settings = widget.settings;
    return SizedBox(
      height: MeridianSize.toolbar,
      child: Stack(
        children: [
          if (PlatformCapabilities.isDesktop)
            const Positioned.fill(
              child: DragToMoveArea(child: SizedBox.expand()),
            ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showLabels = constraints.maxWidth >= _labelBreakpoint;
                return Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: PlatformCapabilities.isMacOS
                        ? _macOSTitleInset
                        : MeridianSpace.space6,
                    end: MeridianSpace.space5,
                  ),
                  child: Row(
                    children: [
                      _WindowTitle(processService: processService, tree: tree),
                      const SizedBox(width: MeridianSpace.space7),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _searchMaxWidth,
                          ),
                          child: _FilterField(
                            controller: _searchController,
                            processService: processService,
                          ),
                        ),
                      ),
                      const SizedBox(width: MeridianSpace.space2),
                      ValueListenableBuilder<String>(
                        valueListenable: processService.filter,
                        builder: (context, filter, _) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MeridianIconButton(
                              label: l10n.saveCurrentFilter,
                              icon: MeridianIcons.bookmarkPlus,
                              onPressed: filter.isEmpty
                                  ? null
                                  : () => settingsService.addSavedFilter(
                                      processService.searchOptions.value
                                          .savedQuery(filter),
                                    ),
                            ),
                            MeridianMenuAnchor(
                              entries: [
                                for (final saved in settings.savedFilters)
                                  MeridianMenuItem(
                                    label: saved,
                                    checked:
                                        ProcessSearchQuery.parse(saved).text ==
                                            filter &&
                                        ProcessSearchQuery.parse(
                                              saved,
                                            ).options.aspect ==
                                            processService
                                                .searchOptions
                                                .value
                                                .aspect,
                                    onSelected: () {
                                      final query = ProcessSearchQuery.parse(
                                        saved,
                                      );
                                      processService.setFilter(
                                        query.options.savedQuery(query.text),
                                      );
                                    },
                                  ),
                              ],
                              builder: (context, open) => MeridianIconButton(
                                label: l10n.savedFilters,
                                icon: MeridianIcons.listFilter,
                                disabledReason: l10n.noSavedFilters,
                                onPressed: settings.savedFilters.isEmpty
                                    ? null
                                    : open,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      MeridianSelect<int>(
                        label: l10n.pollingInterval,
                        value: settings.pollingIntervalMs,
                        values: {
                          ..._pollingIntervals,
                          settings.pollingIntervalMs,
                        }.toList()..sort(),
                        valueLabel: (value) => '$value ms',
                        onChanged: settingsService.updatePollingIntervalMs,
                      ),
                      const SizedBox(width: MeridianSpace.space5),
                      MeridianToolbarButton(
                        label: l10n.toolbarLock,
                        tooltip: tree.lock.isFrozen
                            ? l10n.unlockProcessTree
                            : l10n.lockProcessTree,
                        icon: tree.lock.isFrozen
                            ? MeridianIcons.lock
                            : MeridianIcons.lockOpen,
                        selected: tree.lock.isFrozen,
                        showLabel: showLabels,
                        onPressed: processService.toggleFrozen,
                      ),
                      MeridianToolbarButton(
                        label: l10n.toolbarSnapshot,
                        tooltip: l10n.takeSnapshot,
                        icon: MeridianIcons.camera,
                        showLabel: showLabels,
                        onPressed: widget.onTakeSnapshot,
                        menuLabel: l10n.snapshotOptions,
                        menu: [
                          MeridianMenuItem(
                            label: l10n.takeSnapshot,
                            icon: MeridianIcons.camera,
                            onSelected: widget.onTakeSnapshot,
                          ),
                          MeridianMenuItem(
                            label: l10n.openSnapshot,
                            icon: MeridianIcons.folderOpen,
                            onSelected: widget.onOpenSnapshot,
                          ),
                        ],
                      ),
                      if (widget.appUpdateService.isSupported)
                        MeridianToolbarButton(
                          label: l10n.toolbarUpdates,
                          tooltip: l10n.checkForUpdates,
                          icon: MeridianIcons.download,
                          showLabel: showLabels,
                          onPressed: widget.onCheckForUpdates,
                        ),
                      MeridianToolbarButton(
                        label: l10n.inspector,
                        tooltip: widget.inspectorOpen
                            ? l10n.hideInspector
                            : l10n.showInspector,
                        icon: MeridianIcons.panelRight,
                        selected: widget.inspectorOpen,
                        showLabel: showLabels,
                        onPressed: widget.onToggleInspector,
                      ),
                      MeridianToolbarButton(
                        label: l10n.preferences,
                        icon: MeridianIcons.settings,
                        showLabel: showLabels,
                        onPressed: widget.onPreferences,
                        menuLabel: PlatformCapabilities.isLinux
                            ? l10n.morePreferencesOptions
                            : null,
                        menu: PlatformCapabilities.isLinux
                            ? [
                                MeridianMenuItem(
                                  label: l10n.installNetworkTelemetry,
                                  icon: MeridianIcons.download,
                                  onSelected: widget.onInstallNetworkTelemetry,
                                ),
                              ]
                            : null,
                      ),
                      if (PlatformCapabilities.isLinux) ...[
                        const SizedBox(width: MeridianSpace.space3),
                        MeridianIconButton(
                          label: l10n.minimizeWindow,
                          icon: MeridianIcons.minus,
                          onPressed: windowManager.minimize,
                        ),
                        MeridianIconButton(
                          label: l10n.maximizeWindow,
                          icon: MeridianIcons.square,
                          onPressed: () async {
                            if (await windowManager.isMaximized()) {
                              await windowManager.unmaximize();
                            } else {
                              await windowManager.maximize();
                            }
                          },
                        ),
                        MeridianIconButton(
                          label: l10n.closeWindow,
                          icon: MeridianIcons.x,
                          onPressed: windowManager.close,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The window's name and what it shows (the live system or a snapshot).
/// It lets clicks through so the title bar keeps moving the window.
class _WindowTitle extends StatelessWidget {
  const _WindowTitle({required this.processService, required this.tree});

  static const double _maxWidth = 180;

  final ProcessService processService;
  final ProcessTreeView tree;

  @override
  Widget build(BuildContext context) {
    final meridian = context.meridian;
    return IgnorePointer(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: ValueListenableBuilder<String?>(
          valueListenable: processService.loadedSnapshotPath,
          builder: (context, loadedPath, _) {
            final source = loadedPath == null
                ? context.l10n.livePlatform(tree.snapshot.platform)
                : _snapshotLabelFor(processService, loadedPath);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.appTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: meridian.text.bodyStrong,
                ),
                Text(
                  source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: meridian.text.caption.copyWith(
                    color: meridian.colors.inkMuted,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _snapshotLabelFor(ProcessService service, String path) {
  for (final entry in service.savedSnapshots.value) {
    if (entry.path == path) {
      return _snapshotLabel(entry);
    }
  }
  return path.split(RegExp(r'[/\\]')).last;
}

String _snapshotLabel(SnapshotEntry entry) {
  final timestamp = _formatSnapshotUnixMs(entry.generatedAtUnixMs);
  return switch (entry.name) {
    final name? when name.trim().isNotEmpty => '${name.trim()} · $timestamp',
    _ => timestamp,
  };
}

/// The process filter with its match-case and whole-word toggles.
class _FilterField extends StatelessWidget {
  const _FilterField({required this.controller, required this.processService});

  final TextEditingController controller;
  final ProcessService processService;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<ProcessSearchOptions>(
      valueListenable: processService.searchOptions,
      builder: (context, options, _) {
        return MeridianTextField(
          controller: controller,
          variant: MeridianTextFieldVariant.search,
          placeholder: switch (options.aspect) {
            ProcessSearchAspect.all => l10n.searchHint,
            ProcessSearchAspect.port => l10n.searchPortHint,
            _ => '${_searchAspectLabel(l10n, options.aspect)}…',
          },
          onChanged: processService.setFilter,
          clearLabel: l10n.clearSearch,
          trailing: _searchMenu(l10n, options),
        );
      },
    );
  }

  Widget _searchMenu(
    AppLocalizations l10n,
    ProcessSearchOptions options,
  ) => MeridianMenuAnchor(
    entries: [
      for (final aspect in ProcessSearchAspect.values)
        MeridianMenuItem(
          label: _searchAspectLabel(l10n, aspect),
          checked: options.aspect == aspect,
          onSelected: () => processService.setSearchAspect(aspect),
        ),
      if (options.aspect != ProcessSearchAspect.port) ...[
        const MeridianMenuDivider(),
        MeridianMenuItem(
          label: l10n.matchCase,
          icon: MeridianIcons.caseSensitive,
          checked: options.matchCase,
          onSelected: () =>
              processService.setSearchMatchCase(!options.matchCase),
        ),
        MeridianMenuItem(
          label: l10n.wholeWord,
          icon: MeridianIcons.wholeWord,
          checked: options.wholeWord,
          onSelected: () =>
              processService.setSearchWholeWord(!options.wholeWord),
        ),
      ],
    ],
    builder: (context, open) => MeridianIconButton(
      label:
          '${l10n.searchAspect}: ${_searchAspectLabel(l10n, options.aspect)}',
      icon: MeridianIcons.listFilter,
      active:
          options.aspect != ProcessSearchAspect.all ||
          options.matchCase ||
          options.wholeWord,
      size: MeridianControlSize.small,
      onPressed: open,
    ),
  );
}

String _searchAspectLabel(AppLocalizations l10n, ProcessSearchAspect aspect) =>
    switch (aspect) {
      ProcessSearchAspect.all => l10n.searchAll,
      ProcessSearchAspect.name => l10n.searchName,
      ProcessSearchAspect.pid => l10n.searchPid,
      ProcessSearchAspect.user => l10n.searchUser,
      ProcessSearchAspect.command => l10n.searchCommand,
      ProcessSearchAspect.path => l10n.searchPath,
      ProcessSearchAspect.port => l10n.searchPort,
    };
