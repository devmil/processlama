import 'dart:convert';
import 'dart:typed_data';

import '../../../../models/models.dart';
import '../../../process_repository.dart';
import 'contract.g.dart';
import 'messages.dart';

/// Metric columns of `telemetry.snapshot`, in wire order.
const telemetryMetricColumns = [
  'cpu',
  'gpu',
  'rss',
  'vmem',
  'cpuTimeMs',
  'threads',
  'files',
  'nice',
  'prio',
  'status',
  'netIn',
  'netOut',
  'netInTotal',
  'netOutTotal',
  'ioRead',
  'ioWrite',
  'ioReadTotal',
  'ioWriteTotal',
  'ioAvail',
];

const _topologyColumns = [
  'pid',
  'start',
  'parent',
  'ppid',
  'uid',
  'user',
  'name',
  'exe',
  'cmd',
  'bundle',
  'icon',
];

const _statusByIndex = [
  ProcessStatus.running,
  ProcessStatus.sleeping,
  ProcessStatus.stopped,
  ProcessStatus.zombie,
  ProcessStatus.unknown,
];

Never _invalid(String reason) => throw InvalidRemoteMessage(reason);

List<Object?> _column(Map<String, Object?> map, String key, int length) {
  final value = map[key];
  if (value is! List<Object?> || value.length != length) {
    _invalid('column $key');
  }
  return value;
}

final class _StaticRow {
  const _StaticRow({
    required this.identity,
    required this.ppid,
    required this.uid,
    required this.user,
    required this.name,
    required this.executablePath,
    required this.commandLine,
    required this.appBundlePath,
    required this.icon,
  });

  final ProcessIdentity identity;
  final int ppid;
  final int uid;
  final String user;
  final String name;
  final String executablePath;
  final String commandLine;
  final String appBundlePath;
  final String? icon;
}

/// Decodes `telemetry.snapshot` publications of one subscription into
/// [ProcessSnapshot]s. Keeps the topology between samples and fills `null`
/// metrics from the previous sample. Every violation throws
/// [InvalidRemoteMessage].
final class RemoteTelemetryDecoder {
  int? _version;
  List<_StaticRow> _rows = const [];
  ProcessTopology? _topology;
  List<List<int>>? _metrics;

  ProcessSnapshot decode(Object? data) {
    final sample = wireObject(data, [
      'capturedAtMs',
      'platform',
      'topologyVersion',
      'topology',
      'metrics',
      if (data is Map<String, Object?> && data.containsKey('localPorts'))
        'localPorts',
      if (data is Map<String, Object?> && data.containsKey('listeningPorts'))
        'listeningPorts',
    ], 'sample');
    final version = wireUnsigned(sample, 'topologyVersion', 'version');
    final topology = sample['topology'];
    var fresh = false;
    if (topology != null) {
      _readTopology(topology, version);
      fresh = true;
    } else if (version != _version) {
      // A metric-only sample for a topology this client never received.
      _invalid('topology version');
    }
    final metricsMap = wireObject(
      sample['metrics'],
      telemetryMetricColumns,
      'metrics',
    );
    final length = _rows.length;
    List<int>? Function(int row) portColumn(String name, String what) {
      final ports = sample.containsKey(name)
          ? _column(sample, name, length)
          : null;
      return (row) {
        final value = ports?[row];
        if (value == null) return null;
        if (value is! List<Object?> ||
            value.length > 65535 ||
            value.any((p) => p is! int || p < 1 || p > 65535)) {
          _invalid(what);
        }
        return List<int>.unmodifiable(value.cast<int>());
      };
    }

    final localPorts = portColumn('localPorts', 'local ports');
    final listeningPorts = portColumn('listeningPorts', 'listening ports');

    final columns = [
      for (final name in telemetryMetricColumns)
        _column(metricsMap, name, length),
    ];
    final previous = fresh ? null : _metrics;
    final metrics = List<List<int>>.generate(length, (row) {
      return List<int>.generate(telemetryMetricColumns.length, (column) {
        final value = columns[column][row];
        if (value == null) {
          if (previous == null) _invalid('null without a previous sample');
          return previous[row][column];
        }
        if (value is! int || value < -(1 << 53) || value > (1 << 53)) {
          _invalid('metric');
        }
        return value;
      });
    });
    _metrics = metrics;
    final platform = wireString(sample, 'platform', 32, 'platform');
    return ProcessSnapshot(
      generatedAtUnixMs: wireUnsigned(sample, 'capturedAtMs', 'capturedAt'),
      platform: platform,
      processes: [
        for (var row = 0; row < length; row++)
          _record(_rows[row], metrics[row]).copyWith(
            localPorts: localPorts(row),
            listeningPorts: listeningPorts(row),
          ),
      ],
      topology: _topology,
    );
  }

