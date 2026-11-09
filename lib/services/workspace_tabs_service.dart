import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'process_session.dart';

/// The most remote tabs open at once.
const maximumRemoteTabs = 16;

/// The order and active tab of the main window, restored across launches.
@immutable
class WorkspaceTabsLayout {
  const WorkspaceTabsLayout({required this.remoteTabs, this.activeTab});

  static const empty = WorkspaceTabsLayout(remoteTabs: <RemoteWorkspaceTab>[]);

  /// Remote tabs in display order; the local tab always comes first.
  final List<RemoteWorkspaceTab> remoteTabs;
  final WorkspaceTab? activeTab;

  @override
  bool operator ==(Object other) =>
      other is WorkspaceTabsLayout &&
      listEquals(other.remoteTabs, remoteTabs) &&
      other.activeTab == activeTab;

  @override
  int get hashCode => Object.hash(Object.hashAll(remoteTabs), activeTab);
}

/// Persists [WorkspaceTabsLayout]. The settings owner implements it.
abstract interface class WorkspaceTabsStore {
  WorkspaceTabsLayout read();

  Future<void> write(WorkspaceTabsLayout layout);
}

/// Keeps the layout in memory only.
final class MemoryWorkspaceTabsStore implements WorkspaceTabsStore {
  WorkspaceTabsLayout _layout = WorkspaceTabsLayout.empty;

  @override
  WorkspaceTabsLayout read() => _layout;

  @override
  Future<void> write(WorkspaceTabsLayout layout) async => _layout = layout;
}

/// Owns the main window's tabs and one [ProcessSession] per tab.
///
/// The local tab is always first and cannot be closed. Sessions of hidden
/// tabs stay alive at the background cadence so their selection, expansion
/// and freeze state survive a switch.
abstract interface class WorkspaceTabsService {
  ValueListenable<List<WorkspaceTab>> get tabs;

  ValueListenable<WorkspaceTab> get activeTab;

  ValueListenable<ProcessSession> get activeSession;

  /// The session of an open [tab], or null.
  ProcessSession? sessionFor(WorkspaceTab tab);

  /// Creates the local session and restores remote tabs.
  Future<void> initialize();

  /// Opens [tab] (or selects it when already open). Returns false when the
  /// remote tab limit is reached or the tab has no session.
  Future<bool> openTab(RemoteWorkspaceTab tab, {bool activate = true});

  /// Closes [tab] and disposes its session and source. The local tab stays.
  Future<void> closeTab(WorkspaceTab tab);

  void activate(WorkspaceTab tab);

  /// Selects the tab at [index], if any.
  void activateIndex(int index);

  /// Selects the next (or with [backwards] the previous) tab, wrapping.
  void cycle({bool backwards = false});

  /// Moves the tab at [oldIndex] to [newIndex]; both count the local tab,
  /// which never moves.
  void reorder(int oldIndex, int newIndex);

  Future<void> dispose();
}
