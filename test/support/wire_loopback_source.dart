import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:devmil_remote/devmil_remote.dart';
import 'package:flutter/foundation.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/repositories.dart';
import 'package:processlama/repositories/impl/remote/wire/contract.g.dart';
import 'package:processlama/repositories/impl/remote/wire/telemetry_codec.dart';
import 'package:processlama/services/services.dart';

/// Mirrors the helper's `telemetry.snapshot` encoder
/// (`rust-core/remote-helper/src/telemetry.rs`): topology only when
/// identities, parents or static fields changed; integer metrics; `null` for
/// an unchanged value longer than four characters.
final class RemoteTelemetryTestEncoder {
  var _version = 0;
  List<ProcessIdentity> _rows = const [];
  List<int> _parents = const [];
  String? _statics;
  List<List<int>>? _baseline;

  /// Icon URIs by the hash the encoder sent for them.
  final iconUris = <String, String>{};

  Map<String, Object?> encode(ProcessSnapshot snapshot) {
    final records = snapshot.processes;
    final rows = [for (final record in records) record.identity];
    final parentByIdentity =
        snapshot.topology?.parentByIdentity ?? _parentLinks(records);
    final index = {for (var i = 0; i < rows.length; i++) rows[i]: i};
    final parents = [
      for (final identity in rows) index[parentByIdentity[identity]] ?? -1,
    ];
    String? icon(ProcessRecord record) {
      final uri = record.iconUri;
      if (uri == null) return null;
      final hash = sha256.convert(utf8.encode(uri)).toString();
      iconUris[hash] = uri;
      return hash;
    }

    final statics = jsonEncode([
      for (final record in records)
        [
          record.ppid,
          record.uid,
          record.user,
          record.name,
          record.executablePath,
          record.commandLine,
          record.appBundlePath,
          icon(record),
        ],
    ]);
    final sendTopology =
        _statics == null ||
        !listEquals(rows, _rows) ||
        !listEquals(parents, _parents) ||
        statics != _statics;
    if (sendTopology) {
      _version++;
      _rows = rows;
      _parents = parents;
      _statics = statics;
      _baseline = null;
    }
    final metrics = [for (final record in records) _metrics(record)];
    final baseline = _baseline;
    final columns = <String, Object?>{
      for (var column = 0; column < telemetryMetricColumns.length; column++)
        telemetryMetricColumns[column]: [
          for (var row = 0; row < metrics.length; row++)
            baseline != null &&
                    baseline[row][column] == metrics[row][column] &&
                    (metrics[row][column] < -99 || metrics[row][column] > 999)
                ? null
                : metrics[row][column],
        ],
    };
    _baseline = metrics;
    return {
      'capturedAtMs': snapshot.generatedAtUnixMs,
      'platform': snapshot.platform,
      'topologyVersion': _version,
      'topology': sendTopology
          ? {
              'pid': [for (final row in rows) row.pid],
              'start': [for (final row in rows) row.startTimeUnixMs],
              'parent': parents,
              'ppid': [for (final record in records) record.ppid],
              'uid': [for (final record in records) record.uid],
              'user': [for (final record in records) record.user],
              'name': [for (final record in records) record.name],
              'exe': [for (final record in records) record.executablePath],
              'cmd': [for (final record in records) record.commandLine],
              'bundle': [for (final record in records) record.appBundlePath],
              'icon': [for (final record in records) icon(record)],
            }
          : null,
      'metrics': columns,
      'localPorts': [for (final record in records) record.localPorts],
      'listeningPorts': [for (final record in records) record.listeningPorts],
    };
  }

  static Map<ProcessIdentity, ProcessIdentity?> _parentLinks(
    List<ProcessRecord> records,
  ) {
    final byPid = {for (final record in records) record.pid: record.identity};
    return {
      for (final record in records)
        record.identity: record.ppid == record.pid ? null : byPid[record.ppid],
    };
  }

  static int _rate(double value) =>
      value.isFinite && value > 0 ? value.round() : 0;

  static List<int> _metrics(ProcessRecord record) => [
    _rate(record.cpuUsage * 10),
    _rate(record.gpuUsage * 10),
    record.rssBytes,
    record.virtualMemoryBytes,
    record.cpuTimeNanos ~/ 1000000,
    record.threadCount,
    record.openFileCount,
    record.nice,
    record.priority,
    ProcessStatus.values.indexOf(record.status),
    _rate(record.networkInBytesPerSecond),
    _rate(record.networkOutBytesPerSecond),
    record.totalNetworkInBytes,
    record.totalNetworkOutBytes,
    _rate(record.storageReadBytesPerSecond),
    _rate(record.storageWriteBytesPerSecond),
    record.totalStorageReadBytes,
    record.totalStorageWriteBytes,
    record.storageIoAvailable ? 1 : 0,
  ];
}

Object? _overTheWire(Object? value) => parseWireJson(
  Uint8List.fromList(encodeWireJson(value)),
  WireParseLimits.standard,
);

Map<String, Object?> _section<T>(
  ProcessDetailSection<T> section,
  Object? Function(T value) encode,
) => switch (section) {
  ProcessDetailAvailable(:final value) => {
    'state': 'available',
    'reason': null,
    'value': encode(value),
  },
  ProcessDetailRestricted(:final reason) => {
    'state': 'restricted',
    'reason': reason,
    'value': null,
  },
  ProcessDetailUnsupported(:final reason) => {
    'state': 'unsupported',
    'reason': reason,
    'value': null,
  },
  ProcessDetailNotFound(:final reason) => {
    'state': 'notFound',
    'reason': reason,
    'value': null,
  },
};

