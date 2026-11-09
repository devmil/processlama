import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/impl/file_snapshot_repository.dart';

void main() {
  test('saves and lists snapshot documents', () async {
    final directory = await Directory.systemTemp.createTemp(
      'processlama_snapshot_test',
    );
    addTearDown(() => directory.delete(recursive: true));

    final repository = FileSnapshotRepository(baseDirectory: directory);
    final snapshot = ProcessSnapshot(
      generatedAtUnixMs: 42,
      platform: 'test',
      processes: [
        ProcessRecord(
          pid: 1,
          ppid: 0,
          uid: 501,
          user: 'test',
          status: ProcessStatus.running,
          rssBytes: 1024,
          virtualMemoryBytes: 1024,
          cpuTimeNanos: 0,
          threadCount: 0,
          openFileCount: 0,
          nice: 0,
          priority: 0,
          cpuUsage: 0,
          gpuUsage: 0,
          networkInBytesPerSecond: 0,
          networkOutBytesPerSecond: 0,
          totalNetworkInBytes: 0,
          totalNetworkOutBytes: 0,
          startTimeUnixMs: 1000,
          name: 'launchd',
          executablePath: '/sbin/launchd',
          commandLine: '/sbin/launchd',
          appBundlePath: '',
        ),
      ],
    );

    final path = await repository.saveSnapshot(snapshot);
    final entries = await repository.listSnapshots();
    final imported = await repository.importSnapshot(path);

    expect(entries, hasLength(1));
    expect(entries.single.path, path);
    expect(entries.single.processCount, 1);
    expect(entries.single.platform, 'test');
    expect(imported.generatedAtUnixMs, 42);
    expect(imported.processes.single.name, 'launchd');

    await repository.renameSnapshot(entries.single, 'Incident baseline');
    final renamedEntries = await repository.listSnapshots();

    expect(renamedEntries.single.name, 'Incident baseline');

    final externalFile = File('${directory.path}/external.json');
    await externalFile.writeAsString(
      jsonEncode(
        SnapshotDocument(
          schemaVersion: 1,
          exportedAtUnixMs: 99,
          source: 'ProcessLama',
          displayName: 'External capture',
          snapshot: snapshot,
        ).toJson(),
      ),
    );
    final importedPath = await repository.saveSnapshotDocument(
      externalFile.path,
    );
    final importedEntries = await repository.listSnapshots();

    expect(importedPath, isNot(externalFile.path));
    expect(importedEntries, hasLength(2));
    expect(
      importedEntries.singleWhere((entry) => entry.path == importedPath).name,
      'External capture',
    );

    await repository.deleteSnapshot(renamedEntries.single);

    await repository.deleteSnapshot(
      importedEntries.singleWhere((entry) => entry.path == importedPath),
    );

    expect(await repository.listSnapshots(), isEmpty);
    expect(File(path).existsSync(), isFalse);
  });

  test('remote snapshots carry their host and embedded icons', () async {
    final directory = await Directory.systemTemp.createTemp(
      'processlama_remote_snapshot_test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = FileSnapshotRepository(baseDirectory: directory);
    const hash =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    final record = const ProcessRecord(
      pid: 9,
      ppid: 1,
      uid: 1000,
      user: 'tester',
      status: ProcessStatus.running,
      rssBytes: 1,
      virtualMemoryBytes: 1,
      cpuTimeNanos: 0,
      threadCount: 1,
      openFileCount: 0,
      nice: 0,
      priority: 0,
      cpuUsage: 0,
      gpuUsage: 0,
      networkInBytesPerSecond: 0,
      networkOutBytesPerSecond: 0,
      totalNetworkInBytes: 0,
      totalNetworkOutBytes: 0,
      startTimeUnixMs: 5,
      name: 'nginx',
      executablePath: '/usr/sbin/nginx',
      commandLine: 'nginx',
      appBundlePath: '',
      iconRef: ProcessIconRef.remote(hash),
    );
    final path = await repository.saveRemoteSnapshot(
      ProcessSnapshot(
        generatedAtUnixMs: 7,
        platform: 'linux',
        processes: [record],
      ),
      host: const SnapshotHost(
        displayName: 'Build box',
        alias: 'build-box',
        operatingSystem: 'linux',
        architecture: 'arm64',
      ),
      icons: {
        hash: Uint8List.fromList([1, 2, 3]),
      },
    );

    final document = SnapshotDocument.fromJson(
      jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>,
    );
    expect(document.schemaVersion, SnapshotDocument.currentSchemaVersion);
    expect(document.host!.alias, 'build-box');
    expect(document.host!.architecture, 'arm64');
    final imported = await repository.importSnapshot(path);
    expect(
      imported.processes.single.iconRef,
      const ProcessIconRef.remote(hash),
    );
    expect(await repository.importSnapshotIcons(path), {
      hash: [1, 2, 3],
    });

    // Version 1 documents still load, without host or icons.
    final legacy = File('${directory.path}/legacy.json')
      ..writeAsStringSync(
        jsonEncode({
          'schema_version': 1,
          'exported_at_unix_ms': 1,
          'source': 'ProcessLama',
          'snapshot': {
            'generated_at_unix_ms': 1,
            'platform': 'linux',
            'processes': [],
          },
        }),
      );
    final old = SnapshotDocument.fromJson(
      jsonDecode(legacy.readAsStringSync()) as Map<String, Object?>,
    );
    expect(old.host, isNull);
    expect(old.icons, isEmpty);
    expect(await repository.importSnapshotIcons(legacy.path), isEmpty);
  });
}
