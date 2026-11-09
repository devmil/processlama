import 'package:devmil_logging/devmil_logging.dart';
import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../models/models.dart';
import '../repositories/repositories.dart';
import 'process_icon_resolver.dart';
import 'process_icon_service.dart';
import 'process_service.dart';
import 'process_source.dart';
import 'repository_operation_tracker.dart';
import 'settings_service.dart';
import 'tree_order_lock_controller.dart';

const Set<String> _stableTreeSearchColumnIds = <String>{
  'name',
  'pid',
  'startTime',
  'status',
  'uid',
  'executablePath',
  'commandLine',
  'appBundlePath',
};

const InspectorSectionState _availableInspectorState = InspectorSectionState(
  availability: InspectorAvailability.available,
  message: '',
);

Set<String> _visibleStableTreeSearchColumnIds(List<String> visibleColumns) {
  final visible =
      visibleColumns.where(AppSettings.availableColumns.contains).toSet()
        ..add('name');
  return visible.intersection(_stableTreeSearchColumnIds);
}

String _formatSearchUnixMs(int unixMs) {
  if (unixMs <= 0) {
    return 'Unknown';
  }
  final dateTime = DateTime.fromMillisecondsSinceEpoch(unixMs);
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final second = dateTime.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

/// What a remote tab's snapshot carries besides its processes.
final class RemoteSnapshotContext {
  const RemoteSnapshotContext({required this.host, required this.icons});

  final SnapshotHost host;
  final Map<String, Uint8List> icons;
}

/// Builds the remote context of a snapshot about to be saved.
typedef RemoteSnapshotContextProvider =
    Future<RemoteSnapshotContext?> Function(ProcessSnapshot snapshot);

/// The explorer state of one tab: tree caches and filter, selection, freeze
/// and its queued snapshot, the order lock, metric histories, pins and the
/// inspector. A session consumes one [ProcessSource]; it never polls a
/// repository itself.
class ProcessSession implements ProcessService {
  ProcessSession({
    required this.source,
    required this.snapshotRepository,
    required this.repositoryOperationTracker,
    this.settingsService,
    this.iconResolver = const FileIconResolver(),
    this.iconService,
    this.remoteSnapshotContext,
    this._backgroundCadence = const ProcessCadence.background(
      defaultBackgroundRefreshInterval,
    ),
  }) {
    _orderLock.locked.addListener(_handleOrderLockChanged);
    _sourceUpdates = source.updates.listen(_handleSourceUpdate);
    source.state.addListener(_handleSourceStateChanged);
  }

  static final _log = Logger('ProcessService');

  final ProcessSource source;
  final SnapshotRepository snapshotRepository;
  final RepositoryOperationTracker repositoryOperationTracker;
  final SettingsService? settingsService;
  final ProcessIconResolver iconResolver;

  /// Takes the icons of loaded remote snapshots into the cache.
  final ProcessIconService? iconService;

  /// Set for remote tabs: their snapshots carry host and icons.
  final RemoteSnapshotContextProvider? remoteSnapshotContext;
  late final StreamSubscription<ProcessSnapshot> _sourceUpdates;
  ProcessCadence _backgroundCadence;
  var _active = true;
  var _disposed = false;

  /// Sampling follows the settings' polling interval. Without a settings
  /// service the session samples only on [refresh].
  var _autoRefresh = false;
  var _initialized = false;
  final ValueNotifier<ProcessSnapshot> _snapshot =
      ValueNotifier<ProcessSnapshot>(ProcessSnapshot.empty());
  final ValueNotifier<ProcessTreeView> _tree = ValueNotifier<ProcessTreeView>(
    ProcessTreeView.empty(),
  );
  final ValueNotifier<ProcessInspectorView> _inspector =
      ValueNotifier<ProcessInspectorView>(ProcessInspectorView.empty());
  final ValueNotifier<String> _filter = ValueNotifier<String>('');
  final ValueNotifier<ProcessSearchOptions> _searchOptions =
      ValueNotifier<ProcessSearchOptions>(const ProcessSearchOptions());

  /// The aspect picked in the search menu. A typed prefix such as `port:` or
  /// [showPort] only applies to its query; clearing it returns here.
  ProcessSearchAspect _chosenAspect = ProcessSearchAspect.all;
  final ValueNotifier<List<SnapshotEntry>> _savedSnapshots =
      ValueNotifier<List<SnapshotEntry>>(const <SnapshotEntry>[]);
  final ValueNotifier<String?> _loadedSnapshotPath = ValueNotifier<String?>(
    null,
  );
  final ValueNotifier<ProcessIdentity?> _selectedIdentityNotifier =
      ValueNotifier<ProcessIdentity?>(null);

  final Set<ProcessIdentity> _expandedIdentities = <ProcessIdentity>{};
  final Set<ProcessIdentity> _pinnedIdentities = <ProcessIdentity>{};
  Map<ProcessIdentity, ProcessIdentity?> _parentByIdentity =
      <ProcessIdentity, ProcessIdentity?>{};
  Map<ProcessIdentity, ProcessRecord> _cachedRecordsByIdentity =
      <ProcessIdentity, ProcessRecord>{};
  Map<ProcessIdentity?, List<ProcessIdentity>> _cachedChildrenByParent =
      <ProcessIdentity?, List<ProcessIdentity>>{};
  Map<ProcessIdentity?, List<ProcessIdentity>> _cachedSortedChildrenByParent =
      <ProcessIdentity?, List<ProcessIdentity>>{};
  Map<ProcessIdentity, _TreeMetrics> _cachedTreeMetrics =
      <ProcessIdentity, _TreeMetrics>{};

  bool _sortedChildrenDirty = true;
  ProcessTopology? _cachedTopology;

  ProcessSnapshot _activeSnapshot = ProcessSnapshot.empty();
  List<ProcessRecord> _displayRecords = const <ProcessRecord>[];
  Map<ProcessIdentity, ProcessChangeMarker> _changeMarkers =
      const <ProcessIdentity, ProcessChangeMarker>{};
  ProcessSnapshot? _queuedSnapshot;
  ProcessIdentity? _selectedIdentity;
  ProcessIdentity? _focusedIdentity;
  String _treeSearchQuery = '';
  Set<String> _treeSearchColumnIds = _visibleStableTreeSearchColumnIds(
    AppSettings.defaultVisibleColumns,
  );
  bool _selectFirstTreeSearchMatchOnPublish = false;
  final List<ProcessIdentity> _focusStack = <ProcessIdentity>[];
  ProcessSortColumn _sortColumn = AppSettings.defaultProcessSortColumn;
  ProcessSortDirection _sortDirection = AppSettings.defaultProcessSortDirection;
  Timer? _inspectorDetailTimer;
  final Map<ProcessIdentity, _MetricHistory> _cpuHistory =
      <ProcessIdentity, _MetricHistory>{};
  final Map<ProcessIdentity, _MetricHistory> _gpuHistory =
      <ProcessIdentity, _MetricHistory>{};
  final Map<ProcessIdentity, _MetricHistory> _rssHistory =
      <ProcessIdentity, _MetricHistory>{};
  final Map<ProcessIdentity, _MetricHistory> _networkInHistory =
      <ProcessIdentity, _MetricHistory>{};
  final Map<ProcessIdentity, _MetricHistory> _networkOutHistory =
      <ProcessIdentity, _MetricHistory>{};
  final Map<ProcessIdentity, _MetricHistory> _storageReadHistory =
      <ProcessIdentity, _MetricHistory>{};
  final Map<ProcessIdentity, _MetricHistory> _storageWriteHistory =
      <ProcessIdentity, _MetricHistory>{};
  final Map<ProcessIdentity, _MetricHistory> _processCpuHistory =
      <ProcessIdentity, _MetricHistory>{};
  final Map<ProcessIdentity, _MetricHistory> _processGpuHistory =
      <ProcessIdentity, _MetricHistory>{};
  final Map<ProcessIdentity, _MetricHistory> _processRssHistory =
      <ProcessIdentity, _MetricHistory>{};
  final Map<ProcessIdentity, _MetricHistory> _processNetworkInHistory =
      <ProcessIdentity, _MetricHistory>{};
  final Map<ProcessIdentity, _MetricHistory> _processNetworkOutHistory =
      <ProcessIdentity, _MetricHistory>{};
  final Map<ProcessIdentity, _MetricHistory> _processStorageReadHistory =
      <ProcessIdentity, _MetricHistory>{};
  final Map<ProcessIdentity, _MetricHistory> _processStorageWriteHistory =
      <ProcessIdentity, _MetricHistory>{};
  double _cpuScaleMax = 1;

  bool _refreshing = false;
  bool _frozen = false;
  bool _windowResizing = false;
  bool _hasAppliedInitialTreeExpansion = false;
  final TreeOrderLockController _orderLock = TreeOrderLockController();
  ProcessDetail? _selectedProcessDetail;
  int _inspectorDetailGeneration = 0;

  @override
  ValueListenable<ProcessSnapshot> get snapshot => _snapshot;

  @override
  ValueListenable<ProcessTreeView> get tree => _tree;

  @override
  ValueListenable<ProcessIdentity?> get selectedIdentity =>
      _selectedIdentityNotifier;

  @override
  ValueListenable<ProcessInspectorView> get inspector => _inspector;

  @override
  ValueListenable<List<SnapshotEntry>> get savedSnapshots => _savedSnapshots;

  @override
  ValueListenable<String> get filter => _filter;

  @override
  ValueListenable<ProcessSearchOptions> get searchOptions => _searchOptions;

  @override
  ValueListenable<String?> get loadedSnapshotPath => _loadedSnapshotPath;

  @override
  ProcessSourceDescriptor get sourceDescriptor => source.descriptor;

  @override
  ValueListenable<ProcessSourceState> get sourceState => source.state;

  @override
  ValueListenable<HostCapabilities> get hostCapabilities => source.capabilities;

  /// Whether this session's tab is the visible one.
  bool get isActive => _active;

  bool get isDisposed => _disposed;

  @override
  Future<void> initialize() async {
    if (_initialized || _disposed) {
      return;
    }
    _initialized = true;
    final settings = settingsService;
    if (settings != null) {
      _applySettings(settings.settings.value);
      settings.settings.addListener(_handleSettingsChanged);
    } else {
      _configureInspectorDetailTimer();
    }
    unawaited(_refreshSavedSnapshots());
    unawaited(refresh());
  }

  /// Marks this session's tab visible or hidden. Hidden tabs sample at the
  /// background cadence and stop refreshing the inspector.
  void setActive(bool active) {
    if (_active == active || _disposed) {
      return;
    }
    _active = active;
    _configureRefreshTimer(_pollingIntervalMs);
    _configureInspectorDetailTimer();
  }

  /// Replaces the cadence used while this tab is hidden.
  void setBackgroundCadence(ProcessCadence cadence) {
    if (_backgroundCadence == cadence) {
      return;
    }
    _backgroundCadence = cadence;
    _configureRefreshTimer(_pollingIntervalMs);
  }

  /// Stops sampling and releases listeners. The source is disposed by its
  /// owner after the session.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _inspectorDetailTimer?.cancel();
    settingsService?.settings.removeListener(_handleSettingsChanged);
    _orderLock.locked.removeListener(_handleOrderLockChanged);
    source.state.removeListener(_handleSourceStateChanged);
    await _sourceUpdates.cancel();
  }

  int get _pollingIntervalMs =>
      settingsService?.settings.value.pollingIntervalMs ??
      const AppSettings().pollingIntervalMs;

  void _handleOrderLockChanged() {
    _publishTree(recordMetrics: false);
  }

  @override
  Future<void> refresh() async {
    if (_disposed) {
      return;
    }
    if (_loadedSnapshotPath.value != null) {
      return;
    }
    if (_windowResizing) {
      return;
    }
    if (_refreshing) {
      return;
    }

    _refreshing = true;
    try {
      await source.sampleNow();
    } finally {
      _refreshing = false;
    }
  }

  /// Set while the source is stale or failed: the next sample's histories
  /// start after a gap instead of a line across the outage.
  var _historyGapPending = false;

  void _handleSourceStateChanged() {
    switch (source.state.value.phase) {
      case ProcessSourcePhase.stale || ProcessSourcePhase.failed:
        _historyGapPending = true;
      case ProcessSourcePhase.connecting || ProcessSourcePhase.live:
        break;
    }
  }

  void _handleSourceUpdate(ProcessSnapshot nextSnapshot) {
    if (_disposed || _loadedSnapshotPath.value != null || _windowResizing) {
      return;
    }
    try {
      if (_frozen && _hasStructuralChange(_activeSnapshot, nextSnapshot)) {
        _queuedSnapshot = nextSnapshot;
        _activeSnapshot = _mergeMetricsKeepingStructure(
          current: _activeSnapshot,
          metricsSource: nextSnapshot,
        );
        _displayRecords = _activeSnapshot.processes;
        _changeMarkers = const {};
        _rebuildTreeCaches(recordMetrics: true);
        _snapshot.value = _activeSnapshot;
        _publishTree();
      } else {
        _applySnapshot(nextSnapshot);
      }
    } on Object catch (error, stackTrace) {
      _log.warning('Failed to apply process snapshot.', error, stackTrace);
      _applySnapshot(ProcessSnapshot.empty(error: error.toString()));
    }
  }

  @override
  Future<void> takeSnapshot() async {
    repositoryOperationTracker.recordOperation(
      'SnapshotRepository.saveSnapshot',
      'ProcessService.takeSnapshot',
    );
    final remote = await remoteSnapshotContext?.call(_activeSnapshot);
    if (remote != null) {
      await snapshotRepository.saveRemoteSnapshot(
        _activeSnapshot,
        host: remote.host,
        icons: remote.icons,
      );
    } else {
      await snapshotRepository.saveSnapshot(_activeSnapshot);
    }
    await _refreshSavedSnapshots();
  }

  @override
  Future<List<SnapshotEntry>> listSnapshots() async {
    repositoryOperationTracker.recordOperation(
      'SnapshotRepository.listSnapshots',
      'ProcessService.listSnapshots',
    );
    return snapshotRepository.listSnapshots();
  }

  @override
  Future<void> showLiveSnapshot() async {
    if (_loadedSnapshotPath.value == null) {
      return;
    }

    _loadedSnapshotPath.value = null;
    _queuedSnapshot = null;
    _frozen = false;
    _orderLock.resetInteraction();
    if (settingsService case final settings?) {
      _configureRefreshTimer(settings.settings.value.pollingIntervalMs);
      _configureInspectorDetailTimer();
    } else {
      _configureInspectorDetailTimer();
    }
    await refresh();
  }

  @override
  Future<void> loadSnapshot(String path) async {
    repositoryOperationTracker.recordOperation(
      'SnapshotRepository.importSnapshot',
      'ProcessService.loadSnapshot',
    );
    final savedSnapshots = await snapshotRepository.listSnapshots();
    final savedPath = savedSnapshots.any((entry) => entry.path == path)
        ? path
        : await snapshotRepository.saveSnapshotDocument(path);
    final snapshot = await snapshotRepository.importSnapshot(savedPath);
    final embedded = await snapshotRepository.importSnapshotIcons(savedPath);
    if (embedded.isNotEmpty) {
      await iconService?.importIcons(embedded);
    }
    unawaited(source.setCadence(ProcessCadence.paused));
    _inspectorDetailTimer?.cancel();
    _selectedProcessDetail = null;
    _inspectorDetailGeneration++;
    _loadedSnapshotPath.value = savedPath;
    _queuedSnapshot = null;
    _frozen = false;
    _orderLock.resetInteraction();
    _applySnapshot(snapshot);
    if (savedPath != path) {
      await _refreshSavedSnapshots();
    }
  }

  @override
  Future<void> exportSnapshot(SnapshotEntry entry, String targetPath) async {
    repositoryOperationTracker.recordOperation(
      'SnapshotRepository.exportSnapshotToPath',
      'ProcessService.exportSnapshot',
    );
    await snapshotRepository.exportSnapshotToPath(entry, targetPath);
  }

  @override
  Future<void> renameSnapshot(SnapshotEntry entry, String name) async {
    repositoryOperationTracker.recordOperation(
      'SnapshotRepository.renameSnapshot',
      'ProcessService.renameSnapshot',
    );
    await snapshotRepository.renameSnapshot(entry, name);
    await _refreshSavedSnapshots();
  }

  @override
  Future<void> deleteSnapshot(SnapshotEntry entry) async {
    repositoryOperationTracker.recordOperation(
      'SnapshotRepository.deleteSnapshot',
      'ProcessService.deleteSnapshot',
    );
    await snapshotRepository.deleteSnapshot(entry);
    await _refreshSavedSnapshots();
    if (_loadedSnapshotPath.value == entry.path) {
      await showLiveSnapshot();
    }
  }

  @override
  Future<void> terminateProcess(ProcessIdentity identity) async {
    await _sendProcessSignal(identity, ProcessSignal.terminate);
  }

  @override
  Future<void> killProcess(ProcessIdentity identity) async {
    await _sendProcessSignal(identity, ProcessSignal.kill);
  }

  @override
  Future<void> suspendProcess(ProcessIdentity identity) async {
    await _sendProcessSignal(identity, ProcessSignal.suspend);
  }

  @override
  Future<void> resumeProcess(ProcessIdentity identity) async {
    await _sendProcessSignal(identity, ProcessSignal.resume);
  }

  Future<void> _sendProcessSignal(
    ProcessIdentity identity,
    ProcessSignal signal,
  ) async {
    await source.sendSignal(identity, signal);
    await refresh();
  }

  Future<void> _refreshSavedSnapshots() async {
    _savedSnapshots.value = await snapshotRepository.listSnapshots();
  }

  @override
  void setFilter(String value) {
    var options = _searchOptions.value;
    // A prefix-chosen aspect ends with its query: when the text is cleared,
    // or a port search no longer holds a port number.
    if (options.aspect != _chosenAspect) {
      final query = ProcessSearchQuery(value.trim(), options);
      final keep = options.aspect == ProcessSearchAspect.port
          ? query.port != null
          : query.text.isNotEmpty;
      if (!keep) options = options.copyWith(aspect: _chosenAspect);
    }
    final parsed = ProcessSearchQuery.parse(value, options: options);
    _applyFilter(parsed.text, parsed.options);
  }

  @override
  void setSearchAspect(ProcessSearchAspect aspect) {
    _chosenAspect = aspect;
    _applyFilter(_filter.value, _searchOptions.value.copyWith(aspect: aspect));
  }

  @override
  void showPort(int port) {
    _applyFilter(
      '$port',
      _searchOptions.value.copyWith(aspect: ProcessSearchAspect.port),
    );
  }

  void _applyFilter(String text, ProcessSearchOptions options) {
    final aspectChanged = options.aspect != _searchOptions.value.aspect;
    if (_filter.value == text && !aspectChanged) return;
    if (aspectChanged) _searchOptions.value = options;
    _filter.value = text;
    _publishTree(allowInteractionOrderLock: false, recordMetrics: false);
  }

  @override
  void setSearchMatchCase(bool value) {
    final options = _searchOptions.value;
    if (options.matchCase == value) {
      return;
    }

    _searchOptions.value = options.copyWith(matchCase: value);
    _publishTree(allowInteractionOrderLock: false, recordMetrics: false);
  }

  @override
  void setSearchWholeWord(bool value) {
    final options = _searchOptions.value;
    if (options.wholeWord == value) {
      return;
    }

    _searchOptions.value = options.copyWith(wholeWord: value);
    _publishTree(allowInteractionOrderLock: false, recordMetrics: false);
  }

  @override
  void setTreeSearch(String value) {
    final next = value.trim();
    if (kDebugMode) {
      recordDiagnostic(
        const DiagnosticEvent(
          'processlama.process_session.diagnostic',
          detailed: true,
        ),
      );
    }
    if (_treeSearchQuery == next) {
      return;
    }

    _treeSearchQuery = next;
    _selectFirstTreeSearchMatchOnPublish = next.isNotEmpty;
    _publishTree(allowInteractionOrderLock: false, recordMetrics: false);
  }

  @override
  void selectNextTreeSearchMatch() {
    markTreeInteraction();
    _selectTreeSearchOffset(1);
  }

  @override
  void selectPreviousTreeSearchMatch() {
    markTreeInteraction();
    _selectTreeSearchOffset(-1);
  }

  @override
  void toggleExpansion(ProcessIdentity identity) {
    markTreeInteraction();
    if (_expandedIdentities.contains(identity)) {
      _expandedIdentities.remove(identity);
    } else {
      _expandedIdentities.add(identity);
    }
    _publishTree(recordMetrics: false);
  }

  @override
  void selectProcess(ProcessIdentity identity) {
    markTreeInteraction();
    _selectIdentity(identity);
  }

  @override
  void selectNextVisible() {
    markTreeInteraction();
    _selectVisibleOffset(1);
  }

  @override
  void selectPreviousVisible() {
    markTreeInteraction();
    _selectVisibleOffset(-1);
  }

  @override
  void markTreeInteraction() {
    if (_loadedSnapshotPath.value != null) {
      return;
    }

    _orderLock.markInteraction();
  }

  @override
  void expandSelected() {
    markTreeInteraction();
    final row = _selectedVisibleRow();
    if (row == null || !row.hasChildren) {
      return;
    }

    _expandedIdentities.add(row.identity);
    _publishTree(recordMetrics: false);
  }

  @override
  void collapseSelected() {
    markTreeInteraction();
    final row = _selectedVisibleRow();
    if (row == null) {
      return;
    }

    if (row.isExpanded) {
      _expandedIdentities.remove(row.identity);
      _publishTree(recordMetrics: false);
      return;
    }

    final parent = _parentByIdentity[row.identity];
    if (parent != null) {
      _selectIdentity(parent);
    }
  }

  @override
  void focusSelectedSubtree() {
    markTreeInteraction();
    final identity = _selectedIdentity;
    if (identity == null) {
      return;
    }
    focusSubtree(identity);
  }

  @override
  void focusSubtree(ProcessIdentity identity) {
    if (!_cachedRecordsByIdentity.containsKey(identity) ||
        identity == _focusedIdentity) {
      return;
    }

    final current = _focusedIdentity;
    if (current != null) {
      final descendants = _subtreeIdentities(root: current);
      if (descendants.contains(identity)) {
        _focusStack.add(current);
      } else {
        _focusStack.clear();
      }
    } else {
      _focusStack.clear();
    }

    _focusedIdentity = identity;
    _selectedIdentity = identity;
    _expandedIdentities.add(identity);
    _publishTree(allowInteractionOrderLock: false, recordMetrics: false);
  }

  @override
  void clearSubtreeFocus() {
    if (_focusedIdentity == null) {
      return;
    }
    final former = _focusedIdentity;
    _focusedIdentity = null;
    _focusStack.clear();
    _selectedIdentity = former;
    _publishTree(allowInteractionOrderLock: false, recordMetrics: false);
  }

  @override
  void popSubtreeFocus() {
    final former = _focusedIdentity;
    if (former == null) {
      return;
    }

    final next = _focusStack.isEmpty ? null : _focusStack.removeLast();
    _focusedIdentity = next;
    _selectedIdentity = next ?? former;
    if (next != null) {
      _expandedIdentities.add(next);
    }
    _publishTree(allowInteractionOrderLock: false, recordMetrics: false);
  }

  @override
  void expandSelectedSubtree() {
    markTreeInteraction();
    final row = _selectedVisibleRow();
    if (row == null) {
      return;
    }

    _expandedIdentities.addAll(_subtreeIdentities(root: row.identity));
    _publishTree(recordMetrics: false);
  }

  @override
  void collapseSelectedSubtree() {
    markTreeInteraction();
    final row = _selectedVisibleRow();
    if (row == null) {
      return;
    }

    final subtree = _subtreeIdentities(root: row.identity)
      ..remove(row.identity);
    _expandedIdentities.removeAll(subtree);
    _expandedIdentities.remove(row.identity);
    _publishTree(recordMetrics: false);
  }

  @override
  void sortBy(ProcessSortColumn column) {
    if (_sortColumn == column) {
      _sortDirection = _sortDirection == ProcessSortDirection.ascending
          ? ProcessSortDirection.descending
          : ProcessSortDirection.ascending;
    } else {
      _sortColumn = column;
      _sortDirection = switch (column) {
        ProcessSortColumn.tree ||
        ProcessSortColumn.name ||
        ProcessSortColumn.status ||
        ProcessSortColumn.startTime => ProcessSortDirection.ascending,
        ProcessSortColumn.pid ||
        ProcessSortColumn.cpu ||
        ProcessSortColumn.treeCpu ||
        ProcessSortColumn.gpu ||
        ProcessSortColumn.treeGpu ||
        ProcessSortColumn.memory ||
        ProcessSortColumn.treeMemory ||
        ProcessSortColumn.networkIn ||
        ProcessSortColumn.networkOut ||
        ProcessSortColumn.treeNetworkIn ||
        ProcessSortColumn.treeNetworkOut ||
        ProcessSortColumn.storageRead ||
        ProcessSortColumn.storageWrite ||
        ProcessSortColumn.treeStorageRead ||
        ProcessSortColumn.treeStorageWrite ||
        ProcessSortColumn.uid => ProcessSortDirection.descending,
        ProcessSortColumn.ports => ProcessSortDirection.ascending,
      };
    }
    final settings = settingsService;
    if (settings != null) {
      unawaited(settings.updateProcessSort(_sortColumn, _sortDirection));
    }
    _rebuildSortedChildren();
    _publishTree(allowInteractionOrderLock: false, recordMetrics: false);
  }

  @override
  void togglePin(ProcessIdentity identity) {
    markTreeInteraction();
    if (_pinnedIdentities.contains(identity)) {
      _pinnedIdentities.remove(identity);
    } else {
      _pinnedIdentities.add(identity);
    }
    _publishTree(recordMetrics: false);
  }

  @override
  void setTreeHovering(bool hovering) {
    _orderLock.setHovering(hovering);
  }

  @override
  void setTreeContextMenuOpen(bool open) {
    _orderLock.setContextMenuOpen(open);
  }

  @override
  void setModalOverlayOpen(bool open) {
    _orderLock.setModalOverlayOpen(open);
  }

  @override
  void setWindowResizing(bool resizing) {
    if (_windowResizing == resizing) {
      return;
    }
    _windowResizing = resizing;
    _configureRefreshTimer(_pollingIntervalMs);
  }

  @override
  void setFrozen(bool frozen) {
    if (_frozen == frozen) {
      return;
    }

    _frozen = frozen;
    if (!_frozen) {
      final queued = _queuedSnapshot;
      _queuedSnapshot = null;
      if (queued != null) {
        _applySnapshot(queued);
        return;
      }
    }
    _publishTree(recordMetrics: false);
  }

  @override
  void toggleFrozen() {
    setFrozen(!_frozen);
  }

  void _applySnapshot(ProcessSnapshot nextSnapshot) {
    final previousSnapshot = _activeSnapshot;
    final previousRecords = _recordsByIdentity(previousSnapshot.processes);
    final nextRecords = _recordsByIdentity(nextSnapshot.processes);
    final firstSnapshot = previousSnapshot.processes.isEmpty;

    final markers = <ProcessIdentity, ProcessChangeMarker>{};
    final displayRecords = <ProcessRecord>[...nextSnapshot.processes];

    if (!firstSnapshot) {
      for (final identity in nextRecords.keys) {
        if (!previousRecords.containsKey(identity)) {
          markers[identity] = ProcessChangeMarker.spawned;
        }
      }
      for (final entry in previousRecords.entries) {
        if (!nextRecords.containsKey(entry.key)) {
          markers[entry.key] = ProcessChangeMarker.terminated;
          displayRecords.add(entry.value);
        }
      }
    }

    _activeSnapshot = nextSnapshot;
    _displayRecords = displayRecords;
    _changeMarkers = markers;
    _rebuildTreeCaches(recordMetrics: true);
    _snapshot.value = nextSnapshot;
    _publishTree();
    if (_selectedProcessDetail?.identity != _selectedIdentity) {
      unawaited(_refreshInspectorDetail());
    }
  }

  void _publishTree({
    bool allowInteractionOrderLock = true,
    bool recordMetrics = true,
  }) {
    final previousVisibleOrder = _previousVisibleOrder();
    final orderLockedByInteraction =
        allowInteractionOrderLock &&
        _orderLock.locked.value &&
        previousVisibleOrder.isNotEmpty;
    // A locked tree also keeps its order through refreshes; explicit sorts,
    // filters and focus changes (allowInteractionOrderLock: false) still
    // apply.
    final orderFrozen =
        allowInteractionOrderLock && _frozen && previousVisibleOrder.isNotEmpty;
    if (_cachedRecordsByIdentity.length != _displayRecords.length) {
      _rebuildTreeCaches(recordMetrics: recordMetrics);
    }

    final tree = _buildTreeRows(
      _filter.value,
      searchOptions: _searchOptions.value,
      treeSearchQuery: _treeSearchQuery,
      preservePreviousVisibleOrder: orderLockedByInteraction || orderFrozen,
      previousVisibleOrder: previousVisibleOrder,
    );
    final treeSearchMatches = tree.visibleRows
        .where((row) => row.matchesTreeSearch && !row.isTerminated)
        .toList(growable: false);
    if (_selectFirstTreeSearchMatchOnPublish) {
      final firstTreeSearchMatch = treeSearchMatches.firstOrNull;
      if (firstTreeSearchMatch != null) {
        _selectedIdentity = firstTreeSearchMatch.identity;
      }
      _selectFirstTreeSearchMatchOnPublish = false;
    }
    if (_selectedIdentity == null ||
        !tree.visibleRows.any((row) => row.identity == _selectedIdentity)) {
      _selectedIdentity = tree.visibleRows
          .where((row) => !row.isTerminated)
          .firstOrNull
          ?.identity;
    }

    _pruneRowCache(tree.displayIdentities);
    final nextTree = ProcessTreeView(
      snapshot: _activeSnapshot,
      visibleRows: List<ProcessTreeRow>.unmodifiable(tree.visibleRows),
      expandedIdentities: Set<ProcessIdentity>.unmodifiable(
        _expandedIdentities,
      ),
      selectedIdentity: _selectedIdentity,
      filter: _filter.value,
      treeSearchQuery: _treeSearchQuery,
      treeSearchMatchCount: treeSearchMatches.length,
      treeSearchSelectedMatchIndex: treeSearchMatches.indexWhere(
        (row) => row.identity == _selectedIdentity,
      ),
      searchOptions: _searchOptions.value,
      lock: ProcessTreeLockState(
        isFrozen: _frozen,
        hasQueuedStructuralMutations: _queuedSnapshot != null,
        queuedProcessCount: _queuedSnapshot?.processes.length ?? 0,
        isOrderLockedByInteraction: orderLockedByInteraction,
      ),
      sortColumn: _sortColumn,
      sortDirection: _sortDirection,
      pinnedIdentities: Set<ProcessIdentity>.unmodifiable(_pinnedIdentities),
      focusedIdentity: _focusedIdentity,
      focusStack: List<ProcessIdentity>.unmodifiable(_focusStack),
      focusedProcessName: _focusedIdentity == null
          ? null
          : _cachedRecordsByIdentity[_focusedIdentity!]?.name,
      cpuScaleMax: _cpuScaleMax,
    );
    _tree.value = nextTree;
    if (_selectedIdentityNotifier.value != _selectedIdentity) {
      _selectedIdentityNotifier.value = _selectedIdentity;
    }
    _publishInspector();
  }

  void _publishInspector() {
    final selected = _selectedVisibleRow();
    if (selected == null) {
      _inspector.value = ProcessInspectorView.empty();
      return;
    }

    final process = selected.record;
    _inspector.value = ProcessInspectorView(
      process: process,
      ports: ProcessPorts.ofRecord(process),
      treePorts: _subtreePorts(selected.identity),
      listenerOwnersByPort: _listenerOwnersOfPeers(
        selected.identity,
        _selectedProcessDetail?.identity == selected.identity
            ? _selectedProcessDetail?.sockets
            : null,
      ),
      identity: selected.identity,
      changeMarker: selected.changeMarker,
      iconPath: selected.iconPath,
      iconUpdates: selected.iconUpdates,
      platform: _activeSnapshot.platform,
      detail: _selectedProcessDetail?.identity == selected.identity
          ? _selectedProcessDetail
          : null,
      overview: _availableInspectorState,
      openFiles: _detailState(_selectedProcessDetail?.files),
      sockets: _detailState(_selectedProcessDetail?.sockets),
      network: _availableInspectorState,
      threads: _detailState(_selectedProcessDetail?.threads),
      security: _detailState(_selectedProcessDetail?.security),
    );
  }

  ProcessPorts? _subtreePorts(ProcessIdentity root) {
    final pending = <ProcessIdentity>[root];
    final visited = <ProcessIdentity>{};
    final sources = <(List<int>, List<int>?)>[];
    while (pending.isNotEmpty) {
      final identity = pending.removeLast();
      if (!visited.add(identity)) continue;
      pending.addAll(_cachedChildrenByParent[identity] ?? const []);
      if (_changeMarkers[identity] == ProcessChangeMarker.terminated) continue;
      final record = _cachedRecordsByIdentity[identity];
      if (record?.localPorts case final localPorts?) {
        sources.add((localPorts, record!.listeningPorts));
      }
    }
    if (sources.isEmpty) return null;
    return ProcessPorts.merge(sources);
  }

  /// Listeners on the remote ports of [selected]'s loopback sockets, other
  /// than [selected] itself.
  Map<int, List<ProcessPortOwner>> _listenerOwnersOfPeers(
    ProcessIdentity selected,
    ProcessDetailSection<List<NetworkEndpointInfo>>? sockets,
  ) {
    if (sockets is! ProcessDetailAvailable<List<NetworkEndpointInfo>>) {
      return const {};
    }
    final peerPorts = {
      for (final endpoint in sockets.value)
        if (endpoint.remotePort != 0 &&
            isLoopbackAddress(endpoint.remoteAddress))
          endpoint.remotePort,
    };
    if (peerPorts.isEmpty) return const {};
    final owners = <int, List<ProcessPortOwner>>{};
    for (final MapEntry(key: identity, value: record)
        in _cachedRecordsByIdentity.entries) {
      if (identity == selected ||
          _changeMarkers[identity] == ProcessChangeMarker.terminated) {
        continue;
      }
      for (final port in record.listeningPorts ?? const <int>[]) {
        if (!peerPorts.contains(port)) continue;
        (owners[port] ??= []).add(
          ProcessPortOwner(
            identity: identity,
            pid: record.pid,
            name: record.displayName,
          ),
        );
      }
    }
    return Map.unmodifiable({
      for (final MapEntry(:key, :value) in owners.entries)
        key: List<ProcessPortOwner>.unmodifiable(value),
    });
  }

  InspectorSectionState _detailState<T>(ProcessDetailSection<T>? section) {
    return switch (section) {
      ProcessDetailAvailable<T>() => const InspectorSectionState(
        availability: InspectorAvailability.available,
        message: 'Inspector details are available.',
      ),
      ProcessDetailRestricted<T>(:final reason) => InspectorSectionState(
        availability: InspectorAvailability.requiresPermission,
        message: 'Restricted access: $reason',
      ),
      ProcessDetailUnsupported<T>(:final reason) => InspectorSectionState(
        availability: InspectorAvailability.unsupportedPlatform,
        message: reason,
      ),
      ProcessDetailNotFound<T>(:final reason) => InspectorSectionState(
        availability: InspectorAvailability.unavailable,
        message: reason,
      ),
      null => const InspectorSectionState(
        availability: InspectorAvailability.unavailable,
        message: 'Inspector details will appear after the next refresh.',
      ),
    };
  }

  Map<ProcessIdentity, int> _previousVisibleOrder() {
    return <ProcessIdentity, int>{
      for (final indexed in _tree.value.visibleRows.indexed)
        indexed.$2.identity: indexed.$1,
    };
  }

  int? _comparePreviousVisibleOrder(
    ProcessIdentity left,
    ProcessIdentity right,
    Map<ProcessIdentity, int> previousVisibleOrder,
  ) {
    final leftOrder = previousVisibleOrder[left];
    final rightOrder = previousVisibleOrder[right];
    if (leftOrder == null && rightOrder == null) {
      return null;
    }
    if (leftOrder == null) {
      return 1;
    }
    if (rightOrder == null) {
      return -1;
    }
    return leftOrder.compareTo(rightOrder);
  }

  _TreeBuildResult _buildTreeRows(
    String filter, {
    required ProcessSearchOptions searchOptions,
    required String treeSearchQuery,
    required bool preservePreviousVisibleOrder,
    required Map<ProcessIdentity, int> previousVisibleOrder,
  }) {
    final recordsByIdentity = _cachedRecordsByIdentity;
    if (!preservePreviousVisibleOrder && _sortedChildrenDirty) {
      _rebuildSortedChildren();
    }
    final childrenByParent = preservePreviousVisibleOrder
        ? _orderedChildrenForVisibleOrder(previousVisibleOrder)
        : _cachedSortedChildrenByParent;
    final roots = childrenByParent[null] ?? const <ProcessIdentity>[];
    final focusedIdentity = _focusedIdentity;
    final visibleRoots =
        focusedIdentity != null &&
            recordsByIdentity.containsKey(focusedIdentity)
        ? <ProcessIdentity>[focusedIdentity]
        : roots;
    if (focusedIdentity != null &&
        !recordsByIdentity.containsKey(focusedIdentity)) {
      _focusedIdentity = null;
      _focusStack.clear();
    }
    _applyInitialTreeExpansion(
      roots: roots,
      childrenByParent: childrenByParent,
      recordsByIdentity: recordsByIdentity,
    );

    final filterQuery = ProcessSearchQuery(filter, searchOptions);
    final treeSearchMatcher = _ProcessSearchMatcher(
      query: treeSearchQuery,
      options: searchOptions,
    );
    final hasFilter = filterQuery.text.isNotEmpty;
    final hasTreeSearch = treeSearchMatcher.hasQuery;
    final descendantMatchMemo = <ProcessIdentity, bool>{};
    final treeSearchDescendantMatchMemo = <ProcessIdentity, bool>{};
    final visibleRows = <ProcessTreeRow>[];

    bool recordMatches(ProcessRecord record) =>
        !hasFilter || filterQuery.matches(record);

    bool recordMatchesTreeSearch(ProcessRecord record) {
      if (!hasTreeSearch) {
        return false;
      }
      return treeSearchMatcher.matchesAny([
        record.displayName,
        record.pid.toString(),
        record.executablePath,
        record.commandLine,
        record.appBundlePath,
      ]);
    }

    bool hasMatchingDescendant(ProcessIdentity identity) {
      final cached = descendantMatchMemo[identity];
      if (cached != null) {
        return cached;
      }

      final children = childrenByParent[identity] ?? const <ProcessIdentity>[];
      final matches = children.any((child) {
        final record = recordsByIdentity[child];
        return (record != null && recordMatches(record)) ||
            hasMatchingDescendant(child);
      });
      descendantMatchMemo[identity] = matches;
      return matches;
    }

    bool hasTreeSearchMatchingDescendant(ProcessIdentity identity) {
      if (!hasTreeSearch) {
        return false;
      }
      final cached = treeSearchDescendantMatchMemo[identity];
      if (cached != null) {
        return cached;
      }

      final children = childrenByParent[identity] ?? const <ProcessIdentity>[];
      final matches = children.any((child) {
        final record = recordsByIdentity[child];
        return (record != null && recordMatchesTreeSearch(record)) ||
            hasTreeSearchMatchingDescendant(child);
      });
      treeSearchDescendantMatchMemo[identity] = matches;
      return matches;
    }

    void visit(ProcessIdentity identity, int depth, bool ancestorMatched) {
      final record = recordsByIdentity[identity];
      if (record == null) {
        return;
      }

      final children = childrenByParent[identity] ?? const <ProcessIdentity>[];
      final hasChildren = children.isNotEmpty;
      final expanded = _expandedIdentities.contains(identity);
      final matches = recordMatches(record);
      final treeSearchMatchedColumnIds = hasTreeSearch
          ? _recordSearchFieldsByColumn(
              record,
              treeSearchMatcher,
              _treeSearchColumnIds,
            ).keys.toSet()
          : <String>{};
      final descendantMatches = hasFilter && hasMatchingDescendant(identity);
      final forceExpandedForFilter = hasFilter && hasChildren;
      final forceExpandedForTreeSearch =
          hasTreeSearch &&
          hasChildren &&
          hasTreeSearchMatchingDescendant(identity);
      final forceExpanded =
          forceExpandedForFilter || forceExpandedForTreeSearch;
      final includeForFilter =
          !hasFilter || matches || descendantMatches || ancestorMatched;

      if (!includeForFilter) {
        return;
      }

      final metrics = _cachedTreeMetrics[identity];
      final selected = identity == _selectedIdentity;
      final row = ProcessTreeRow(
        identity: identity,
        record: record,
        iconPath: iconResolver.pathFor(record.iconRef),
        iconUpdates: iconResolver.updatesFor(record.iconRef),
        depth: depth,
        treeCpuUsage: metrics?.cpu ?? record.cpuUsage,
        treeGpuUsage: metrics?.gpu ?? record.gpuUsage,
        treeRssBytes: metrics?.rssBytes ?? record.rssBytes,
        treeNetworkInBytesPerSecond:
            metrics?.networkInBytesPerSecond ?? record.networkInBytesPerSecond,
        treeNetworkOutBytesPerSecond:
            metrics?.networkOutBytesPerSecond ??
            record.networkOutBytesPerSecond,
        treeStorageReadBytesPerSecond:
            metrics?.storageReadBytesPerSecond ??
            record.storageReadBytesPerSecond,
        treeStorageWriteBytesPerSecond:
            metrics?.storageWriteBytesPerSecond ??
            record.storageWriteBytesPerSecond,
        treeStorageIoAvailable:
            metrics?.storageIoAvailable ?? record.storageIoAvailable,
        processCpuHistory: selected
            ? _processCpuHistory[identity]?.asList() ?? const <double>[]
            : const <double>[],
        processGpuHistory: selected
            ? _processGpuHistory[identity]?.asList() ?? const <double>[]
            : const <double>[],
        processRssHistory: selected
            ? _processRssHistory[identity]?.asList() ?? const <double>[]
            : const <double>[],
        processNetworkInHistory: selected
            ? _processNetworkInHistory[identity]?.asList() ?? const <double>[]
            : const <double>[],
        processNetworkOutHistory: selected
            ? _processNetworkOutHistory[identity]?.asList() ?? const <double>[]
            : const <double>[],
        processStorageReadHistory: selected
            ? _processStorageReadHistory[identity]?.asList() ?? const <double>[]
            : const <double>[],
        processStorageWriteHistory: selected
            ? _processStorageWriteHistory[identity]?.asList() ??
                  const <double>[]
            : const <double>[],
        cpuHistory: _cpuHistory[identity]?.asList() ?? const <double>[],
        gpuHistory: selected
            ? _gpuHistory[identity]?.asList() ?? const <double>[]
            : const <double>[],
        rssHistory: selected
            ? _rssHistory[identity]?.asList() ?? const <double>[]
            : const <double>[],
        networkInHistory: selected
            ? _networkInHistory[identity]?.asList() ?? const <double>[]
            : const <double>[],
        networkOutHistory: selected
            ? _networkOutHistory[identity]?.asList() ?? const <double>[]
            : const <double>[],
        storageReadHistory: selected
            ? _storageReadHistory[identity]?.asList() ?? const <double>[]
            : const <double>[],
        storageWriteHistory: selected
            ? _storageWriteHistory[identity]?.asList() ?? const <double>[]
            : const <double>[],
        descendantCount: metrics?.descendantCount ?? 0,
        hasChildren: hasChildren,
        isExpanded: expanded || forceExpanded,
        matchesFilter: !hasFilter || matches,
        preservesFilterBranch: hasFilter && !matches,
        matchesTreeSearch: treeSearchMatchedColumnIds.isNotEmpty,
        treeSearchMatchedColumnIds: Set<String>.unmodifiable(
          treeSearchMatchedColumnIds,
        ),
        changeMarker: _changeMarkers[identity] ?? ProcessChangeMarker.none,
      );
      visibleRows.add(row);

      final shouldShowChildren = forceExpanded || expanded;
      if (!shouldShowChildren) {
        return;
      }

      for (final child in children) {
        visit(child, depth + 1, ancestorMatched || matches);
      }
    }

    for (final root in visibleRoots) {
      visit(root, 0, false);
    }

    return _TreeBuildResult(
      visibleRows: visibleRows,
      displayIdentities: recordsByIdentity.keys.toSet(),
    );
  }

  void _applyInitialTreeExpansion({
    required List<ProcessIdentity> roots,
    required Map<ProcessIdentity?, List<ProcessIdentity>> childrenByParent,
    required Map<ProcessIdentity, ProcessRecord> recordsByIdentity,
  }) {
    if (_hasAppliedInitialTreeExpansion || roots.isEmpty) {
      return;
    }

    _expandedIdentities.addAll(roots);
    if (source.capabilities.value.operatingSystem ==
        HostOperatingSystem.linux) {
      for (final root in roots) {
        final rootRecord = recordsByIdentity[root];
        if (rootRecord?.name != 'systemd') {
          continue;
        }
        for (final child
            in childrenByParent[root] ?? const <ProcessIdentity>[]) {
          if (recordsByIdentity[child]?.name == 'systemd') {
            _expandedIdentities.add(child);
          }
        }
      }
    }
    _hasAppliedInitialTreeExpansion = true;
  }

  Map<String, String> _recordSearchFieldsByColumn(
    ProcessRecord record,
    _ProcessSearchMatcher matcher,
    Set<String> columnIds,
  ) {
    final fields = <String, String>{
      'name': record.displayName,
      'pid': record.pid.toString(),
      'startTime': _formatSearchUnixMs(record.startTimeUnixMs),
      'status': record.status.name,
      'uid': record.uid.toString(),
      if (record.executablePath.isNotEmpty)
        'executablePath': record.executablePath,
      if (record.commandLine.isNotEmpty) 'commandLine': record.commandLine,
      if (record.appBundlePath.isNotEmpty)
        'appBundlePath': record.appBundlePath,
    };
    return <String, String>{
      for (final entry in fields.entries)
        if (columnIds.contains(entry.key) && matcher.matches(entry.value))
          entry.key: entry.value,
    };
  }

  void _rebuildTreeCaches({required bool recordMetrics}) {
    final recordsByIdentity = _recordsByIdentity(_displayRecords);
    final nativeTopology = _activeSnapshot.topology;
    // Exited rows remain for one publication. Build that presentation overlay
    // locally; ordinary live samples share the repository's immutable graph.
    final useNativeTopology =
        nativeTopology != null &&
        !_changeMarkers.containsValue(ProcessChangeMarker.terminated) &&
        nativeTopology.parentByIdentity.length == recordsByIdentity.length;
    final bool topologyChanged;
    if (useNativeTopology) {
      topologyChanged = !identical(nativeTopology, _cachedTopology);
      if (topologyChanged) {
        _cachedChildrenByParent = nativeTopology.childrenByParent;
        _parentByIdentity = nativeTopology.parentByIdentity;
      }
      _cachedTopology = nativeTopology;
    } else {
      topologyChanged =
          _cachedTopology != null ||
          _changeMarkers.isNotEmpty ||
          recordsByIdentity.length != _cachedRecordsByIdentity.length ||
          recordsByIdentity.entries.any(
            (entry) =>
                _cachedRecordsByIdentity[entry.key]?.ppid != entry.value.ppid,
          );
      if (topologyChanged) {
        final parentLinks = _parentLinks(_displayRecords);
        final childrenByParent = <ProcessIdentity?, List<ProcessIdentity>>{};
        for (final identity in recordsByIdentity.keys) {
          childrenByParent
              .putIfAbsent(parentLinks[identity], () => [])
              .add(identity);
        }
        _cachedChildrenByParent = childrenByParent;
        _parentByIdentity = parentLinks;
      }
      _cachedTopology = null;
    }
    final stableSort = switch (_sortColumn) {
      ProcessSortColumn.tree ||
      ProcessSortColumn.pid ||
      ProcessSortColumn.startTime => true,
      _ => false,
    };
    _sortedChildrenDirty |= topologyChanged || !stableSort;
    _cachedRecordsByIdentity = recordsByIdentity;
    _rebuildTreeMetrics(recordMetrics: recordMetrics);
  }

  void _rebuildTreeMetrics({required bool recordMetrics}) {
    _cachedTreeMetrics = _treeMetricsByIdentity(
      _cachedRecordsByIdentity,
      _cachedChildrenByParent,
    );
    if (recordMetrics) {
      _recordMetricHistories(_cachedRecordsByIdentity, _cachedTreeMetrics);
    }
  }

  void _rebuildSortedChildren() {
    _sortedChildrenDirty = false;
    _cachedSortedChildrenByParent = <ProcessIdentity?, List<ProcessIdentity>>{
      for (final entry in _cachedChildrenByParent.entries)
        entry.key: List<ProcessIdentity>.of(entry.value)
          ..sort(
            (left, right) => _compareIdentities(
              left,
              right,
              _cachedRecordsByIdentity,
              _cachedTreeMetrics,
            ),
          ),
    };
  }

  Map<ProcessIdentity?, List<ProcessIdentity>> _orderedChildrenForVisibleOrder(
    Map<ProcessIdentity, int> previousVisibleOrder,
  ) {
    return <ProcessIdentity?, List<ProcessIdentity>>{
      for (final entry in _cachedChildrenByParent.entries)
        entry.key: List<ProcessIdentity>.of(entry.value)
          ..sort((left, right) {
            final stableCompare = _comparePreviousVisibleOrder(
              left,
              right,
              previousVisibleOrder,
            );
            if (stableCompare != null) {
              return stableCompare;
            }
            return _compareIdentities(
              left,
              right,
              _cachedRecordsByIdentity,
              _cachedTreeMetrics,
            );
          }),
    };
  }

  Map<ProcessIdentity, _TreeMetrics> _treeMetricsByIdentity(
    Map<ProcessIdentity, ProcessRecord> recordsByIdentity,
    Map<ProcessIdentity?, List<ProcessIdentity>> childrenByParent,
  ) {
    final memo = <ProcessIdentity, _TreeMetrics>{};

    _TreeMetrics sum(ProcessIdentity identity) {
      final cached = memo[identity];
      if (cached != null) {
        return cached;
      }

      final record = recordsByIdentity[identity];
      if (record != null && _hasRustTreeMetrics(record)) {
        final total = _TreeMetrics(
          cpu: record.treeCpuUsage,
          gpu: record.treeGpuUsage,
          rssBytes: record.treeRssBytes,
          networkInBytesPerSecond: record.treeNetworkInBytesPerSecond,
          networkOutBytesPerSecond: record.treeNetworkOutBytesPerSecond,
          storageReadBytesPerSecond: record.treeStorageReadBytesPerSecond,
          storageWriteBytesPerSecond: record.treeStorageWriteBytesPerSecond,
          storageIoAvailable: record.treeStorageIoAvailable,
          descendantCount: record.descendantCount,
        );
        memo[identity] = total;
        return total;
      }
      final children = childrenByParent[identity] ?? const <ProcessIdentity>[];
      final total = children.fold<_TreeMetrics>(
        _TreeMetrics(
          cpu: record?.cpuUsage ?? 0,
          gpu: record?.gpuUsage ?? 0,
          rssBytes: record?.rssBytes ?? 0,
          networkInBytesPerSecond: record?.networkInBytesPerSecond ?? 0,
          networkOutBytesPerSecond: record?.networkOutBytesPerSecond ?? 0,
          storageReadBytesPerSecond: record?.storageReadBytesPerSecond ?? 0,
          storageWriteBytesPerSecond: record?.storageWriteBytesPerSecond ?? 0,
          storageIoAvailable: record?.storageIoAvailable ?? false,
          descendantCount: 0,
        ),
        (value, child) => value + sum(child),
      );
      memo[identity] = total;
      return total;
    }

    for (final identity in recordsByIdentity.keys) {
      sum(identity);
    }
    return memo;
  }

  bool _hasRustTreeMetrics(ProcessRecord record) {
    return record.descendantCount > 0 ||
        record.treeCpuUsage != record.cpuUsage ||
        record.treeGpuUsage != record.gpuUsage ||
        record.treeRssBytes != record.rssBytes ||
        record.treeNetworkInBytesPerSecond != record.networkInBytesPerSecond ||
        record.treeNetworkOutBytesPerSecond !=
            record.networkOutBytesPerSecond ||
        record.treeStorageReadBytesPerSecond !=
            record.storageReadBytesPerSecond ||
        record.treeStorageWriteBytesPerSecond !=
            record.storageWriteBytesPerSecond ||
        record.treeStorageIoAvailable != record.storageIoAvailable;
  }

  int _compareIdentities(
    ProcessIdentity left,
    ProcessIdentity right,
    Map<ProcessIdentity, ProcessRecord> recordsByIdentity,
    Map<ProcessIdentity, _TreeMetrics> treeMetricsByIdentity,
  ) {
    final leftRecord = recordsByIdentity[left];
    final rightRecord = recordsByIdentity[right];
    if (leftRecord == null || rightRecord == null) {
      return _compareByPid(left, right);
    }

    final base = switch (_sortColumn) {
      ProcessSortColumn.tree => _compareByPid(left, right),
      ProcessSortColumn.pid => leftRecord.pid.compareTo(rightRecord.pid),
      ProcessSortColumn.name => leftRecord.displayName.toLowerCase().compareTo(
        rightRecord.displayName.toLowerCase(),
      ),
      ProcessSortColumn.cpu => leftRecord.cpuUsage.compareTo(
        rightRecord.cpuUsage,
      ),
      ProcessSortColumn.treeCpu =>
        (treeMetricsByIdentity[left]?.cpu ?? leftRecord.cpuUsage).compareTo(
          treeMetricsByIdentity[right]?.cpu ?? rightRecord.cpuUsage,
        ),
      ProcessSortColumn.gpu => leftRecord.gpuUsage.compareTo(
        rightRecord.gpuUsage,
      ),
      ProcessSortColumn.treeGpu =>
        (treeMetricsByIdentity[left]?.gpu ?? leftRecord.gpuUsage).compareTo(
          treeMetricsByIdentity[right]?.gpu ?? rightRecord.gpuUsage,
        ),
      ProcessSortColumn.memory => leftRecord.rssBytes.compareTo(
        rightRecord.rssBytes,
      ),
      ProcessSortColumn.treeMemory =>
        (treeMetricsByIdentity[left]?.rssBytes ?? leftRecord.rssBytes)
            .compareTo(
              treeMetricsByIdentity[right]?.rssBytes ?? rightRecord.rssBytes,
            ),
      ProcessSortColumn.networkIn =>
        leftRecord.networkInBytesPerSecond.compareTo(
          rightRecord.networkInBytesPerSecond,
        ),
      ProcessSortColumn.networkOut =>
        leftRecord.networkOutBytesPerSecond.compareTo(
          rightRecord.networkOutBytesPerSecond,
        ),
      ProcessSortColumn.treeNetworkIn =>
        (treeMetricsByIdentity[left]?.networkInBytesPerSecond ??
                leftRecord.networkInBytesPerSecond)
            .compareTo(
              treeMetricsByIdentity[right]?.networkInBytesPerSecond ??
                  rightRecord.networkInBytesPerSecond,
            ),
      ProcessSortColumn.treeNetworkOut =>
        (treeMetricsByIdentity[left]?.networkOutBytesPerSecond ??
                leftRecord.networkOutBytesPerSecond)
            .compareTo(
              treeMetricsByIdentity[right]?.networkOutBytesPerSecond ??
                  rightRecord.networkOutBytesPerSecond,
            ),
      ProcessSortColumn.storageRead =>
        leftRecord.storageReadBytesPerSecond.compareTo(
          rightRecord.storageReadBytesPerSecond,
        ),
      ProcessSortColumn.storageWrite =>
        leftRecord.storageWriteBytesPerSecond.compareTo(
          rightRecord.storageWriteBytesPerSecond,
        ),
      ProcessSortColumn.treeStorageRead =>
        (treeMetricsByIdentity[left]?.storageReadBytesPerSecond ??
                leftRecord.storageReadBytesPerSecond)
            .compareTo(
              treeMetricsByIdentity[right]?.storageReadBytesPerSecond ??
                  rightRecord.storageReadBytesPerSecond,
            ),
      ProcessSortColumn.treeStorageWrite =>
        (treeMetricsByIdentity[left]?.storageWriteBytesPerSecond ??
                leftRecord.storageWriteBytesPerSecond)
            .compareTo(
              treeMetricsByIdentity[right]?.storageWriteBytesPerSecond ??
                  rightRecord.storageWriteBytesPerSecond,
            ),
      ProcessSortColumn.startTime => leftRecord.startTimeUnixMs.compareTo(
        rightRecord.startTimeUnixMs,
      ),
      ProcessSortColumn.status => leftRecord.status.name.compareTo(
        rightRecord.status.name,
      ),
      ProcessSortColumn.uid => leftRecord.uid.compareTo(rightRecord.uid),
      ProcessSortColumn.ports => _comparePorts(leftRecord, rightRecord),
    };

    final ordered = _sortDirection == ProcessSortDirection.ascending
        ? base
        : -base;
    if (ordered != 0) {
      return ordered;
    }
    return _compareByPid(left, right);
  }

  void _recordMetricHistories(
    Map<ProcessIdentity, ProcessRecord> recordsByIdentity,
    Map<ProcessIdentity, _TreeMetrics> treeMetricsByIdentity,
  ) {
    final active = recordsByIdentity.keys.toSet();
    final gap = _historyGapPending;
    _historyGapPending = false;
    var cpuScaleMax = 1.0;
    for (final identity in active) {
      final record = recordsByIdentity[identity];
      final metrics = treeMetricsByIdentity[identity];
      if (metrics == null || record == null) {
        continue;
      }
      _MetricHistory history(Map<ProcessIdentity, _MetricHistory> histories) {
        final history = histories[identity] ??= _MetricHistory();
        if (gap && history.length > 0) {
          history.addGap();
        }
        return history;
      }

      final cpuHistory = history(_cpuHistory)..add(metrics.cpu);
      if (cpuHistory.max > cpuScaleMax) {
        cpuScaleMax = cpuHistory.max;
      }
      history(_processCpuHistory).add(record.cpuUsage);
      history(_processGpuHistory).add(record.gpuUsage);
      history(_processRssHistory).add(record.rssBytes.toDouble());
      history(_processNetworkInHistory).add(record.networkInBytesPerSecond);
      history(_processNetworkOutHistory).add(record.networkOutBytesPerSecond);
      history(_processStorageReadHistory).add(record.storageReadBytesPerSecond);
      history(
        _processStorageWriteHistory,
      ).add(record.storageWriteBytesPerSecond);
      history(_gpuHistory).add(metrics.gpu);
      history(_rssHistory).add(metrics.rssBytes.toDouble());
      history(_networkInHistory).add(metrics.networkInBytesPerSecond);
      history(_networkOutHistory).add(metrics.networkOutBytesPerSecond);
      history(_storageReadHistory).add(metrics.storageReadBytesPerSecond);
      history(_storageWriteHistory).add(metrics.storageWriteBytesPerSecond);
    }

    _cpuHistory.removeWhere((identity, _) => !active.contains(identity));
    _gpuHistory.removeWhere((identity, _) => !active.contains(identity));
    _rssHistory.removeWhere((identity, _) => !active.contains(identity));
    _networkInHistory.removeWhere((identity, _) => !active.contains(identity));
    _networkOutHistory.removeWhere((identity, _) => !active.contains(identity));
    _storageReadHistory.removeWhere(
      (identity, _) => !active.contains(identity),
    );
    _storageWriteHistory.removeWhere(
      (identity, _) => !active.contains(identity),
    );
    _processCpuHistory.removeWhere((identity, _) => !active.contains(identity));
    _processGpuHistory.removeWhere((identity, _) => !active.contains(identity));
    _processRssHistory.removeWhere((identity, _) => !active.contains(identity));
    _processNetworkInHistory.removeWhere(
      (identity, _) => !active.contains(identity),
    );
    _processNetworkOutHistory.removeWhere(
      (identity, _) => !active.contains(identity),
    );
    _processStorageReadHistory.removeWhere(
      (identity, _) => !active.contains(identity),
    );
    _processStorageWriteHistory.removeWhere(
      (identity, _) => !active.contains(identity),
    );
    _cpuScaleMax = cpuScaleMax;
  }

  /// Ascending puts listeners first, by their lowest listening port, then
  /// processes with only other local ports, then processes without ports.
  static int _comparePorts(ProcessRecord left, ProcessRecord right) {
    (int, int) key(ProcessRecord record) {
      final listening = record.listeningPorts ?? const <int>[];
      if (listening.isNotEmpty) return (0, listening.first);
      final local = record.localPorts ?? const <int>[];
      return local.isNotEmpty ? (1, -local.length) : (2, 0);
    }

    final (leftGroup, leftValue) = key(left);
    final (rightGroup, rightValue) = key(right);
    final group = leftGroup.compareTo(rightGroup);
    return group != 0 ? group : leftValue.compareTo(rightValue);
  }

  int _compareByPid(ProcessIdentity left, ProcessIdentity right) {
    final pidCompare = left.pid.compareTo(right.pid);
    if (pidCompare != 0) {
      return pidCompare;
    }
    return left.startTimeUnixMs.compareTo(right.startTimeUnixMs);
  }

  bool _hasStructuralChange(ProcessSnapshot current, ProcessSnapshot next) {
    if (current.processes.isEmpty) {
      return false;
    }

    final currentTopology = current.topology;
    final nextTopology = next.topology;
    if (currentTopology != null && identical(currentTopology, nextTopology)) {
      return false;
    }
    final currentParents =
        currentTopology?.parentByIdentity ?? _parentLinks(current.processes);
    final nextParents =
        nextTopology?.parentByIdentity ?? _parentLinks(next.processes);
    if (!setEquals(currentParents.keys.toSet(), nextParents.keys.toSet())) {
      return true;
    }

    for (final entry in currentParents.entries) {
      if (nextParents[entry.key] != entry.value) {
        return true;
      }
    }
    return false;
  }

  ProcessSnapshot _mergeMetricsKeepingStructure({
    required ProcessSnapshot current,
    required ProcessSnapshot metricsSource,
  }) {
    final sourceByIdentity = _recordsByIdentity(metricsSource.processes);
    return ProcessSnapshot(
      generatedAtUnixMs: metricsSource.generatedAtUnixMs,
      platform: metricsSource.platform,
      processes: current.processes.map((record) {
        final updated = sourceByIdentity[record.identity];
        if (updated == null) return record;
        return updated.ppid == record.ppid
            ? updated
            : updated.copyWith(ppid: record.ppid);
      }).toList(),
      error: metricsSource.error,
      topology:
          current.topology ??
          ProcessTopology(parents: _parentLinks(current.processes)),
    );
  }

  Map<ProcessIdentity, ProcessRecord> _recordsByIdentity(
    Iterable<ProcessRecord> records,
  ) {
    return <ProcessIdentity, ProcessRecord>{
      for (final record in records) record.identity: record,
    };
  }

  Map<ProcessIdentity, ProcessIdentity?> _parentLinks(
    Iterable<ProcessRecord> records,
  ) {
    final recordsByIdentity = _recordsByIdentity(records);
    final pidToIdentity = <int, ProcessIdentity>{};
    for (final identity in recordsByIdentity.keys) {
      final existing = pidToIdentity[identity.pid];
      final existingTerminated =
          existing != null &&
          _changeMarkers[existing] == ProcessChangeMarker.terminated;
      final identityTerminated =
          _changeMarkers[identity] == ProcessChangeMarker.terminated;
      if (existing == null || (existingTerminated && !identityTerminated)) {
        pidToIdentity[identity.pid] = identity;
      }
    }

    return <ProcessIdentity, ProcessIdentity?>{
      for (final record in recordsByIdentity.values)
        record.identity: record.ppid == record.pid
            ? null
            : pidToIdentity[record.ppid],
    };
  }

  void _selectVisibleOffset(int offset) {
    final rows = _tree.value.visibleRows
        .where((row) => !row.isTerminated)
        .toList(growable: false);
    if (rows.isEmpty) {
      return;
    }

    final selected = _selectedIdentity;
    final currentIndex = selected == null
        ? -1
        : rows.indexWhere((row) => row.identity == selected);
    final nextIndex = (currentIndex + offset).clamp(0, rows.length - 1);
    _selectIdentity(rows[nextIndex].identity);
  }

  void _selectTreeSearchOffset(int offset) {
    if (_treeSearchQuery.isEmpty) {
      return;
    }

    final rows = _tree.value.visibleRows
        .where((row) => row.matchesTreeSearch && !row.isTerminated)
        .toList(growable: false);
    if (rows.isEmpty) {
      return;
    }

    final selected = _selectedIdentity;
    final currentIndex = selected == null
        ? -1
        : rows.indexWhere((row) => row.identity == selected);
    final nextIndex = currentIndex < 0
        ? (offset < 0 ? rows.length - 1 : 0)
        : (currentIndex + offset) % rows.length;
    _selectIdentity(rows[nextIndex].identity);
  }

  void _selectIdentity(ProcessIdentity identity) {
    if (_selectedIdentity == identity) {
      return;
    }

    _selectedIdentity = identity;
    _selectedProcessDetail = null;
    _inspectorDetailGeneration++;
    _publishTree(recordMetrics: false);
    unawaited(_refreshInspectorDetail());
  }

  Future<void> _refreshInspectorDetail() async {
    if (_loadedSnapshotPath.value != null) {
      return;
    }
    final identity = _selectedIdentity;
    if (identity == null || !_cachedRecordsByIdentity.containsKey(identity)) {
      return;
    }

    final generation = _inspectorDetailGeneration;
    try {
      final detail = await source.fetchDetail(identity);
      if (_selectedIdentity == identity &&
          _inspectorDetailGeneration == generation) {
        _selectedProcessDetail = detail;
        _publishInspector();
      }
    } on Object catch (error, stackTrace) {
      _log.fine(
        'Failed to refresh process inspector detail.',
        error,
        stackTrace,
      );
    }
  }

  ProcessTreeRow? _selectedVisibleRow() {
    final selected = _selectedIdentity;
    if (selected == null) {
      return null;
    }
    for (final row in _tree.value.visibleRows) {
      if (row.identity == selected) {
        return row;
      }
    }
    return null;
  }

  void _pruneRowCache(Set<ProcessIdentity> displayIdentities) {}

  Set<ProcessIdentity> _subtreeIdentities({required ProcessIdentity root}) {
    final identities = <ProcessIdentity>{};
    void visit(ProcessIdentity identity) {
      if (!identities.add(identity)) {
        return;
      }
      for (final child
          in _cachedChildrenByParent[identity] ?? const <ProcessIdentity>[]) {
        visit(child);
      }
    }

    visit(root);
    return identities;
  }

  void _handleSettingsChanged() {
    final settings = settingsService;
    if (settings == null) {
      return;
    }
    final currentSettings = settings.settings.value;
    final sortChanged =
        _sortColumn != currentSettings.processSortColumn ||
        _sortDirection != currentSettings.processSortDirection;
    final treeSearchColumnsChanged = !setEquals(
      _treeSearchColumnIds,
      _visibleStableTreeSearchColumnIds(currentSettings.visibleColumns),
    );
    _applySettings(currentSettings);
    if (sortChanged) {
      _rebuildSortedChildren();
    }
    if (sortChanged ||
        (treeSearchColumnsChanged && _treeSearchQuery.isNotEmpty)) {
      _publishTree(allowInteractionOrderLock: false, recordMetrics: false);
    }
  }

  void _applySettings(AppSettings settings) {
    _autoRefresh = true;
    _sortColumn = settings.processSortColumn;
    _sortDirection = settings.processSortDirection;
    _treeSearchColumnIds = _visibleStableTreeSearchColumnIds(
      settings.visibleColumns,
    );
    _configureRefreshTimer(settings.pollingIntervalMs);
    _configureInspectorDetailTimer();
  }

  /// Selects the source cadence: paused for a loaded snapshot or while the
  /// window resizes, live while visible, background while hidden.
  void _configureRefreshTimer(int intervalMs) {
    if (_disposed || !_autoRefresh) {
      return;
    }
    final ProcessCadence cadence;
    if (_loadedSnapshotPath.value != null || _windowResizing) {
      cadence = ProcessCadence.paused;
    } else if (_active) {
      cadence = ProcessCadence.live(Duration(milliseconds: intervalMs));
    } else {
      cadence = _backgroundCadence;
    }
    unawaited(source.setCadence(cadence));
  }

  void _configureInspectorDetailTimer() {
    _inspectorDetailTimer?.cancel();
    if (_disposed || _loadedSnapshotPath.value != null || !_active) {
      return;
    }
    _inspectorDetailTimer = Timer.periodic(
      const Duration(milliseconds: 2000),
      (_) => _refreshInspectorDetail(),
    );
  }
}

