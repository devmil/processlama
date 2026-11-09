import 'dart:typed_data';

import '../models/models.dart';

abstract interface class SnapshotRepository {
  Future<String> saveSnapshot(ProcessSnapshot snapshot);

  /// Saves a snapshot of a remote host with the icons its rows reference.
  Future<String> saveRemoteSnapshot(
    ProcessSnapshot snapshot, {
    required SnapshotHost host,
    required Map<String, Uint8List> icons,
  });

  /// The icons a saved snapshot embeds, by SHA-256.
  Future<Map<String, Uint8List>> importSnapshotIcons(String path);

  Future<List<SnapshotEntry>> listSnapshots();

  Future<ProcessSnapshot> importSnapshot(String path);

  Future<String> saveSnapshotDocument(String path);

  Future<void> exportSnapshotToPath(SnapshotEntry entry, String targetPath);

  Future<void> renameSnapshot(SnapshotEntry entry, String name);

  Future<void> deleteSnapshot(SnapshotEntry entry);
}
