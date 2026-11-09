import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/rust/api.dart' as native;
import 'package:processlama/repositories/impl/rust_process_repository.dart';

void main() {
  test(
    'reuses native topology for metric updates and replaces PID identities',
    () {
      final mapper = RustProcessSnapshotMapper();
      final initial = mapper.map(_sample(1, includeTopology: true));
      final updated = mapper.map(_sample(1));
      expect(identical(initial.topology, updated.topology), isTrue);
      expect(mapper.knownTopologyVersion, BigInt.one);
      expect(initial.processes.last.localPorts, [53, 8080]);
      expect(
        ProcessSnapshot.fromJson(initial.toJson()).processes.last.localPorts,
        [53, 8080],
      );
      expect(initial.processes.last.listeningPorts, [8080]);
      expect(
        ProcessSnapshot.fromJson(
          initial.toJson(),
        ).processes.last.listeningPorts,
        [8080],
      );
      final reused = mapper.map(
        _sample(2, includeTopology: true, parentStart: 9),
      );
      const child = ProcessIdentity(pid: 2, startTimeUnixMs: 1);
      expect(
        reused.topology!.parentByIdentity[child],
        const ProcessIdentity(pid: 1, startTimeUnixMs: 9),
      );
      expect(
        initial.topology!.parentByIdentity[child],
        const ProcessIdentity(pid: 1, startTimeUnixMs: 1),
      );
      expect(
        () => reused.topology!.childrenByParent.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => reused.topology!.childrenByParent[null]!.clear(),
        throwsUnsupportedError,
      );
      // Saved snapshots contain records, not a backend runtime cache token.
      expect(ProcessSnapshot.fromJson(reused.toJson()).topology, isNull);
      expect(ProcessSnapshot.fromJson(reused.toJson()).processes.length, 2);
    },
  );

  test('missing structural response resets the next request for recovery', () {
    final mapper = RustProcessSnapshotMapper();
    mapper.map(_sample(1, includeTopology: true));
    expect(() => mapper.map(_sample(2)), throwsStateError);
    expect(mapper.knownTopologyVersion, isNull);
    expect(mapper.map(_sample(2, includeTopology: true)).topology!.version, 2);
  });

  test('resolves Linux Rust library beside the installed executable', () {
    final candidates = rustCoreLibraryCandidates(
      operatingSystem: 'linux',
      resolvedExecutable: '/opt/processlama/processlama',
    );

    expect(
      candidates.single.path,
      '/opt/processlama/lib/libprocesslama_core.so',
    );
  });

  test('preserves the macOS framework bundle layout', () {
    final candidates = rustCoreLibraryCandidates(
      operatingSystem: 'macos',
      resolvedExecutable:
          '/Applications/ProcessLama.app/Contents/MacOS/ProcessLama',
    );

    expect(
      candidates.single.path,
      '/Applications/ProcessLama.app/Contents/Frameworks/'
      'processlama_core.framework/processlama_core',
    );
  });
}

native.ProcessSnapshotDto _sample(
  int version, {
  bool includeTopology = false,
  int parentStart = 1,
}) {
  final parent = native.ProcessIdentityDto(
    pid: 1,
    startTimeUnixMs: BigInt.from(parentStart),
  );
  final child = native.ProcessIdentityDto(pid: 2, startTimeUnixMs: BigInt.one);
  return native.ProcessSnapshotDto(
    generatedAtUnixMs: BigInt.one,
    platform: 'test',
    processes: [_record(parent, 0), _record(child, 1)],
    topologyVersion: BigInt.from(version),
    topology: includeTopology
        ? [
            native.ProcessParentDto(identity: parent),
            native.ProcessParentDto(identity: child, parent: parent),
          ]
        : null,
  );
}

native.ProcessRecordDto _record(
  native.ProcessIdentityDto identity,
  int parent,
) => native.ProcessRecordDto(
  localPorts: parent == 0 ? null : Uint16List.fromList([53, 8080]),
  listeningPorts: parent == 0 ? null : Uint16List.fromList([8080]),
  pid: identity.pid,
  ppid: parent,
  startTimeUnixMs: identity.startTimeUnixMs,
  uid: 0,
  user: 'test',
  status: native.ProcessStatusDto.running,
  rssBytes: BigInt.zero,
  virtualMemoryBytes: BigInt.zero,
  cpuTimeNanos: BigInt.zero,
  threadCount: 0,
  openFileCount: 0,
  nice: 0,
  priority: 0,
  cpuUsage: 1,
  gpuUsage: 0,
  networkInBytesPerSecond: 0,
  networkOutBytesPerSecond: 0,
  totalNetworkInBytes: BigInt.zero,
  totalNetworkOutBytes: BigInt.zero,
  storageReadBytesPerSecond: 0,
  storageWriteBytesPerSecond: 0,
  totalStorageReadBytes: BigInt.zero,
  totalStorageWriteBytes: BigInt.zero,
  storageIoAvailable: false,
  treeCpuUsage: 1,
  treeGpuUsage: 0,
  treeRssBytes: BigInt.zero,
  treeNetworkInBytesPerSecond: 0,
  treeNetworkOutBytesPerSecond: 0,
  treeStorageReadBytesPerSecond: 0,
  treeStorageWriteBytesPerSecond: 0,
  treeStorageIoAvailable: false,
  descendantCount: BigInt.zero,
  name: 'test',
  executablePath: '',
  commandLine: '',
  appBundlePath: '',
);