class _TreeBuildResult {
  const _TreeBuildResult({
    required this.visibleRows,
    required this.displayIdentities,
  });

  final List<ProcessTreeRow> visibleRows;
  final Set<ProcessIdentity> displayIdentities;
}

class _ProcessSearchMatcher {
  _ProcessSearchMatcher({
    required String query,
    required ProcessSearchOptions options,
  }) : _query = options.matchCase ? query : query.toLowerCase(),
       _options = options,
       _wholeWordPattern = options.wholeWord && query.isNotEmpty
           ? RegExp(
               r'(^|[^\w])' + RegExp.escape(query) + r'($|[^\w])',
               caseSensitive: options.matchCase,
             )
           : null;

  final String _query;
  final ProcessSearchOptions _options;
  final RegExp? _wholeWordPattern;

  bool get hasQuery => _query.isNotEmpty;

  bool matchesAny(Iterable<String> fields) {
    return fields.any(matches);
  }

  bool matches(String value) {
    if (!hasQuery) {
      return true;
    }

    final pattern = _wholeWordPattern;
    if (pattern != null) {
      return pattern.hasMatch(value);
    }

    final candidate = _options.matchCase ? value : value.toLowerCase();
    return candidate.contains(_query);
  }
}

class _TreeMetrics {
  const _TreeMetrics({
    required this.cpu,
    required this.gpu,
    required this.rssBytes,
    required this.networkInBytesPerSecond,
    required this.networkOutBytesPerSecond,
    required this.storageReadBytesPerSecond,
    required this.storageWriteBytesPerSecond,
    required this.storageIoAvailable,
    required this.descendantCount,
  });

