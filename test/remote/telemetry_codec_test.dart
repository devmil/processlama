import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:devmil_remote/devmil_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/impl/remote/wire/messages.dart';
import 'package:processlama/repositories/impl/remote/wire/telemetry_codec.dart';

List<Object?> _golden() {
  final bytes = Uint8List.fromList(
    utf8.encode(
      File('fixtures/remote_telemetry_golden.json').readAsStringSync(),
    ),
  );
  final document = parseWireJson(bytes, WireParseLimits.standard)! as Map;
  return document['samples']! as List<Object?>;
}

void main() {
  test('decodes the helper encoder golden samples', () {
    final samples = _golden();
    final decoder = RemoteTelemetryDecoder();
    final first = decoder.decode(samples[0]);
    expect(first.platform, 'linux');
    expect(first.processes.map((record) => record.pid), [1, 42]);
    final worker = first.processes[1];
    expect(worker.name, 'worker');
    expect(worker.localPorts, [8080, 51000]);
    expect(worker.listeningPorts, [8080]);
    expect(worker.commandLine, '/usr/bin/worker --serve');
    expect(worker.cpuUsage, 12.3);
    expect(worker.rssBytes, 104857600);
    expect(worker.networkInBytesPerSecond, 2048);
    expect(worker.storageIoAvailable, isTrue);
    expect(
      worker.treeCpuUsage,
      worker.cpuUsage,
      reason: 'the session sums trees',
    );
    expect(first.processes[0].status, ProcessStatus.sleeping);
    expect(first.processes[0].cpuTimeNanos, 4200000000);
    expect(
      first.topology!.parentByIdentity[worker.identity],
      first.processes[0].identity,
    );

    final second = decoder.decode(samples[1]);
    expect(
      second.topology,
      same(first.topology),
      reason: 'metric-only samples share the graph',
    );
    expect(second.processes[1].cpuUsage, 50);
    expect(second.processes[1].localPorts, [9090]);
    expect(second.processes[1].listeningPorts, isEmpty);
    expect(
      second.processes[1].rssBytes,
      104857600,
      reason: 'null keeps the previous value',
    );
    expect(second.processes[1].virtualMemoryBytes, 2147483648);
    expect(second.processes[1].totalNetworkInBytes, 9000000);
    expect(second.processes[1].networkInBytesPerSecond, 0);
  });

  test('rejects samples that do not fit the topology', () {
    final samples = _golden();
    final metricOnly =
        jsonDecode(jsonEncode(samples[1])) as Map<String, Object?>;
    expect(
      () => RemoteTelemetryDecoder().decode(metricOnly),
      throwsA(isA<InvalidRemoteMessage>()),
      reason: 'a metric-only sample needs a known topology',
    );

    Map<String, Object?> mutated(
      void Function(Map<String, dynamic> sample) change,
    ) {
      final copy = jsonDecode(jsonEncode(samples[0])) as Map<String, dynamic>;
      change(copy);
      return copy.cast<String, Object?>();
    }

    for (final (reason, change)
        in <(String, void Function(Map<String, dynamic>))>[
          (
            'short column',
            (sample) => (sample['metrics']['cpu'] as List).removeLast(),
          ),
          ('extra key', (sample) => sample['extra'] = 1),
          ('short ports', (sample) => sample['localPorts'] = [null]),
          (
            'short listening ports',
            (sample) => sample['listeningPorts'] = [null],
          ),
          (
            'invalid listening port',
            (sample) => sample['listeningPorts'] = [
              null,
              [0],
            ],
          ),
          (
            'invalid port',
            (sample) => sample['localPorts'] = [
              null,
              [65536],
            ],
          ),
          (
            'fractional port',
            (sample) => sample['localPorts'] = [
              null,
              [80.5],
            ],
          ),
          ('fraction', (sample) => (sample['metrics']['cpu'] as List)[0] = 1.5),
          (
            'self parent',
            (sample) => (sample['topology']['parent'] as List)[1] = 1,
          ),
          (
            'parent out of range',
            (sample) => (sample['topology']['parent'] as List)[1] = 7,
          ),
          (
            'duplicate identity',
            (sample) {
              (sample['topology']['pid'] as List)[1] = 1;
              (sample['topology']['start'] as List)[1] =
                  (sample['topology']['start'] as List)[0];
            },
          ),
          (
            'bad icon',
            (sample) => (sample['topology']['icon'] as List)[0] = 'not-a-hash',
          ),
          (
            'null in a topology sample',
            (sample) => (sample['metrics']['rss'] as List)[0] = null,
          ),
        ]) {
      expect(
        () => RemoteTelemetryDecoder().decode(mutated(change)),
        throwsA(isA<InvalidRemoteMessage>()),
        reason: reason,
      );
    }
  });

  test('details and signal outcomes decode strictly', () {
    final detail = decodeProcessDetail({
      'pid': 42,
      'start': 1,
      'files': {
        'state': 'available',
        'reason': null,
        'value': [
          {'fd': 3, 'kind': 'file', 'path': '/tmp/x'},
        ],
      },
      'sockets': {'state': 'restricted', 'reason': 'permission', 'value': null},
      'threads': {'state': 'unsupported', 'reason': 'n/a', 'value': null},
      'security': {'state': 'notFound', 'reason': 'gone', 'value': null},
    });
    expect(
      (detail.files as ProcessDetailAvailable).value.single.path,
      '/tmp/x',
    );
    expect(
      detail.sockets,
      isA<ProcessDetailRestricted<List<NetworkEndpointInfo>>>(),
    );
    expect(
      detail.threads,
      isA<ProcessDetailUnsupported<ThreadInspectionInfo>>(),
    );
    expect(
      () => decodeProcessDetail({'pid': 1}),
      throwsA(isA<InvalidRemoteMessage>()),
    );
    expect(decodeSignalOutcome({'outcome': 'denied'}), SignalOutcome.denied);
    expect(
      () => decodeSignalOutcome({'outcome': 'maybe'}),
      throwsA(isA<InvalidRemoteMessage>()),
    );
  });
}
