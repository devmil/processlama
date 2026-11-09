import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../models/models.dart';
import '../snapshot_repository.dart';

class FileSnapshotRepository implements SnapshotRepository {
  FileSnapshotRepository({Directory? baseDirectory})
    : _baseDirectoryOverride = baseDirectory;

  static const String _extension = '.processlama-snapshot.json';

  final Directory? _baseDirectoryOverride;
  Directory? _baseDirectory;

  @override
  Future<String> saveSnapshot(ProcessSnapshot snapshot) async {
    final directory = await _snapshotDirectory();
    final exportedAt = DateTime.now().millisecondsSinceEpoch;
    final document = SnapshotDocument(
      schemaVersion: 1,
      exportedAtUnixMs: exportedAt,
      source: 'ProcessLama',
      snapshot: snapshot,
    );
    final file = File('${directory.path}/snapshot-$exportedAt$_extension');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(document.toJson()),
      flush: true,
    );
    return file.path;
  }

  @override
  Future<String> saveRemoteSnapshot(
    ProcessSnapshot snapshot, {
    required SnapshotHost host,
    required Map<String, Uint8List> icons,
  }) async {
    final directory = await _snapshotDirectory();
    final file = await _nextSnapshotFile(directory);
    final document = SnapshotDocument(
      schemaVersion: SnapshotDocument.currentSchemaVersion,
      exportedAtUnixMs: DateTime.now().millisecondsSinceEpoch,
      source: 'ProcessLama',
      host: host,
      icons: {
        for (final MapEntry(:key, :value) in icons.entries)
          key: base64.encode(value),
      },
      snapshot: snapshot,
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(document.toJson()),
      flush: true,
    );
    return file.path;
  }

  @override
  Future<Map<String, Uint8List>> importSnapshotIcons(String path) async {
    final payload = jsonDecode(await File(path).readAsString());
    if (payload is! Map<String, Object?>) return const {};
    final icons = <String, Uint8List>{};
    for (final MapEntry(:key, :value) in SnapshotDocument.fromJson(
      payload,
    ).icons.entries) {
      try {
        icons[key] = base64.decode(value);
      } on FormatException {
        continue;
      }
    }
    return icons;
  }

  @override
  Future<List<SnapshotEntry>> listSnapshots() async {
    final directory = await _snapshotDirectory();
    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith(_extension))
        .toList();
    files.sort((left, right) => right.path.compareTo(left.path));

    final entries = <SnapshotEntry>[];
    for (final file in files) {
      try {
        final payload = jsonDecode(await file.readAsString());
        if (payload is! Map<String, Object?>) {
          continue;
        }
        final document = SnapshotDocument.fromJson(payload);
        entries.add(
          SnapshotEntry(
            path: file.path,
            generatedAtUnixMs: document.snapshot.generatedAtUnixMs,
            processCount: document.snapshot.processes.length,
            platform: document.snapshot.platform,
            name: document.displayName,
          ),
        );
      } on Object {
        continue;
      }
    }
    return entries;
  }

  @override
  Future<ProcessSnapshot> importSnapshot(String path) async {
    final payload = jsonDecode(await File(path).readAsString());
    if (payload is! Map<String, Object?>) {
      throw const FormatException('Snapshot document must be a JSON object.');
    }
    return SnapshotDocument.fromJson(payload).snapshot;
  }

  @override
  Future<String> saveSnapshotDocument(String path) async {
    final payload = jsonDecode(await File(path).readAsString());
    if (payload is! Map<String, Object?>) {
      throw const FormatException('Snapshot document must be a JSON object.');
    }
    final document = SnapshotDocument.fromJson(payload);
    final directory = await _snapshotDirectory();
    final file = await _nextSnapshotFile(directory);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(document.toJson()),
      flush: true,
    );
    return file.path;
  }

  @override
  Future<void> exportSnapshotToPath(
    SnapshotEntry entry,
    String targetPath,
  ) async {
    final sourceFile = File(entry.path);
    await sourceFile.copy(targetPath);
  }

  @override
  Future<void> renameSnapshot(SnapshotEntry entry, String name) async {
    final file = File(entry.path);
    final payload = jsonDecode(await file.readAsString());
    if (payload is! Map<String, Object?>) {
      throw const FormatException('Snapshot document must be a JSON object.');
    }
    final document = SnapshotDocument.fromJson(payload);
    final trimmedName = name.trim();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        document
            .copyWith(displayName: trimmedName.isEmpty ? null : trimmedName)
            .toJson(),
      ),
      flush: true,
    );
  }

  @override
  Future<void> deleteSnapshot(SnapshotEntry entry) async {
    final file = File(entry.path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Directory> _snapshotDirectory() async {
    final base =
        _baseDirectoryOverride ??
        (_baseDirectory ??= await getApplicationSupportDirectory());
    final directory = Directory('${base.path}/snapshots');
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> _nextSnapshotFile(Directory directory) async {
    while (true) {
      final exportedAt = DateTime.now().millisecondsSinceEpoch;
      final file = File('${directory.path}/snapshot-$exportedAt$_extension');
      if (!await file.exists()) {
        return file;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }
}