  final double cpu;
  final double gpu;
  final int rssBytes;
  final double networkInBytesPerSecond;
  final double networkOutBytesPerSecond;
  final double storageReadBytesPerSecond;
  final double storageWriteBytesPerSecond;
  final bool storageIoAvailable;
  final int descendantCount;

  _TreeMetrics operator +(_TreeMetrics other) {
    return _TreeMetrics(
      cpu: cpu + other.cpu,
      gpu: gpu + other.gpu,
      rssBytes: rssBytes + other.rssBytes,
      networkInBytesPerSecond:
          networkInBytesPerSecond + other.networkInBytesPerSecond,
      networkOutBytesPerSecond:
          networkOutBytesPerSecond + other.networkOutBytesPerSecond,
      storageReadBytesPerSecond:
          storageReadBytesPerSecond + other.storageReadBytesPerSecond,
      storageWriteBytesPerSecond:
          storageWriteBytesPerSecond + other.storageWriteBytesPerSecond,
      storageIoAvailable: storageIoAvailable || other.storageIoAvailable,
      descendantCount: descendantCount + other.descendantCount + 1,
    );
  }
}

/// Fixed-capacity ring buffer for a per-process metric history.
///
/// Replaces the previous implementation, which allocated a brand new
/// `List<double>` (spreading up to 60 elements) for every process for every
/// metric on every refresh. That allocation churn dominated CPU. Appends here
/// are O(1); [asList] is only called for the currently visible rows at publish
/// time, and [max] is maintained incrementally (recomputed only when the
/// current maximum is evicted, which is rare).
class _MetricHistory {
  _MetricHistory();

