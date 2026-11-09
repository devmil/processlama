part of '../process_explorer_screen.dart';

class _SelectionAwareBuilder extends StatefulWidget {
  const _SelectionAwareBuilder({
    required this.identity,
    required this.selectedIdentity,
    required this.builder,
  });

  final ProcessIdentity identity;
  final ValueListenable<ProcessIdentity?> selectedIdentity;
  final Widget Function(BuildContext context, bool isSelected) builder;

  @override
  State<_SelectionAwareBuilder> createState() => _SelectionAwareBuilderState();
}

class _SelectionAwareBuilderState extends State<_SelectionAwareBuilder> {
  late bool _isSelected;

  @override
  void initState() {
    super.initState();
    _isSelected = _computeIsSelected();
    widget.selectedIdentity.addListener(_handleSelectedIdentityChanged);
  }

  @override
  void didUpdateWidget(covariant _SelectionAwareBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIdentity != widget.selectedIdentity) {
      oldWidget.selectedIdentity.removeListener(_handleSelectedIdentityChanged);
      widget.selectedIdentity.addListener(_handleSelectedIdentityChanged);
    }
    final next = _computeIsSelected();
    if (next != _isSelected) {
      _isSelected = next;
    }
  }

  @override
  void dispose() {
    widget.selectedIdentity.removeListener(_handleSelectedIdentityChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _isSelected);

  bool _computeIsSelected() {
    return widget.selectedIdentity.value == widget.identity;
  }

  void _handleSelectedIdentityChanged() {
    final next = _computeIsSelected();
    if (next == _isSelected) {
      return;
    }
    setState(() => _isSelected = next);
  }
}

/// One cell of a process row. The row's fill is painted by the table (an
/// inset rounded bar); the cell draws its content in [rowColors].
class _ProcessCell extends StatelessWidget {
  const _ProcessCell({
    required this.column,
    required this.row,
    required this.cpuScaleMax,
    required this.rowColors,
    required this.isSelected,
    required this.isHovered,
    required this.isPinned,
    required this.onToggleExpanded,
    required this.onTogglePin,
    required this.onFocusSubtree,
    required this.treeSearchQuery,
    required this.searchOptions,
  });

  static const double _cpuWarningPercent = 50;
  static const double _cpuStrongPercent = 10;
  static const double _metricLabelWidth = 44;

  final _ProcessColumn column;
  final ProcessTreeRow row;
  final double cpuScaleMax;
  final MeridianRowColors rowColors;
  final bool isSelected;
  final bool isHovered;
  final bool isPinned;
  final ValueChanged<ProcessIdentity> onToggleExpanded;
  final ValueChanged<ProcessIdentity> onTogglePin;
  final ValueChanged<ProcessIdentity> onFocusSubtree;
  final String treeSearchQuery;
  final ProcessSearchOptions searchOptions;