/// The helper's `process.detail` encoding (`remote-helper/src/detail.rs`).
Map<String, Object?> encodeTestDetail(ProcessDetail detail) => {
  'pid': detail.identity.pid,
  'start': detail.identity.startTimeUnixMs,
  'files': _section(
    detail.files,
    (files) => [
      for (final file in files)
        {'fd': file.fd, 'kind': file.kind, 'path': file.path},
    ],
  ),
  'sockets': _section(
    detail.sockets,
    (sockets) => [
      for (final socket in sockets)
        {
          'protocol': socket.protocol,
          'localAddress': socket.localAddress,
          'localPort': socket.localPort,
          'localApproximate': socket.localAddressApproximate,
          'remoteAddress': socket.remoteAddress,
          'remotePort': socket.remotePort,
          'remoteApproximate': socket.remoteAddressApproximate,
          'state': socket.state,
        },
    ],
  ),
  'threads': _section(
    detail.threads,
    (threads) => {
      'summary': switch (threads.summary) {
        final summary? => {
          'threadCount': summary.threadCount,
          'machSyscallCount': summary.machSyscallCount,
          'rosettaTranslated': summary.rosettaTranslated,
        },
        null => null,
      },
      'threads': [
        for (final thread in threads.threads)
          {
            'id': thread.threadId,
            'cpuTenths': (thread.cpuPercent * 10).round(),
            'approximate': thread.cpuPercentApproximate,
            'state': thread.state,
          },
      ],
    },
  ),
  'security': _section(
    detail.security,
    (security) => {
      'signingStatus': security.signingStatus,
      'signingAuthority': security.signingAuthority,
      'teamId': security.teamId,
      'bundleId': security.bundleId,
      'entitlementsSummary': security.entitlementsSummary,
      'entitlementsApproximate': security.entitlementsApproximate,
      'gatekeeperOrigin': security.gatekeeperOrigin,
      'sandbox': security.sandbox,
      'hardenedRuntime': security.hardenedRuntime,
      'architecture': security.architecture,
      'rosettaTranslated': security.rosettaTranslated,
    },
  ),
};

/// A remote [ProcessSource] whose "helper" is a [ProcessRepository]: every
/// sample, detail and signal crosses the wire encoding, strict JSON and the
/// production decoders. Records the same repository operations as the local
/// source.
final class WireLoopbackRemoteSource implements ProcessSource {
  WireLoopbackRemoteSource({
    required this.repository,
    required this.tracker,
    TargetPlatform? platform,
  }) : _capabilities = ValueNotifier(
         HostCapabilities.local(platform ?? defaultTargetPlatform),
       );

  final ProcessRepository repository;
  final RepositoryOperationTracker tracker;
  final encoder = RemoteTelemetryTestEncoder();
  final _decoder = RemoteTelemetryDecoder();
  final ValueNotifier<HostCapabilities> _capabilities;
  final _state = ValueNotifier(ProcessSourceState.live);
  final _updates = StreamController<ProcessSnapshot>.broadcast(sync: true);

  @override
  ProcessSourceDescriptor get descriptor =>
      const RemoteProcessSourceDescriptor('wire-loopback');

  @override
  ValueListenable<ProcessSourceState> get state => _state;

  @override
  ValueListenable<HostCapabilities> get capabilities => _capabilities;

  @override
  Stream<ProcessSnapshot> get updates => _updates.stream;

  /// Resolves the hashes this source sent back to the original icon URIs.
  ProcessIconResolver get iconResolver => _LoopbackIcons(encoder.iconUris);

  @override
  Future<void> setCadence(ProcessCadence cadence) async {}

  @override
  Future<void> sampleNow() async {
    tracker.recordOperation(
      'ProcessRepository.fetchSnapshot',
      'ProcessService.refresh',
    );
    final snapshot = await repository.fetchSnapshot(
      pollingIntervalMs: const AppSettings().pollingIntervalMs,
    );
    _updates.add(_decoder.decode(_overTheWire(encoder.encode(snapshot))));
  }

  @override
  Future<ProcessDetail?> fetchDetail(ProcessIdentity identity) async {
    tracker.recordOperation(
      'ProcessRepository.fetchProcessDetail',
      'ProcessService.refreshInspectorDetail',
    );
    final detail = await repository.fetchProcessDetail(identity);
    return decodeProcessDetail(_overTheWire(encodeTestDetail(detail)));
  }

  @override
  Future<void> sendSignal(
    ProcessIdentity identity,
    ProcessSignal signal,
  ) async {
    tracker.recordOperation(
      'ProcessRepository.sendSignal',
      'ProcessService.${signal.name}Process',
    );
    final arguments = _overTheWire(signalArguments(identity, signal))! as Map;
    await repository.sendSignal(
      ProcessIdentity(
        pid: arguments['pid'] as int,
        startTimeUnixMs: arguments['start'] as int,
      ),
      processSignalFromWire(arguments['signal'] as String)!,
    );
    final outcome = decodeSignalOutcome(_overTheWire({'outcome': 'sent'}));
    if (outcome != SignalOutcome.sent) throw ProcessSignalException(outcome);
  }

  @override
  Future<void> dispose() => _updates.close();
}

final class _LoopbackIcons implements ProcessIconResolver {
  const _LoopbackIcons(this.uris);

  final Map<String, String> uris;

  @override
  String? pathFor(ProcessIconRef? ref) => switch (ref) {
    ProcessRemoteIcon(:final sha256) => uris[sha256],
    ProcessFileIcon(:final uri) => uri,
    null => null,
  };

  @override
  ValueListenable<String?>? updatesFor(ProcessIconRef? ref) => null;
}