  void _readTopology(Object? value, int version) {
    final map = wireObject(value, _topologyColumns, 'topology');
    final pids = map['pid'];
    if (pids is! List<Object?> ||
        pids.length > RemoteWireLimits.processesPerSample) {
      _invalid('topology size');
    }
    final length = pids.length;
    final columns = {
      for (final name in _topologyColumns) name: _column(map, name, length),
    };
    int integer(String column, int row) {
      final value = columns[column]![row];
      if (value is! int) _invalid(column);
      return value;
    }

    String text(String column, int row, int maxLength) {
      final value = columns[column]![row];
      if (value is! String || value.length > maxLength) _invalid(column);
      return value;
    }

    final rows = <_StaticRow>[];
    final seen = <ProcessIdentity>{};
    for (var row = 0; row < length; row++) {
      final pid = integer('pid', row);
      final start = integer('start', row);
      if (pid < 0 || start < 0) _invalid('identity');
      final identity = ProcessIdentity(pid: pid, startTimeUnixMs: start);
      if (!seen.add(identity)) _invalid('duplicate identity');
      final icon = columns['icon']![row];
      if (icon != null &&
          (icon is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(icon))) {
        _invalid('icon');
      }
      rows.add(
        _StaticRow(
          identity: identity,
          ppid: integer('ppid', row),
          uid: integer('uid', row),
          user: text('user', row, 64),
          name: text('name', row, 256),
          executablePath: text('exe', row, 1024),
          commandLine: text('cmd', row, 2048),
          appBundlePath: text('bundle', row, 1024),
          icon: icon as String?,
        ),
      );
    }
    final parents = <ProcessIdentity, ProcessIdentity?>{};
    for (var row = 0; row < length; row++) {
      final parent = integer('parent', row);
      if (parent < -1 || parent >= length || parent == row) _invalid('parent');
      parents[rows[row].identity] = parent < 0 ? null : rows[parent].identity;
    }
    _rows = rows;
    _version = version;
    _topology = ProcessTopology(version: version, parents: parents);
  }

  ProcessRecord _record(_StaticRow row, List<int> metrics) {
    final status = metrics[9];
    return ProcessRecord(
      pid: row.identity.pid,
      ppid: row.ppid,
      uid: row.uid,
      user: row.user,
      status: status >= 0 && status < _statusByIndex.length
          ? _statusByIndex[status]
          : ProcessStatus.unknown,
      rssBytes: metrics[2],
      virtualMemoryBytes: metrics[3],
      cpuTimeNanos: metrics[4] * 1000000,
      threadCount: metrics[5],
      openFileCount: metrics[6],
      nice: metrics[7],
      priority: metrics[8],
      cpuUsage: metrics[0] / 10,
      gpuUsage: metrics[1] / 10,
      networkInBytesPerSecond: metrics[10].toDouble(),
      networkOutBytesPerSecond: metrics[11].toDouble(),
      totalNetworkInBytes: metrics[12],
      totalNetworkOutBytes: metrics[13],
      storageReadBytesPerSecond: metrics[14].toDouble(),
      storageWriteBytesPerSecond: metrics[15].toDouble(),
      totalStorageReadBytes: metrics[16],
      totalStorageWriteBytes: metrics[17],
      storageIoAvailable: metrics[18] != 0,
      treeCpuUsage: metrics[0] / 10,
      treeGpuUsage: metrics[1] / 10,
      treeRssBytes: metrics[2],
      treeNetworkInBytesPerSecond: metrics[10].toDouble(),
      treeNetworkOutBytesPerSecond: metrics[11].toDouble(),
      treeStorageReadBytesPerSecond: metrics[14].toDouble(),
      treeStorageWriteBytesPerSecond: metrics[15].toDouble(),
      treeStorageIoAvailable: metrics[18] != 0,
      startTimeUnixMs: row.identity.startTimeUnixMs,
      name: row.name,
      executablePath: row.executablePath,
      commandLine: row.commandLine,
      appBundlePath: row.appBundlePath,
      iconRef: row.icon == null ? null : ProcessIconRef.remote(row.icon!),
    );
  }
}

