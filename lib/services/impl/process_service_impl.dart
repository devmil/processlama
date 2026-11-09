import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../process_service.dart';
import '../repository_operation_tracker.dart';
import '../settings_service.dart';
import 'local_process_source.dart';
import '../process_session.dart';
import '../process_source.dart';

/// [ProcessService] over the active tab's [ProcessSession].
///
/// Listenables stay the same objects across tab switches: they follow the
/// active session and notify when it changes.
class ProcessServiceImpl implements ProcessService {
  /// A service over a single local session, sampling [processRepository].
  factory ProcessServiceImpl({
    required ProcessRepository processRepository,
    required SnapshotRepository snapshotRepository,
    required RepositoryOperationTracker repositoryOperationTracker,
    SettingsService? settingsService,
    TargetPlatform? platform,
  }) {
    final session = ProcessSession(
      source: LocalProcessSource(
        processRepository: processRepository,
        repositoryOperationTracker: repositoryOperationTracker,
        platform: platform,
      ),
      snapshotRepository: snapshotRepository,
      repositoryOperationTracker: repositoryOperationTracker,
      settingsService: settingsService,
    );
    return ProcessServiceImpl.overSessions(
      activeSession: ValueNotifier<ProcessSession>(session),
      initializer: session.initialize,
    );
  }

  /// A service over whichever session [activeSession] names. [initializer]
  /// runs once from [initialize].
  ProcessServiceImpl.overSessions({
    required ValueListenable<ProcessSession> activeSession,
    required this._initializer,
  }) : _activeSession = activeSession {
    _snapshot = _Forwarding(activeSession, (session) => session.snapshot);
    _tree = _Forwarding(activeSession, (session) => session.tree);
    _selectedIdentity = _Forwarding(
      activeSession,
      (session) => session.selectedIdentity,
    );
    _inspector = _Forwarding(activeSession, (session) => session.inspector);
    _filter = _Forwarding(activeSession, (session) => session.filter);
    _searchOptions = _Forwarding(
      activeSession,
      (session) => session.searchOptions,
    );
    _savedSnapshots = _Forwarding(
      activeSession,
      (session) => session.savedSnapshots,
    );
    _loadedSnapshotPath = _Forwarding(
      activeSession,
      (session) => session.loadedSnapshotPath,
    );
    _sourceState = _Forwarding(activeSession, (session) => session.sourceState);
    _hostCapabilities = _Forwarding(
      activeSession,
      (session) => session.hostCapabilities,
    );
  }

  final ValueListenable<ProcessSession> _activeSession;
  final Future<void> Function() _initializer;
  Future<void>? _initialization;
  late final _Forwarding<ProcessSnapshot> _snapshot;
  late final _Forwarding<ProcessTreeView> _tree;
  late final _Forwarding<ProcessIdentity?> _selectedIdentity;
  late final _Forwarding<ProcessInspectorView> _inspector;
  late final _Forwarding<String> _filter;
  late final _Forwarding<ProcessSearchOptions> _searchOptions;
  late final _Forwarding<List<SnapshotEntry>> _savedSnapshots;
  late final _Forwarding<String?> _loadedSnapshotPath;
  late final _Forwarding<ProcessSourceState> _sourceState;
  late final _Forwarding<HostCapabilities> _hostCapabilities;

  ProcessSession get _session => _activeSession.value;

  /// The session currently shown.
  ValueListenable<ProcessSession> get activeSession => _activeSession;

  @override
  ValueListenable<ProcessSnapshot> get snapshot => _snapshot;

  @override
  ValueListenable<ProcessTreeView> get tree => _tree;

  @override
  ValueListenable<ProcessIdentity?> get selectedIdentity => _selectedIdentity;

  @override
  ValueListenable<ProcessInspectorView> get inspector => _inspector;

  @override
  ValueListenable<String> get filter => _filter;

  @override
  ValueListenable<ProcessSearchOptions> get searchOptions => _searchOptions;

  @override
  ValueListenable<List<SnapshotEntry>> get savedSnapshots => _savedSnapshots;

  @override
  ValueListenable<String?> get loadedSnapshotPath => _loadedSnapshotPath;

  @override
  ProcessSourceDescriptor get sourceDescriptor => _session.sourceDescriptor;

  @override
  ValueListenable<ProcessSourceState> get sourceState => _sourceState;

  @override
  ValueListenable<HostCapabilities> get hostCapabilities => _hostCapabilities;

  @override
  Future<void> initialize() => _initialization ??= _initializer();

  @override
  Future<void> refresh() => _session.refresh();