  @override
  Widget build(BuildContext context) {
    final process = row.record;
    final meridian = context.meridian;
    final colors = meridian.colors;
    final highlight = ProcessLamaTheme.of(context).searchHighlight;
    final matched = row.treeSearchMatchedColumnIds.contains(column.id);
    final value = switch (column.id) {
      'pid' => '${process.pid}',
      'cpu' => _formatPercent(process.cpuUsage),
      'treeCpu' => _formatPercent(row.treeCpuUsage),
      'gpu' => _formatPercent(process.gpuUsage),
      'treeGpu' => _formatPercent(row.treeGpuUsage),
      'memory' => _formatBytes(process.rssBytes),
      'treeMemory' => _formatBytes(row.treeRssBytes),
      'networkIn' => _formatRate(process.networkInBytesPerSecond),
      'networkOut' => _formatRate(process.networkOutBytesPerSecond),
      'treeNetworkIn' => _formatRate(row.treeNetworkInBytesPerSecond),
      'treeNetworkOut' => _formatRate(row.treeNetworkOutBytesPerSecond),
      'storageRead' =>
        process.storageIoAvailable
            ? _formatRate(process.storageReadBytesPerSecond)
            : '-',
      'storageWrite' =>
        process.storageIoAvailable
            ? _formatRate(process.storageWriteBytesPerSecond)
            : '-',
      'treeStorageRead' =>
        row.treeStorageIoAvailable
            ? _formatRate(row.treeStorageReadBytesPerSecond)
            : '-',
      'treeStorageWrite' =>
        row.treeStorageIoAvailable
            ? _formatRate(row.treeStorageWriteBytesPerSecond)
            : '-',
      'startTime' => _formatUnixMs(process.startTimeUnixMs),
      'status' => process.status.name,
      'uid' => '${process.uid}',
      'ports' => _formatPortsCell(process),
      _ => '',
    };
    final numberStyle = MeridianTextStyles.numeric(
      meridian.text.code.copyWith(color: rowColors.secondary),
    );

    if (column.id == 'name') {
      return _buildName(context, meridian, highlight, matched);
    }
    if (column.id == 'cpu' || column.id == 'treeCpu') {
      final usage = column.id == 'cpu' ? process.cpuUsage : row.treeCpuUsage;
      final warning = usage >= _cpuWarningPercent;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: MeridianSpace.space4),
        child: Row(
          children: [
            Expanded(
              // Telemetry is sampled, not an interaction. Update its bars in
              // the sample frame instead of relaying out cells between polls.
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: MeridianMeter(
                  value: usage / 100,
                  warningAt: _cpuWarningPercent / 100,
                  color: rowColors.strong ? rowColors.primary : null,
                ),
              ),
            ),
            const SizedBox(width: MeridianSpace.space3),
            SizedBox(
              width: _metricLabelWidth,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: numberStyle.copyWith(
                  color: warning && !rowColors.strong
                      ? colors.warning
                      : rowColors.secondary,
                  fontWeight: usage >= _cpuStrongPercent
                      ? FontWeight.w600
                      : null,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (column.id == 'status') {
      final tone = switch (process.status) {
        ProcessStatus.running => MeridianStatusTone.success,
        ProcessStatus.stopped => MeridianStatusTone.warning,
        ProcessStatus.zombie => MeridianStatusTone.danger,
        ProcessStatus.sleeping ||
        ProcessStatus.unknown => MeridianStatusTone.neutral,
      };
      final label =
          process.status.name[0].toUpperCase() +
          process.status.name.substring(1);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: MeridianSpace.space4),
        child: Row(
          children: [
            MeridianStatusDot(
              tone: tone,
              halo: process.status == ProcessStatus.running,
            ),
            const SizedBox(width: MeridianSpace.space3),
            Expanded(
              child: Text.rich(
                _searchHighlightedSpan(
                  value: label,
                  query: treeSearchQuery,
                  options: searchOptions,
                  highlight: matched,
                  style: meridian.text.body.copyWith(
                    color: rowColors.secondary,
                  ),
                  highlightColor: highlight,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MeridianSpace.space4),
      child: Align(
        alignment: column.numeric
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: Text.rich(
          _searchHighlightedSpan(
            value: value,
            query: treeSearchQuery,
            options: searchOptions,
            highlight: matched,
            style: numberStyle,
            highlightColor: highlight,
          ),
          overflow: TextOverflow.ellipsis,
          textAlign: column.numeric ? TextAlign.right : TextAlign.left,
          maxLines: 1,
        ),
      ),
    );
  }

  Widget _buildName(
    BuildContext context,
    MeridianTheme meridian,
    Color highlight,
    bool matched,
  ) {
    final process = row.record;
    final colors = meridian.colors;
    final nameStyle =
        (isSelected ? meridian.text.bodyStrong : meridian.text.body).copyWith(
          color: rowColors.primary,
          decoration: row.isTerminated ? TextDecoration.lineThrough : null,
        );
    final showPin = isPinned || isHovered || isSelected;
    return Row(
      children: [
        SizedBox(
          width: MeridianSpace.space3 + row.depth * MeridianLayout.treeIndent,
        ),
        SizedBox(
          width: MeridianLayout.navChevronTarget,
          child: _ChangeMarkerIcon(row: row, rowColors: rowColors),
        ),
        SizedBox(
          width: MeridianLayout.navChevronTarget,
          child: row.hasChildren
              ? MeridianIconButton(
                  label: row.isExpanded
                      ? context.l10n.collapse
                      : context.l10n.expand,
                  icon: row.isExpanded
                      ? MeridianIcons.chevronDown
                      : MeridianIcons.chevronRight,
                  size: MeridianControlSize.small,
                  color: rowColors.icon,
                  canRequestFocus: false,
                  onPressed: () => onToggleExpanded(row.identity),
                )
              : null,
        ),
        const SizedBox(width: MeridianSpace.space1),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: row.isTerminated
                ? null
                : () => onFocusSubtree(row.identity),
            child: Row(
              children: [
                _ProcessIcon(
                  name: process.displayName,
                  iconPath: row.iconPath,
                  iconUpdates: row.iconUpdates,
                  size: MeridianLayout.avatarSmall,
                ),
                const SizedBox(width: MeridianSpace.space4),
                Expanded(
                  child: Text.rich(
                    _searchHighlightedSpan(
                      value: process.displayName,
                      query: treeSearchQuery,
                      options: searchOptions,
                      highlight: matched,
                      style: nameStyle,
                      highlightColor: highlight,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (row.descendantCount > 0) ...[
                  const SizedBox(width: MeridianSpace.space3),
                  Text(
                    '${row.descendantCount}',
                    style: MeridianTextStyles.numeric(
                      meridian.text.codeSm.copyWith(color: rowColors.secondary),
                    ),
                  ),
                ],
                const SizedBox(width: MeridianSpace.space4),
                _Sparkline(
                  samples: row.cpuHistory,
                  maxValue: cpuScaleMax,
                  color: rowColors.strong ? rowColors.primary : null,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: MeridianSpace.space2),
        SizedBox(
          width: MeridianSize.controlSm,
          child: showPin
              ? MeridianIconButton(
                  label: isPinned
                      ? context.l10n.unpinProcess
                      : context.l10n.pinProcess,
                  icon: MeridianIcons.pin,
                  size: MeridianControlSize.small,
                  color: isPinned && !rowColors.strong
                      ? colors.accentInk
                      : rowColors.icon,
                  canRequestFocus: false,
                  onPressed: () => onTogglePin(row.identity),
                )
              : null,
        ),
        const SizedBox(width: MeridianSpace.space2),
      ],
    );
  }
}

TextSpan _searchHighlightedSpan({
  required String value,
  required String query,
  required ProcessSearchOptions options,
  required bool highlight,
  required TextStyle? style,
  required Color highlightColor,
}) {
  if (!highlight || query.isEmpty || value.isEmpty) {
    return TextSpan(text: value, style: style);
  }

  final match = _firstSearchMatch(value, query, options);
  if (match == null) {
    return TextSpan(text: value, style: style);
  }

  final highlightStyle =
      style?.copyWith(backgroundColor: highlightColor) ??
      TextStyle(backgroundColor: highlightColor);
  return TextSpan(
    style: style,
    children: [
      if (match.start > 0) TextSpan(text: value.substring(0, match.start)),
      TextSpan(
        text: value.substring(match.start, match.end),
        style: highlightStyle,
      ),
      if (match.end < value.length) TextSpan(text: value.substring(match.end)),
    ],
  );
}

({int start, int end})? _firstSearchMatch(
  String value,
  String query,
  ProcessSearchOptions options,
) {
  if (options.wholeWord) {
    final pattern = RegExp(
      r'(^|[^\w])' + RegExp.escape(query) + r'($|[^\w])',
      caseSensitive: options.matchCase,
    );
    final match = pattern.firstMatch(value);
    if (match == null) {
      return null;
    }
    final leading = match.group(1)?.length ?? 0;
    return (
      start: match.start + leading,
      end: match.end - (match.group(2)?.length ?? 0),
    );
  }

  final candidate = options.matchCase ? value : value.toLowerCase();
  final needle = options.matchCase ? query : query.toLowerCase();
  final start = candidate.indexOf(needle);
  if (start < 0) {
    return null;
  }
  return (start: start, end: start + query.length);
}

class _ChangeMarkerIcon extends StatelessWidget {
  const _ChangeMarkerIcon({required this.row, required this.rowColors});

  final ProcessTreeRow row;
  final MeridianRowColors rowColors;

  @override
  Widget build(BuildContext context) {
    final colors = context.meridian.colors;
    final (icon, color, label) = switch (row.changeMarker) {
      ProcessChangeMarker.spawned => (
        MeridianIcons.circlePlus,
        colors.success,
        context.l10n.spawned,
      ),
      ProcessChangeMarker.terminated => (
        MeridianIcons.circleMinus,
        colors.danger,
        context.l10n.terminated,
      ),
      ProcessChangeMarker.none => (null, null, null),
    };
    if (icon == null) {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: label,
      child: Center(
        child: MeridianIcon(
          icon,
          size: MeridianIconSize.small,
          color: rowColors.strong ? rowColors.icon : color,
        ),
      ),
    );
  }
}

/// A process's own icon, or its initial on a categorical colour when it has
/// none. [size] is one of the `MeridianLayout.avatar*` sizes.
class _ProcessIcon extends StatelessWidget {
  const _ProcessIcon({
    required this.name,
    required this.iconPath,
    this.iconUpdates,
    this.size = MeridianLayout.avatarSmall,
  });

  static const double _maxCacheExtent = 96;
  static const double _minCacheExtent = 16;

  final String name;
  final String? iconPath;

  /// Rebuilds only this icon when a remote icon arrives.
  final ValueListenable<String?>? iconUpdates;
  final double size;

  @override
  Widget build(BuildContext context) {
    final updates = iconUpdates;
    if (updates == null) {
      return _icon(context, iconPath);
    }
    return ValueListenableBuilder<String?>(
      valueListenable: updates,
      builder: (context, path, _) => _icon(context, path ?? iconPath),
    );
  }

  Widget _icon(BuildContext context, String? path) {
    final file = path == null || path.isEmpty ? null : _resolveIconFile(path);
    final fallback = _ProcessInitial(name: name, size: size);
    if (file == null) {
      return fallback;
    }
    final cacheExtent = (size * MediaQuery.devicePixelRatioOf(context))
        .clamp(_minCacheExtent, _maxCacheExtent)
        .ceil();
    final isSvg = file.path.toLowerCase().endsWith('.svg');
    return SizedBox.square(
      dimension: size,
      child: isSvg
          ? SvgPicture.file(
              file,
              width: size,
              height: size,
              fit: BoxFit.contain,
              placeholderBuilder: (_) => fallback,
              errorBuilder: (_, _, _) => fallback,
            )
          : Image.file(
              file,
              width: size,
              height: size,
              cacheWidth: cacheExtent,
              cacheHeight: cacheExtent,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

File? _resolveIconFile(String value) {
  if (value.startsWith('file://')) {
    final uri = Uri.tryParse(value);
    if (uri != null && uri.scheme == 'file') {
      return File.fromUri(uri);
    }
    return null;
  }
  return File(value);
}

class _ProcessInitial extends StatelessWidget {
  const _ProcessInitial({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return MeridianAvatar(
      name: name.isEmpty ? '?' : name,
      size: switch (size) {
        >= MeridianLayout.avatarLarge => MeridianAvatarSize.large,
        >= MeridianLayout.avatarMedium => MeridianAvatarSize.medium,
        _ => MeridianAvatarSize.small,
      },
    );
  }
}

List<MeridianMenuEntry> _processMenuEntries({
  required BuildContext context,
  required ProcessTreeRow row,
  required bool isPinned,
  required ValueChanged<ProcessIdentity> onTogglePin,
  required ValueChanged<ProcessIdentity> onFocusSubtree,
  required Future<void> Function(ProcessIdentity identity) onTerminateProcess,
  required Future<void> Function(ProcessIdentity identity) onKillProcess,
  required Future<void> Function(ProcessIdentity identity) onSuspendProcess,
  required Future<void> Function(ProcessIdentity identity) onResumeProcess,
  required ValueChanged<ProcessIdentity> onExpandSubtree,
  required ValueChanged<ProcessIdentity> onCollapseSubtree,
}) {
  final l10n = context.l10n;
  final process = row.record;
  final alive = !row.isTerminated;
  final isStopped = process.status == ProcessStatus.stopped;
  return [
    MeridianMenuItem(
      label: isPinned ? l10n.unpinProcessMenu : l10n.pinProcessMenu,
      icon: isPinned ? MeridianIcons.pinOff : MeridianIcons.pin,
      onSelected: () => onTogglePin(row.identity),
    ),
    const MeridianMenuDivider(),
    MeridianMenuItem(
      label: l10n.focusSubtree,
      icon: MeridianIcons.focus,
      shortcut: defaultTargetPlatform == TargetPlatform.macOS
          ? const ['⇧', '↵']
          : const ['Shift', 'Enter'],
      onSelected: alive ? () => onFocusSubtree(row.identity) : null,
    ),
    MeridianMenuItem(
      label: l10n.expandSubtree,
      icon: MeridianIcons.chevronsUpDown,
      onSelected: row.hasChildren ? () => onExpandSubtree(row.identity) : null,
    ),
    MeridianMenuItem(
      label: l10n.collapseSubtree,
      icon: MeridianIcons.chevronsDownUp,
      onSelected: row.hasChildren
          ? () => onCollapseSubtree(row.identity)
          : null,
    ),
    const MeridianMenuDivider(),
    MeridianMenuItem(
      label: l10n.copyPid('${process.pid}'),
      icon: MeridianIcons.copy,
      onSelected: () =>
          Clipboard.setData(ClipboardData(text: '${process.pid}')),
    ),
    MeridianMenuItem(
      label: l10n.copyName(process.displayName),
      icon: MeridianIcons.copy,
      onSelected: () =>
          Clipboard.setData(ClipboardData(text: process.displayName)),
    ),
    MeridianMenuItem(
      label: l10n.copyExecutablePath,
      icon: MeridianIcons.copy,
      onSelected: process.executablePath.isEmpty
          ? null
          : () =>
                Clipboard.setData(ClipboardData(text: process.executablePath)),
    ),
    const MeridianMenuDivider(),
    if (isStopped)
      MeridianMenuItem(
        label: l10n.resumeProcessMenu,
        icon: MeridianIcons.circlePlay,
        onSelected: alive
            ? () => unawaited(onResumeProcess(row.identity))
            : null,
      )
    else
      MeridianMenuItem(
        label: l10n.suspendProcessMenu,
        icon: MeridianIcons.circlePause,
        onSelected: alive
            ? () => unawaited(onSuspendProcess(row.identity))
            : null,
      ),
    MeridianMenuItem(
      label: l10n.terminateProcessMenu,
      icon: MeridianIcons.circleStop,
      danger: true,
      onSelected: alive
          ? () => unawaited(onTerminateProcess(row.identity))
          : null,
    ),
    MeridianMenuItem(
      label: l10n.killProcessMenu,
      icon: MeridianIcons.octagonX,
      danger: true,
      onSelected: alive ? () => unawaited(onKillProcess(row.identity)) : null,
    ),
  ];
}

int _matchingCount(List<ProcessRecord> processes, String filter) {
  final query = ProcessSearchQuery.parse(filter);
  return processes.where(query.matches).length;
}