/// The `telemetry` subscription arguments.
Map<String, Object?> telemetryArguments({
  required int? cadenceMs,
  required int pollingMs,
}) => {'cadenceMs': cadenceMs, 'pollingMs': pollingMs};

ProcessDetailSection<T> _section<T>(
  Object? value,
  T Function(Object? value) decode,
) {
  final map = wireObject(value, const ['state', 'reason', 'value'], 'section');
  final state = map['state'];
  final reason = map['reason'];
  if (state == 'available') {
    if (reason != null) _invalid('section');
    return ProcessDetailAvailable(decode(map['value']));
  }
  if (reason is! String || reason.length > 256 || map['value'] != null) {
    _invalid('section');
  }
  return switch (state) {
    'restricted' => ProcessDetailRestricted(reason),
    'unsupported' => ProcessDetailUnsupported(reason),
    'notFound' => ProcessDetailNotFound(reason),
    _ => _invalid('section state'),
  };
}

List<Object?> _list(Object? value) {
  if (value is! List<Object?> || value.length > 4096) _invalid('list');
  return value;
}

/// Decodes a `process.detail` result.
ProcessDetail decodeProcessDetail(Object? value) {
  final map = wireObject(value, const [
    'pid',
    'start',
    'files',
    'sockets',
    'threads',
    'security',
  ], 'detail');
  return ProcessDetail(
    identity: ProcessIdentity(
      pid: wireUnsigned(map, 'pid', 'pid'),
      startTimeUnixMs: wireUnsigned(map, 'start', 'start'),
    ),
    files: _section(map['files'], (value) {
      return [
        for (final entry in _list(value))
          () {
            final file = wireObject(entry, const [
              'fd',
              'kind',
              'path',
            ], 'file');
            final fd = file['fd'];
            if (fd is! int) _invalid('fd');
            return FileDescriptorInfo(
              fd: fd,
              kind: wireString(file, 'kind', 64, 'kind'),
              path: wireString(file, 'path', 1024, 'path'),
            );
          }(),
      ];
    }),
    sockets: _section(map['sockets'], (value) {
      return [
        for (final entry in _list(value))
          () {
            final socket = wireObject(entry, const [
              'protocol',
              'localAddress',
              'localPort',
              'localApproximate',
              'remoteAddress',
              'remotePort',
              'remoteApproximate',
              'state',
            ], 'socket');
            return NetworkEndpointInfo(
              protocol: wireString(socket, 'protocol', 32, 'socket'),
              localAddress: wireString(socket, 'localAddress', 128, 'socket'),
              localPort: wireUnsigned(socket, 'localPort', 'socket'),
              localAddressApproximate: wireBool(
                socket,
                'localApproximate',
                'socket',
              ),
              remoteAddress: wireString(socket, 'remoteAddress', 128, 'socket'),
              remotePort: wireUnsigned(socket, 'remotePort', 'socket'),
              remoteAddressApproximate: wireBool(
                socket,
                'remoteApproximate',
                'socket',
              ),
              state: wireString(socket, 'state', 32, 'socket'),
            );
          }(),
      ];
    }),
    threads: _section(map['threads'], (value) {
      final inspection = wireObject(value, const [
        'summary',
        'threads',
      ], 'threads');
      final summaryValue = inspection['summary'];
      TaskSummaryInfo? summary;
      if (summaryValue != null) {
        final summaryMap = wireObject(summaryValue, const [
          'threadCount',
          'machSyscallCount',
          'rosettaTranslated',
        ], 'summary');
        final threadCount = summaryMap['threadCount'];
        final syscalls = summaryMap['machSyscallCount'];
        if (threadCount is! int || syscalls is! int) _invalid('summary');
        summary = TaskSummaryInfo(
          threadCount: threadCount,
          machSyscallCount: syscalls,
          rosettaTranslated: wireBool(
            summaryMap,
            'rosettaTranslated',
            'summary',
          ),
        );
      }
      return ThreadInspectionInfo(
        summary: summary,
        threads: [
          for (final entry in _list(inspection['threads']))
            () {
              final thread = wireObject(entry, const [
                'id',
                'cpuTenths',
                'approximate',
                'state',
              ], 'thread');
              return ThreadInfo(
                threadId: wireUnsigned(thread, 'id', 'thread'),
                cpuPercent: wireUnsigned(thread, 'cpuTenths', 'thread') / 10,
                cpuPercentApproximate: wireBool(
                  thread,
                  'approximate',
                  'thread',
                ),
                state: wireString(thread, 'state', 32, 'thread'),
              );
            }(),
        ],
      );
    }),
    security: _section(map['security'], (value) {
      final security = wireObject(value, const [
        'signingStatus',
        'signingAuthority',
        'teamId',
        'bundleId',
        'entitlementsSummary',
        'entitlementsApproximate',
        'gatekeeperOrigin',
        'sandbox',
        'hardenedRuntime',
        'architecture',
        'rosettaTranslated',
      ], 'security');
      return SecurityDetailInfo(
        signingStatus: wireString(security, 'signingStatus', 128, 'security'),
        signingAuthority: wireString(
          security,
          'signingAuthority',
          1024,
          'security',
        ),
        teamId: wireString(security, 'teamId', 64, 'security'),
        bundleId: wireString(security, 'bundleId', 256, 'security'),
        entitlementsSummary: wireString(
          security,
          'entitlementsSummary',
          1024,
          'security',
        ),
        entitlementsApproximate: wireBool(
          security,
          'entitlementsApproximate',
          'security',
        ),
        gatekeeperOrigin: wireString(
          security,
          'gatekeeperOrigin',
          256,
          'security',
        ),
        sandbox: wireBool(security, 'sandbox', 'security'),
        hardenedRuntime: wireBool(security, 'hardenedRuntime', 'security'),
        architecture: wireString(security, 'architecture', 64, 'security'),
        rosettaTranslated: wireBool(security, 'rosettaTranslated', 'security'),
      );
    }),
  );
}

