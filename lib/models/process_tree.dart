import 'package:flutter/foundation.dart';

import 'process_identity.dart';
import 'process_record.dart';
import 'process_search_options.dart';
import 'process_snapshot.dart';

enum ProcessChangeMarker { none, spawned, terminated }

enum ProcessSortColumn {
  tree,
  name,
  pid,
  cpu,
  treeCpu,
  gpu,
  treeGpu,
  memory,
  treeMemory,
  networkIn,
  networkOut,
  treeNetworkIn,
  treeNetworkOut,
  storageRead,
  storageWrite,
  treeStorageRead,
  treeStorageWrite,
  startTime,
  status,
  uid,
  ports,
}

enum ProcessSortDirection { ascending, descending }

class ProcessTreeLockState {
  const ProcessTreeLockState({
    required this.isFrozen,
    required this.hasQueuedStructuralMutations,
    required this.queuedProcessCount,
    required this.isOrderLockedByInteraction,
  });

  const ProcessTreeLockState.unlocked()
    : isFrozen = false,
      hasQueuedStructuralMutations = false,
      queuedProcessCount = 0,
      isOrderLockedByInteraction = false;

  final bool isFrozen;
  final bool hasQueuedStructuralMutations;
  final int queuedProcessCount;
  final bool isOrderLockedByInteraction;
}

class ProcessTreeRow {
  ProcessTreeRow({
    required this.identity,
    required this.record,
    required this.iconPath,
    this.iconUpdates,
    required this.depth,
    required this.treeCpuUsage,
    required this.treeGpuUsage,
    required this.treeRssBytes,
    required this.treeNetworkInBytesPerSecond,
    required this.treeNetworkOutBytesPerSecond,
    this.treeStorageReadBytesPerSecond = 0,
    this.treeStorageWriteBytesPerSecond = 0,
    this.treeStorageIoAvailable = false,
    required this.processCpuHistory,
    required this.processGpuHistory,
    required this.processRssHistory,
    required this.processNetworkInHistory,
    required this.processNetworkOutHistory,
    this.processStorageReadHistory = const <double>[],
    this.processStorageWriteHistory = const <double>[],
    required this.cpuHistory,
    required this.gpuHistory,
    required this.rssHistory,
    required this.networkInHistory,
    required this.networkOutHistory,
    this.storageReadHistory = const <double>[],
    this.storageWriteHistory = const <double>[],
    required this.descendantCount,
    required this.hasChildren,
    required this.isExpanded,
    required this.matchesFilter,
    required this.preservesFilterBranch,
    required this.matchesTreeSearch,
    required this.treeSearchMatchedColumnIds,
    required this.changeMarker,
  });

  final ProcessIdentity identity;
  final ProcessRecord record;
  final String? iconPath;

  /// Follows a remote icon that arrives after this row was published; only
  /// the icon rebuilds. Null for icons that cannot change.
  final ValueListenable<String?>? iconUpdates;
  final int depth;
  final double treeCpuUsage;
  final double treeGpuUsage;
  final int treeRssBytes;
  final double treeNetworkInBytesPerSecond;
  final double treeNetworkOutBytesPerSecond;
  final double treeStorageReadBytesPerSecond;
  final double treeStorageWriteBytesPerSecond;
  final bool treeStorageIoAvailable;
  final List<double> processCpuHistory;
  final List<double> processGpuHistory;
  final List<double> processRssHistory;
  final List<double> processNetworkInHistory;
  final List<double> processNetworkOutHistory;
  final List<double> processStorageReadHistory;
  final List<double> processStorageWriteHistory;
  final List<double> cpuHistory;
  final List<double> gpuHistory;
  final List<double> rssHistory;
  final List<double> networkInHistory;
  final List<double> networkOutHistory;
  final List<double> storageReadHistory;
  final List<double> storageWriteHistory;
  final int descendantCount;
  final bool hasChildren;
  final bool isExpanded;
  final bool matchesFilter;
  final bool preservesFilterBranch;
  final bool matchesTreeSearch;
  final Set<String> treeSearchMatchedColumnIds;
  final ProcessChangeMarker changeMarker;

  bool get isTerminated => changeMarker == ProcessChangeMarker.terminated;
}

class ProcessTreeView {
  ProcessTreeView({
    required this.snapshot,
    required this.visibleRows,
    required this.expandedIdentities,
    required this.selectedIdentity,
    required this.filter,
    required this.treeSearchQuery,
    required this.treeSearchMatchCount,
    required this.treeSearchSelectedMatchIndex,
    required this.searchOptions,
    required this.lock,
    required this.sortColumn,
    required this.sortDirection,
    required this.pinnedIdentities,
    required this.focusedIdentity,
    required this.focusStack,
    required this.focusedProcessName,
    required this.cpuScaleMax,
  });

  factory ProcessTreeView.empty() {
    return ProcessTreeView(
      snapshot: ProcessSnapshot.empty(),
      visibleRows: const <ProcessTreeRow>[],
      expandedIdentities: const <ProcessIdentity>{},
      selectedIdentity: null,
      filter: '',
      treeSearchQuery: '',
      treeSearchMatchCount: 0,
      treeSearchSelectedMatchIndex: -1,
      searchOptions: const ProcessSearchOptions(),
      lock: const ProcessTreeLockState.unlocked(),
      sortColumn: ProcessSortColumn.tree,
      sortDirection: ProcessSortDirection.ascending,
      pinnedIdentities: const <ProcessIdentity>{},
      focusedIdentity: null,
      focusStack: const <ProcessIdentity>[],
      focusedProcessName: null,
      cpuScaleMax: 1,
    );
  }

  final ProcessSnapshot snapshot;
  final List<ProcessTreeRow> visibleRows;
  final Set<ProcessIdentity> expandedIdentities;
  final ProcessIdentity? selectedIdentity;
  final String filter;
  final String treeSearchQuery;
  final int treeSearchMatchCount;
  final int treeSearchSelectedMatchIndex;
  final ProcessSearchOptions searchOptions;
  final ProcessTreeLockState lock;
  final ProcessSortColumn sortColumn;
  final ProcessSortDirection sortDirection;
  final Set<ProcessIdentity> pinnedIdentities;
  final ProcessIdentity? focusedIdentity;
  final List<ProcessIdentity> focusStack;
  final String? focusedProcessName;
  final double cpuScaleMax;

  bool get isFrozen => lock.isFrozen;

  bool get hasQueuedStructuralMutations => lock.hasQueuedStructuralMutations;

  int get queuedProcessCount => lock.queuedProcessCount;

  bool get isOrderLockedByInteraction => lock.isOrderLockedByInteraction;

  bool get isSubtreeFocused => focusedIdentity != null;

  ProcessTreeRow? get selectedRow {
    final selected = selectedIdentity;
    if (selected == null) {
      return null;
    }

    for (final row in visibleRows) {
      if (row.identity == selected) {
        return row;
      }
    }
    return null;
  }

  ProcessRecord? get selectedProcess => selectedRow?.record;
}
