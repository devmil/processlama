import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../../models/models.dart';
import '../process_session.dart';
import '../process_session_factory.dart';
import '../workspace_tabs_service.dart';

class WorkspaceTabsServiceImpl implements WorkspaceTabsService {
  WorkspaceTabsServiceImpl({
    required this.sessionFactory,
    WorkspaceTabsStore? store,
  }) : store = store ?? MemoryWorkspaceTabsStore();

  static final _log = Logger('WorkspaceTabsService');

  final ProcessSessionFactory sessionFactory;
  final WorkspaceTabsStore store;

  final ValueNotifier<List<WorkspaceTab>> _tabs = ValueNotifier(
    const <WorkspaceTab>[WorkspaceTab.local],
  );
  final ValueNotifier<WorkspaceTab> _activeTab = ValueNotifier(
    WorkspaceTab.local,
  );
  late final ValueNotifier<ProcessSession> _activeSession;
  final Map<WorkspaceTab, ProcessSessionHandle> _handles = {};
  Future<void>? _initialization;
  var _disposed = false;

  /// The local session, created eagerly so [activeSession] always has a
  /// value.
  late final ProcessSessionHandle _local = _createLocal();

  ProcessSessionHandle _createLocal() {
    final handle = sessionFactory.create(WorkspaceTab.local);
    _handles[WorkspaceTab.local] = handle;
    _activeSession = ValueNotifier(handle.session);
    return handle;
  }

  @override
  ValueListenable<List<WorkspaceTab>> get tabs => _tabs;

  @override
  ValueListenable<WorkspaceTab> get activeTab => _activeTab;

  @override
  ValueListenable<ProcessSession> get activeSession {
    _local;
    return _activeSession;
  }

  @override
  ProcessSession? sessionFor(WorkspaceTab tab) {
    _local;
    return _handles[tab]?.session;
  }

  @override
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    await _local.session.initialize();
    final layout = store.read();
    for (final tab in layout.remoteTabs.take(maximumRemoteTabs)) {
      await _open(tab, persist: false);
    }
    final restoredActive = layout.activeTab;
    if (restoredActive != null && _handles.containsKey(restoredActive)) {
      _select(restoredActive);
    }
  }

  @override
  Future<bool> openTab(RemoteWorkspaceTab tab, {bool activate = true}) async {
    _local;
    if (_disposed) {
      return false;
    }
    if (!_handles.containsKey(tab)) {
      if (_tabs.value.length - 1 >= maximumRemoteTabs) {
        return false;
      }
      if (!await _open(tab, persist: true)) {
        return false;
      }
    }
    if (activate) {
      _select(tab);
      _persist();
    }
    return true;
  }

  Future<bool> _open(RemoteWorkspaceTab tab, {required bool persist}) async {
    final ProcessSessionHandle handle;
    try {
      handle = sessionFactory.create(tab);
    } on ProcessSessionUnavailable {
      _log.info('workspace_tab_unavailable');
      return false;
    }
    handle.session.setActive(false);
    _handles[tab] = handle;
    _tabs.value = List.unmodifiable([..._tabs.value, tab]);
    await handle.session.initialize();
    if (persist) {
      _persist();
    }
    return true;
  }

  @override
  Future<void> closeTab(WorkspaceTab tab) async {
    if (tab is! RemoteWorkspaceTab) {
      return;
    }
    final handle = _handles.remove(tab);
    if (handle == null) {
      return;
    }
    final order = _tabs.value;
    final index = order.indexOf(tab);
    _tabs.value = List.unmodifiable(order.where((open) => open != tab));
    if (_activeTab.value == tab) {
      final remaining = _tabs.value;
      _select(remaining[(index - 1).clamp(0, remaining.length - 1)]);
    }
    _persist();
    await handle.dispose();
  }

  @override
  void activate(WorkspaceTab tab) {
    _local;
    if (!_handles.containsKey(tab) || _activeTab.value == tab) {
      return;
    }
    _select(tab);
    _persist();
  }

  @override
  void activateIndex(int index) {
    final order = tabs.value;
    if (index >= 0 && index < order.length) {
      activate(order[index]);
    }
  }

  @override
  void cycle({bool backwards = false}) {
    final order = tabs.value;
    if (order.length < 2) {
      return;
    }
    final current = order.indexOf(_activeTab.value);
    final next = (current + (backwards ? -1 : 1)) % order.length;
    activate(order[next < 0 ? next + order.length : next]);
  }

  @override
  void reorder(int oldIndex, int newIndex) {
    final order = [...tabs.value];
    if (oldIndex <= 0 || oldIndex >= order.length) {
      return;
    }
    final target = newIndex.clamp(1, order.length - 1);
    if (target == oldIndex) {
      return;
    }
    final moved = order.removeAt(oldIndex);
    order.insert(target, moved);
    _tabs.value = List.unmodifiable(order);
    _persist();
  }

  void _select(WorkspaceTab tab) {
    final next = _handles[tab];
    if (next == null) {
      return;
    }
    final previous = _handles[_activeTab.value];
    _activeTab.value = tab;
    previous?.session.setActive(false);
    next.session.setActive(true);
    _activeSession.value = next.session;
  }

  void _persist() {
    if (_disposed) {
      return;
    }
    final layout = WorkspaceTabsLayout(
      remoteTabs: List.unmodifiable(
        _tabs.value.whereType<RemoteWorkspaceTab>(),
      ),
      activeTab: _activeTab.value,
    );
    unawaited(
      store.write(layout).catchError((Object error) {
        _log.warning('workspace_tabs_save_failed');
      }),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final handles = [..._handles.values];
    _handles.clear();
    for (final handle in handles.reversed) {
      await handle.dispose();
    }
  }
}
