import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'process_source.dart';

abstract interface class ProcessService {
  ValueListenable<ProcessSnapshot> get snapshot;
  ValueListenable<ProcessTreeView> get tree;
  ValueListenable<ProcessIdentity?> get selectedIdentity;
  ValueListenable<ProcessInspectorView> get inspector;
  ValueListenable<String> get filter;
  ValueListenable<ProcessSearchOptions> get searchOptions;
  ValueListenable<List<SnapshotEntry>> get savedSnapshots;
  ValueListenable<String?> get loadedSnapshotPath;

  /// Where the samples come from: this computer or a remote host.
  ProcessSourceDescriptor get sourceDescriptor;

  /// Whether the samples are live, stale or failed.
  ValueListenable<ProcessSourceState> get sourceState;

  /// What the sampled host offers.
  ValueListenable<HostCapabilities> get hostCapabilities;
  Future<void> initialize();
  Future<void> refresh();
  Future<void> takeSnapshot();
  Future<List<SnapshotEntry>> listSnapshots();
  Future<void> showLiveSnapshot();
  Future<void> loadSnapshot(String path);
  Future<void> exportSnapshot(SnapshotEntry entry, String targetPath);
  Future<void> renameSnapshot(SnapshotEntry entry, String name);
  Future<void> deleteSnapshot(SnapshotEntry entry);
  Future<void> terminateProcess(ProcessIdentity identity);
  Future<void> killProcess(ProcessIdentity identity);
  Future<void> suspendProcess(ProcessIdentity identity);
  Future<void> resumeProcess(ProcessIdentity identity);
  void setFilter(String value);
  void setSearchAspect(ProcessSearchAspect aspect);

  /// Filters the tree to the processes using [port].
  void showPort(int port);
  void setSearchMatchCase(bool value);
  void setSearchWholeWord(bool value);
  void setTreeSearch(String value);
  void selectNextTreeSearchMatch();
  void selectPreviousTreeSearchMatch();
  void toggleExpansion(ProcessIdentity identity);
  void selectProcess(ProcessIdentity identity);
  void selectNextVisible();
  void selectPreviousVisible();
  void markTreeInteraction();
  void expandSelected();
  void collapseSelected();
  void focusSelectedSubtree();
  void focusSubtree(ProcessIdentity identity);
  void clearSubtreeFocus();
  void popSubtreeFocus();
  void expandSelectedSubtree();
  void collapseSelectedSubtree();
  void sortBy(ProcessSortColumn column);
  void togglePin(ProcessIdentity identity);
  void setTreeHovering(bool hovering);
  void setTreeContextMenuOpen(bool open);
  void setModalOverlayOpen(bool open);
  void setWindowResizing(bool resizing);
  void setFrozen(bool frozen);
  void toggleFrozen();
}
