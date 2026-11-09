part of '../process_explorer_screen.dart';

/// The sidebar on `ground`: pinned processes, the live system and saved
/// snapshots, and saved filters.
class _NavigationSidebar extends StatelessWidget {
  const _NavigationSidebar({
    required this.onAbout,
    required this.tree,
    required this.settings,
    required this.selectedIdentity,
    required this.savedSnapshots,
    required this.loadedSnapshotPath,
    required this.onSelected,
    required this.onFilterSelected,
    required this.onDeleteFilter,
    required this.onTakeSnapshot,
    required this.onOpenSnapshot,
    required this.onShowLive,
    required this.onLoadSnapshot,
    required this.onExportSnapshot,
    required this.onRenameSnapshot,
    required this.onDeleteSnapshot,
  });

  static const int _maxPinned = 6;
  static const int _maxSnapshots = 6;
  static const int _maxFilters = 8;

  final VoidCallback onAbout;
  final ProcessTreeView tree;
  final AppSettings settings;
  final ValueListenable<ProcessIdentity?> selectedIdentity;
  final List<SnapshotEntry> savedSnapshots;
  final String? loadedSnapshotPath;
  final ValueChanged<ProcessIdentity> onSelected;
  final ValueChanged<String> onFilterSelected;
  final ValueChanged<String> onDeleteFilter;
  final VoidCallback onTakeSnapshot;
  final VoidCallback onOpenSnapshot;
  final VoidCallback onShowLive;
  final ValueChanged<String> onLoadSnapshot;
  final ValueChanged<SnapshotEntry> onExportSnapshot;
  final ValueChanged<SnapshotEntry> onRenameSnapshot;
  final ValueChanged<SnapshotEntry> onDeleteSnapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pinnedRows = tree.visibleRows
        .where((row) => tree.pinnedIdentities.contains(row.identity))
        .toList(growable: false);
    final savedFilters = settings.savedFilters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: MeridianSpace.space3),
            children: [
              MeridianNavSection(
                title: l10n.pinned,
                children: pinnedRows.isEmpty
                    ? [_SidebarHint(l10n.pinRowsForQuickAccess)]
                    : [
                        for (final row in pinnedRows.take(_maxPinned))
                          _SelectionAwareBuilder(
                            identity: row.identity,
                            selectedIdentity: selectedIdentity,
                            builder: (context, isSelected) => MeridianNavRow(
                              label: row.record.displayName,
                              leading: _ProcessIcon(
                                name: row.record.displayName,
                                iconPath: row.iconPath,
                                iconUpdates: row.iconUpdates,
                                size: context.meridian.density.iconSmallSize,
                              ),
                              trailing: Text(
                                '${row.record.pid}',
                                style: MeridianTextStyles.numeric(
                                  context.meridian.text.codeSm,
                                ),
                              ),
                              selected: isSelected,
                              onTap: () => onSelected(row.identity),
                            ),
                          ),
                      ],
              ),
              MeridianNavSection(
                title: l10n.snapshots,
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MeridianIconButton(
                      label: l10n.openSnapshot,
                      icon: MeridianIcons.folderOpen,
                      size: MeridianControlSize.small,
                      onPressed: onOpenSnapshot,
                    ),
                    MeridianIconButton(
                      label: l10n.takeSnapshot,
                      icon: MeridianIcons.plus,
                      size: MeridianControlSize.small,
                      onPressed: onTakeSnapshot,
                    ),
                  ],
                ),
                children: [
                  MeridianNavRow(
                    label: l10n.livePlatform(tree.snapshot.platform),
                    icon: MeridianIcons.activity,
                    trailing: Text(l10n.now),
                    selected: loadedSnapshotPath == null,
                    onTap: onShowLive,
                  ),
                  for (final entry in savedSnapshots.take(_maxSnapshots))
                    MeridianNavRow(
                      label: _snapshotLabel(entry),
                      icon: MeridianIcons.history,
                      count: entry.processCount,
                      selected: loadedSnapshotPath == entry.path,
                      onTap: () => onLoadSnapshot(entry.path),
                      onContextMenu: (position) => showMeridianContextMenu(
                        context,
                        globalPosition: position,
                        entries: [
                          MeridianMenuItem(
                            label: l10n.renameSnapshot,
                            icon: MeridianIcons.pencil,
                            onSelected: () => onRenameSnapshot(entry),
                          ),
                          MeridianMenuItem(
                            label: l10n.exportSnapshot,
                            icon: MeridianIcons.download,
                            onSelected: () => onExportSnapshot(entry),
                          ),
                          const MeridianMenuDivider(),
                          MeridianMenuItem(
                            label: l10n.deleteSnapshot,
                            icon: MeridianIcons.trash2,
                            danger: true,
                            onSelected: () => onDeleteSnapshot(entry),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              MeridianNavSection(
                title: l10n.filters,
                children: savedFilters.isEmpty
                    ? [_SidebarHint(l10n.noSavedFilters)]
                    : [
                        for (final filter in savedFilters.take(_maxFilters))
                          MeridianNavRow(
                            label: filter,
                            icon: MeridianIcons.listFilter,
                            count: _matchingCount(
                              tree.snapshot.processes,
                              filter,
                            ),
                            selected:
                                tree.filter ==
                                    ProcessSearchQuery.parse(filter).text &&
                                tree.searchOptions.aspect ==
                                    ProcessSearchQuery.parse(
                                      filter,
                                    ).options.aspect,
                            onTap: () => onFilterSelected(
                              ProcessSearchQuery.parse(
                                filter,
                              ).options.savedQuery(
                                ProcessSearchQuery.parse(filter).text,
                              ),
                            ),
                            onContextMenu: (position) =>
                                showMeridianContextMenu(
                                  context,
                                  globalPosition: position,
                                  entries: [
                                    MeridianMenuItem(
                                      label: l10n.deleteFilter,
                                      icon: MeridianIcons.trash2,
                                      danger: true,
                                      onSelected: () => onDeleteFilter(filter),
                                    ),
                                  ],
                                ),
                          ),
                      ],
              ),
            ],
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              start: MeridianSpace.space3,
            ),
            child: Semantics(
              button: true,
              label: l10n.aboutApp,
              child: Tooltip(
                message: l10n.brandTooltip,
                excludeFromSemantics: true,
                child: MeridianInteraction(
                  onTap: onAbout,
                  builder: (context, state) => Container(
                    width: MeridianSize.control,
                    height: MeridianSize.control,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: state.fill(
                        rest: meridianClear(
                          context.meridian.colors.groundHover,
                        ),
                        hoverFill: context.meridian.colors.groundHover,
                        ink: context.meridian.colors.ink,
                      ),
                    ),
                    child: SvgPicture.asset(
                      'resources/brand/lama-signature.svg',
                      height: MeridianSize.icon,
                      excludeFromSemantics: true,
                      colorFilter: ColorFilter.mode(
                        state.hovered || state.focused
                            ? context.meridian.colors.inkMuted
                            : context.meridian.colors.inkFaint,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A hint in an empty sidebar section.
class _SidebarHint extends StatelessWidget {
  const _SidebarHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final meridian = context.meridian;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MeridianSpace.space4,
        vertical: MeridianSpace.space2,
      ),
      child: Text(
        text,
        style: meridian.text.caption.copyWith(color: meridian.colors.inkMuted),
      ),
    );
  }
}