/// The `process.signal` arguments.
Map<String, Object?> signalArguments(
  ProcessIdentity identity,
  ProcessSignal signal,
) => {
  'pid': identity.pid,
  'start': identity.startTimeUnixMs,
  'signal': processSignalToWire(signal),
};

/// Decodes a `process.signal` result.
SignalOutcome decodeSignalOutcome(Object? value) {
  final map = wireObject(value, const ['outcome'], 'signal');
  return signalOutcomeFromWire(wireString(map, 'outcome', 16, 'signal')) ??
      _invalid('signal outcome');
}

/// Decodes an `icons.fetch` result: canonical base64 PNG bytes by hash.
Map<String, Uint8List> decodeIcons(Object? value, Set<String> requested) {
  final map = wireObject(value, const ['icons'], 'icons');
  final icons = map['icons'];
  if (icons is! List<Object?> ||
      icons.length > RemoteWireLimits.iconsPerFetch) {
    _invalid('icons');
  }
  final result = <String, Uint8List>{};
  for (final entry in icons) {
    final icon = wireObject(entry, const ['sha256', 'png'], 'icon');
    final hash = wireString(icon, 'sha256', 64, 'icon');
    if (!requested.contains(hash)) _invalid('unrequested icon');
    final encoded = wireString(
      icon,
      'png',
      RemoteWireLimits.iconFetchBytes * 2,
      'icon',
    );
    final Uint8List bytes;
    try {
      bytes = base64.decode(encoded);
    } on FormatException {
      _invalid('icon encoding');
    }
    if (base64.encode(bytes) != encoded ||
        bytes.length > RemoteWireLimits.iconBytes) {
      _invalid('icon encoding');
    }
    result[hash] = bytes;
  }
  return result;
}