  static const int capacity = 60;

  final List<double> _buffer = List<double>.filled(capacity, 0.0);
  int _head = 0;
  int _count = 0;
  double _max = 0.0;
  List<double>? _snapshot;

  int get length => _count;
  double get max => _max;

  /// Marks an outage: charts leave a gap instead of joining across it.
  void addGap() => add(double.nan);

  void add(double value) {
    _snapshot = null;
    if (_count < capacity) {
      _buffer[_head] = value;
      if (value > _max) {
        _max = value;
      }
      _head = (_head + 1) % capacity;
      _count++;
      return;
    }

    final evicted = _buffer[_head];
    _buffer[_head] = value;
    _head = (_head + 1) % capacity;
    if (value >= _max) {
      _max = value;
    } else if (evicted >= _max) {
      // Samples are never negative; a gap's NaN never compares greater.
      var nextMax = 0.0;
      for (var i = 0; i < capacity; i++) {
        final candidate = _buffer[i];
        if (candidate > nextMax) {
          nextMax = candidate;
        }
      }
      _max = nextMax;
    }
  }

  List<double> asList() {
    final cached = _snapshot;
    if (cached != null) {
      return cached;
    }
    if (_count == 0) {
      return const <double>[];
    }
    final result = List<double>.filled(_count, 0.0);
    final start = (_head - _count + capacity) % capacity;
    for (var i = 0; i < _count; i++) {
      result[i] = _buffer[(start + i) % capacity];
    }
    return _snapshot = UnmodifiableListView(result);
  }
}
