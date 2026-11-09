part of '../process_explorer_screen.dart';

String _columnLabel(BuildContext context, String columnId) {
  final l10n = context.l10n;
  return switch (columnId) {
    'pid' => l10n.columnPid,
    'name' => l10n.columnName,
    'cpu' => l10n.columnCpu,
    'treeCpu' => l10n.columnTreeCpu,
    'gpu' => l10n.columnGpu,
    'treeGpu' => l10n.columnTreeGpu,
    'memory' => l10n.columnRss,
    'treeMemory' => l10n.columnTreeRss,
    'networkIn' => l10n.columnNetIn,
    'networkOut' => l10n.columnNetOut,
    'treeNetworkIn' => l10n.columnTreeNetIn,
    'treeNetworkOut' => l10n.columnTreeNetOut,
    'storageRead' => l10n.columnStorageRead,
    'storageWrite' => l10n.columnStorageWrite,
    'treeStorageRead' => l10n.columnTreeStorageRead,
    'treeStorageWrite' => l10n.columnTreeStorageWrite,
    'startTime' => l10n.columnStarted,
    'status' => l10n.columnState,
    'uid' => l10n.columnUid,
    'ports' => l10n.columnPorts,
    _ => columnId,
  };
}

class _ProcessColumn {
  const _ProcessColumn({
    required this.id,
    required this.label,
    required this.sortColumn,
    this.width = 0,
    this.flex = 0,
    this.numeric = false,
  });

  final String id;
  final String label;
  final ProcessSortColumn sortColumn;
  final double width;
  final int flex;
  final bool numeric;
}

const Map<String, _ProcessColumn> _processColumns = {
  'pid': _ProcessColumn(
    id: 'pid',
    label: 'PID',
    sortColumn: ProcessSortColumn.pid,
    width: 86,
    numeric: true,
  ),
  'name': _ProcessColumn(
    id: 'name',
    label: 'Name',
    sortColumn: ProcessSortColumn.name,
    flex: 4,
  ),
  'cpu': _ProcessColumn(
    id: 'cpu',
    label: 'CPU',
    sortColumn: ProcessSortColumn.cpu,
    width: 82,
    numeric: true,
  ),
  'treeCpu': _ProcessColumn(
    id: 'treeCpu',
    label: 'Tree CPU',
    sortColumn: ProcessSortColumn.treeCpu,
    width: 96,
    numeric: true,
  ),
  'gpu': _ProcessColumn(
    id: 'gpu',
    label: 'GPU',
    sortColumn: ProcessSortColumn.gpu,
    width: 72,
    numeric: true,
  ),
  'treeGpu': _ProcessColumn(
    id: 'treeGpu',
    label: 'Tree GPU',
    sortColumn: ProcessSortColumn.treeGpu,
    width: 96,
    numeric: true,
  ),
  'memory': _ProcessColumn(
    id: 'memory',
    label: 'RSS',
    sortColumn: ProcessSortColumn.memory,
    width: 112,
    numeric: true,
  ),
  'treeMemory': _ProcessColumn(
    id: 'treeMemory',
    label: 'Tree RSS',
    sortColumn: ProcessSortColumn.treeMemory,
    width: 112,
    numeric: true,
  ),
  'networkIn': _ProcessColumn(
    id: 'networkIn',
    label: 'Net In',
    sortColumn: ProcessSortColumn.networkIn,
    width: 94,
    numeric: true,
  ),
  'networkOut': _ProcessColumn(
    id: 'networkOut',
    label: 'Net Out',
    sortColumn: ProcessSortColumn.networkOut,
    width: 94,
    numeric: true,
  ),
  'treeNetworkIn': _ProcessColumn(
    id: 'treeNetworkIn',
    label: 'Tree Net In',
    sortColumn: ProcessSortColumn.treeNetworkIn,
    width: 118,
    numeric: true,
  ),
  'treeNetworkOut': _ProcessColumn(
    id: 'treeNetworkOut',
    label: 'Tree Net Out',
    sortColumn: ProcessSortColumn.treeNetworkOut,
    width: 126,
    numeric: true,
  ),
  'storageRead': _ProcessColumn(
    id: 'storageRead',
    label: 'Storage Read',
    sortColumn: ProcessSortColumn.storageRead,
    width: 104,
    numeric: true,
  ),
  'storageWrite': _ProcessColumn(
    id: 'storageWrite',
    label: 'Storage Write',
    sortColumn: ProcessSortColumn.storageWrite,
    width: 104,
    numeric: true,
  ),
  'treeStorageRead': _ProcessColumn(
    id: 'treeStorageRead',
    label: 'Tree Storage Read',
    sortColumn: ProcessSortColumn.treeStorageRead,
    width: 132,
    numeric: true,
  ),
  'treeStorageWrite': _ProcessColumn(
    id: 'treeStorageWrite',
    label: 'Tree Storage Write',
    sortColumn: ProcessSortColumn.treeStorageWrite,
    width: 132,
    numeric: true,
  ),
  'startTime': _ProcessColumn(
    id: 'startTime',
    label: 'Started',
    sortColumn: ProcessSortColumn.startTime,
    width: 96,
  ),
  'status': _ProcessColumn(
    id: 'status',
    label: 'State',
    sortColumn: ProcessSortColumn.status,
    width: 98,
  ),
  'uid': _ProcessColumn(
    id: 'uid',
    label: 'UID',
    sortColumn: ProcessSortColumn.uid,
    width: 76,
    numeric: true,
  ),
  'ports': _ProcessColumn(
    id: 'ports',
    label: 'Ports',
    sortColumn: ProcessSortColumn.ports,
    width: 120,
    numeric: true,
  ),
};

List<_ProcessColumn> _visibleColumnDefinitions(AppSettings settings) {
  return _normalizedVisibleColumnIds(
    settings.visibleColumns,
  ).map((id) => _processColumns[id]).whereType<_ProcessColumn>().toList();
}

double _columnDragWidth(_ProcessColumn column) {
  return column.flex > 0 ? 180 : column.width;
}

List<MeridianMenuEntry> _columnMenuEntries({
  required BuildContext context,
  required AppSettings settings,
  required ValueChanged<List<String>> onChanged,
}) {
  final visible = _normalizedVisibleColumnIds(settings.visibleColumns);
  return [
    MeridianMenuHeader(context.l10n.columns),
    for (final id in AppSettings.availableColumns)
      MeridianMenuItem(
        label: _columnLabel(context, id),
        checked: visible.contains(id),
        onSelected: id == 'name'
            ? null
            : () => onChanged(_toggleColumn(visible, id)),
      ),
    const MeridianMenuDivider(),
    MeridianMenuItem(
      label: context.l10n.showAllColumns,
      onSelected: () => onChanged(AppSettings.defaultVisibleColumns),
    ),
    MeridianMenuItem(
      label: context.l10n.resetColumnOrder,
      onSelected: () => onChanged(AppSettings.defaultVisibleColumns),
    ),
  ];
}

List<String> _toggleColumn(List<String> visible, String id) {
  if (id == 'name') {
    return visible;
  }
  final next = [...visible];
  if (next.contains(id)) {
    next.remove(id);
  } else if (AppSettings.availableColumns.contains(id)) {
    next.add(id);
  }
  return _normalizedVisibleColumnIds(next);
}

List<String> _normalizedVisibleColumnIds(List<String> visibleColumns) {
  final seen = <String>{};
  final visible = visibleColumns
      .where(AppSettings.availableColumns.contains)
      .where(seen.add)
      .toList();
  if (!visible.contains('name')) {
    visible.insert(0, 'name');
  }
  return visible;
}
