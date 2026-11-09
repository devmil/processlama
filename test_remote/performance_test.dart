// The --performance lane of scripts/verify_remote_hosts.py: payload sizes of
// topology and metric-only samples with about 1,000 processes, and the
// helper's CPU at a 1 s cadence, in an Ubuntu 22.04 sshd container. Prints a
// PERFORMANCE line the lane records.
@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:devmil_remote/devmil_remote.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/repositories.dart';
import 'package:processlama/repositories/impl/remote/bundled_remote_helper_repository.dart';
import 'package:processlama/repositories/impl/remote/ssh_remote_connection_repository.dart';
import 'package:processlama/repositories/impl/remote/wire/telemetry_codec.dart';
import 'package:processlama/rust/frb_generated.dart';
import 'package:processlama/services/impl/remote_host_service_impl.dart';
import 'package:processlama/services/impl/settings_service_impl.dart';
import 'package:processlama/services/services.dart';

String _fixture(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw StateError('run through scripts/verify_remote_hosts.py ($name)');
  }
  return value;
}

final class _Port implements RemoteHostInteractionPort {
  @override
  bool get isActive => true;

  @override
  Future<RemoteInstallChoice> confirmInstall(
    RemoteInstallRequest request,
  ) async => RemoteInstallChoice.install;

  @override
  Future<bool> confirmHelperRemoval(RemoteHostProfile profile) async => true;

  @override
  void report(RemoteHostReport report) {}
}

class _NoAppSettings implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<int> _helperTicks(String container) async {
  final result = await Process.run('podman', [
    'exec',
    container,
    'sh',
    '-c',
    'for p in \$(pgrep -f "processlama-remote-helper --stdio"); do '
        'cut -d" " -f14,15 /proc/\$p/stat; done',
  ]);
  return (result.stdout as String)
      .split(RegExp(r'\s+'))
      .where((value) => value.isNotEmpty)
      .map(int.parse)
      .fold<int>(0, (sum, value) => sum + value);
}

void main() {
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        _fixture('PROCESSLAMA_NATIVE_LIBRARY'),
      ),
    );
  });

  test('payload sizes and helper CPU with about 1,000 processes', () async {
    final alias = _fixture('PROCESSLAMA_TEST_ALIAS');
    final container = _fixture('PROCESSLAMA_TEST_CONTAINER');
    final settings = SettingsServiceImpl(
      settingsRepository: _NoAppSettings(),
      remoteHostsRepository: MemoryRemoteHostsSettingsRepository(),
    );
    await settings.initialize();
    final service = RemoteHostServiceImpl(
      connections: SshRemoteConnectionRepository(
        configFile: _fixture('PROCESSLAMA_SSH_CONFIG'),
      ),
      artifacts: BundledRemoteHelperRepository(
        resolvedExecutable: '/nonexistent/processlama',
        environment: {
          'PROCESSLAMA_REMOTE_HELPER_DIR': _fixture(
            'PROCESSLAMA_REMOTE_HELPER_DIR',
          ),
        },
        releaseBuild: false,
      ),
      remoteHostsSettings: settings,
      settingsService: settings,
    );
    addTearDown(service.dispose);
    final workflows = RemoteHostWorkflows(remoteHosts: service, port: _Port());
    final profile = await service.addProfile(
      RemoteHostProfileDraft(sshAlias: alias),
    );
    expect(
      (await workflows.connect(profile.id)).phase,
      RemoteConnectionPhase.live,
    );
    final lease = service.acquire(profile.id);
    final connection = lease.connection.value!;

    // Raw publications, to measure what crosses the wire.
    final subscription = await connection.subscribe(
      'telemetry',
      telemetryArguments(cadenceMs: 1000, pollingMs: 1000),
      initialCredit: 1,
    );
    final sizes = <int>[];
    final topologySizes = <int>[];
    var processes = 0;
    final decoder = RemoteTelemetryDecoder();
    final arrivals = <DateTime>[];
    final done = subscription.publications.take(32).forEach((data) {
      final size = encodeWireJson(data).length;
      final snapshot = decoder.decode(data);
      processes = snapshot.processes.length;
      ((data! as Map)['topology'] == null ? sizes : topologySizes).add(size);
      arrivals.add(DateTime.now());
      subscription.grant(1);
    });
    // CPU over the steady part of the run.
    await Future<void>.delayed(const Duration(seconds: 2));
    final ticksBefore = await _helperTicks(container);
    final started = DateTime.now();
    await done;
    final elapsed = DateTime.now().difference(started);
    final ticksAfter = await _helperTicks(container);
    subscription.cancel();
    await lease.release();
    final cpuPercent =
        (ticksAfter - ticksBefore) / 100 / elapsed.inMilliseconds * 1000 * 100;
    final gaps = [
      for (var index = 1; index < arrivals.length; index++)
        arrivals[index].difference(arrivals[index - 1]).inMilliseconds,
    ]..sort();
    sizes.sort();
    final report = {
      'processes': processes,
      'topologyBytes': topologySizes,
      'metricOnlyBytesMedian': sizes.isEmpty ? null : sizes[sizes.length ~/ 2],
      'metricOnlyBytesMax': sizes.isEmpty ? null : sizes.last,
      'helperCpuPercent': double.parse(cpuPercent.toStringAsFixed(2)),
      'gapMsMedian': gaps[gaps.length ~/ 2],
      'gapMsMax': gaps.last,
    };
    // ignore: avoid_print
    print('PERFORMANCE ${jsonEncode(report)}');
    expect(processes, greaterThan(900));
    expect(await workflows.removeHelper(profile.id), RemoteInstallResult.ok);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