  @override
  Future<void> takeSnapshot() => _session.takeSnapshot();

  @override
  Future<List<SnapshotEntry>> listSnapshots() => _session.listSnapshots();

  @override
  Future<void> showLiveSnapshot() => _session.showLiveSnapshot();

  @override
  Future<void> loadSnapshot(String path) => _session.loadSnapshot(path);

  @override
  Future<void> exportSnapshot(SnapshotEntry entry, String targetPath) =>
      _session.exportSnapshot(entry, targetPath);

  @override
  Future<void> renameSnapshot(SnapshotEntry entry, String name) =>
      _session.renameSnapshot(entry, name);

  @override
  Future<void> deleteSnapshot(SnapshotEntry entry) =>
      _session.deleteSnapshot(entry);

  @override
  Future<void> terminateProcess(ProcessIdentity identity) =>
      _session.terminateProcess(identity);

  @override
  Future<void> killProcess(ProcessIdentity identity) =>
      _session.killProcess(identity);

  @override
  Future<void> suspendProcess(ProcessIdentity identity) =>
      _session.suspendProcess(identity);

  @override
  Future<void> resumeProcess(ProcessIdentity identity) =>
      _session.resumeProcess(identity);

  @override
  void setFilter(String value) => _session.setFilter(value);

  @override
  void setSearchAspect(ProcessSearchAspect aspect) =>
      _session.setSearchAspect(aspect);

  @override
  void showPort(int port) => _session.showPort(port);

  @override
  void setSearchMatchCase(bool value) => _session.setSearchMatchCase(value);

  @override
  void setSearchWholeWord(bool value) => _session.setSearchWholeWord(value);

  @override
  void setTreeSearch(String value) => _session.setTreeSearch(value);

  @override
  void selectNextTreeSearchMatch() => _session.selectNextTreeSearchMatch();

  @override
  void selectPreviousTreeSearchMatch() =>
      _session.selectPreviousTreeSearchMatch();

  @override
  void toggleExpansion(ProcessIdentity identity) =>
      _session.toggleExpansion(identity);

  @override
  void selectProcess(ProcessIdentity identity) =>
      _session.selectProcess(identity);

  @override
  void selectNextVisible() => _session.selectNextVisible();

  @override
  void selectPreviousVisible() => _session.selectPreviousVisible();

  @override
  void markTreeInteraction() => _session.markTreeInteraction();

  @override
  void expandSelected() => _session.expandSelected();

  @override
  void collapseSelected() => _session.collapseSelected();

  @override
  void focusSelectedSubtree() => _session.focusSelectedSubtree();

  @override
  void focusSubtree(ProcessIdentity identity) =>
      _session.focusSubtree(identity);

  @override
  void clearSubtreeFocus() => _session.clearSubtreeFocus();

  @override
  void popSubtreeFocus() => _session.popSubtreeFocus();

  @override
  void expandSelectedSubtree() => _session.expandSelectedSubtree();

  @override
  void collapseSelectedSubtree() => _session.collapseSelectedSubtree();

  @override
  void sortBy(ProcessSortColumn column) => _session.sortBy(column);

  @override
  void togglePin(ProcessIdentity identity) => _session.togglePin(identity);

  @override
  void setTreeHovering(bool hovering) => _session.setTreeHovering(hovering);

  @override
  void setTreeContextMenuOpen(bool open) =>
      _session.setTreeContextMenuOpen(open);

  @override
  void setModalOverlayOpen(bool open) => _session.setModalOverlayOpen(open);

  @override
  void setWindowResizing(bool resizing) => _session.setWindowResizing(resizing);

  @override
  void setFrozen(bool frozen) => _session.setFrozen(frozen);

  @override
  void toggleFrozen() => _session.toggleFrozen();
}

/// A listenable that follows one listenable of the active session.
class _Forwarding<T> extends ChangeNotifier implements ValueListenable<T> {
  _Forwarding(this._sessions, this._select)
    : _bound = _select(_sessions.value) {
    _bound.addListener(notifyListeners);
    _sessions.addListener(_rebind);
  }

  final ValueListenable<ProcessSession> _sessions;
  final ValueListenable<T> Function(ProcessSession session) _select;
  ValueListenable<T> _bound;

  @override
  T get value => _bound.value;

  void _rebind() {
    final next = _select(_sessions.value);
    if (identical(next, _bound)) {
      return;
    }
    _bound.removeListener(notifyListeners);
    _bound = next;
    _bound.addListener(notifyListeners);
    notifyListeners();
  }
}
