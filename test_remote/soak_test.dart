// The --soak lane of scripts/verify_remote_hosts.py: streams an Ubuntu 22.04
// sshd container with process churn into a live explorer session for
// PROCESSLAMA_SOAK_MINUTES (default 120). Every minute it samples the
// helper's resident memory and, through the VM service (the lane runs
// `flutter test --enable-vmservice`), this process's Dart heap after a full
// GC, and checks that both stay flat after a warm-up. This process's RSS is
// reported too; it follows the heap capacity the VM grows and shrinks, not
// the retained objects. Prints SOAK lines the lane records.
@TestOn('linux')
library;

import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/repositories.dart';
import 'package:processlama/repositories/impl/remote/bundled_remote_helper_repository.dart';
import 'package:processlama/repositories/impl/remote/ssh_remote_connection_repository.dart';
import 'package:processlama/rust/frb_generated.dart';
import 'package:processlama/services/impl/remote_host_service_impl.dart';
import 'package:processlama/services/impl/settings_service_impl.dart';
import 'package:processlama/services/services.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart' as vm_io;

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

class _NoSnapshots implements SnapshotRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoTracking implements RepositoryOperationTracker {
  @override
  void recordOperation(String operation, String? context) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The helper's resident memory in bytes.
Future<int> _helperRss(String container) async {
  final result = await Process.run('podman', [
    'exec',
    container,
    'sh',
    '-c',
    'ps -o rss= -p "\$(pgrep -f processlama-remote-helper | head -n 1)"',
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return int.parse('${result.stdout}'.trim()) * 1024;
}

/// The least-squares slope of [values] over [minutes], per hour.
double _slopePerHour(List<double> minutes, List<int> values) {
  final n = minutes.length;
  final meanX = minutes.reduce((a, b) => a + b) / n;
  final meanY = values.reduce((a, b) => a + b) / n;
  var numerator = 0.0;
  var denominator = 0.0;
  for (var i = 0; i < n; i++) {
    numerator += (minutes[i] - meanX) * (values[i] - meanY);
    denominator += (minutes[i] - meanX) * (minutes[i] - meanX);
  }
  return numerator / denominator * 60;
}

const _mib = 1024 * 1024;

/// Measures this isolate's Dart heap in use after a full garbage collection.
Future<Future<int> Function()> _retainedHeapProbe() async {
  final uri = (await developer.Service.getInfo()).serverWebSocketUri;
  if (uri == null) {
    throw StateError('run through scripts/verify_remote_hosts.py (VM service)');
  }
  final client = await vm_io.vmServiceConnectUri(uri.toString());
  final isolate = developer.Service.getIsolateId(Isolate.current)!;
  return () async {
    final vm.AllocationProfile profile = await client.getAllocationProfile(
      isolate,
      gc: true,
    );
    return profile.memoryUsage!.heapUsage!;
  };
}

void main() {
  final minutes = int.parse(
    Platform.environment['PROCESSLAMA_SOAK_MINUTES'] ?? '120',
  );
  // A tenth of the run, at least two minutes, warms caches and the heap.
  final warmUp = math.max(2, minutes ~/ 10);

  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        _fixture('PROCESSLAMA_NATIVE_LIBRARY'),
      ),
    );
  });

  test('memory stays flat while streaming for $minutes min', () async {
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
    final workflows = RemoteHostWorkflows(remoteHosts: service, port: _Port());
    final profile = await service.addProfile(
      RemoteHostProfileDraft(sshAlias: _fixture('PROCESSLAMA_TEST_ALIAS')),
    );
    expect(
      (await workflows.connect(profile.id)).phase,
      RemoteConnectionPhase.live,
    );
    final source = service.createSource(profile.id)!;
    final session = ProcessSession(
      source: source,
      snapshotRepository: _NoSnapshots(),
      repositoryOperationTracker: _NoTracking(),
    );
    var samples = 0;
    var topologies = 0;
    ProcessTopology? lastTopology;
    source.updates.listen((sample) {
      samples++;
      if (!identical(sample.topology, lastTopology)) {
        topologies++;
        lastTopology = sample.topology;
      }
    });
    await source.setCadence(const ProcessCadence.live(Duration(seconds: 1)));

    final retainedHeap = await _retainedHeapProbe();
    final at = <double>[];
    final helper = <int>[];
    final app = <int>[];
    final heap = <int>[];
    final started = DateTime.now();
    for (var minute = 0; minute <= minutes; minute++) {
      final due = started.add(Duration(minutes: minute));
      final wait = due.difference(DateTime.now());
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
      expect(
        service.connectionState(profile.id).value.phase,
        RemoteConnectionPhase.live,
        reason: 'the connection stays up through the soak',
      );
      at.add(minute.toDouble());
      helper.add(await _helperRss(container));
      app.add(ProcessInfo.currentRss);
      heap.add(await retainedHeap());
      // ignore: avoid_print
      print(
        'SOAK_SAMPLE minute=$minute helperRss=${helper.last} '
        'appRss=${app.last} heap=${heap.last} samples=$samples '
        'topologies=$topologies',
      );
    }

    await session.dispose();
    await source.dispose();
    expect(await workflows.removeHelper(profile.id), RemoteInstallResult.ok);
    await service.dispose();

    final steadyAt = at.sublist(warmUp);
    final steadyHelper = helper.sublist(warmUp);
    final steadyApp = app.sublist(warmUp);
    final steadyHeap = heap.sublist(warmUp);
    final helperMean =
        steadyHelper.reduce((a, b) => a + b) / steadyHelper.length;
    final helperSpread = steadyHelper
        .map((value) => (value - helperMean).abs() / helperMean)
        .reduce(math.max);
    final helperSlope = _slopePerHour(steadyAt, steadyHelper);
    final appSlope = _slopePerHour(steadyAt, steadyApp);
    final heapSlope = _slopePerHour(steadyAt, steadyHeap);
    // ignore: avoid_print
    print(
      'SOAK minutes=$minutes warmUp=$warmUp samples=$samples '
      'topologies=$topologies '
      'helperRssMiB=${(helperMean / _mib).toStringAsFixed(1)} '
      'helperSpread=${(helperSpread * 100).toStringAsFixed(1)}% '
      'helperSlopeMiBPerHour=${(helperSlope / _mib).toStringAsFixed(2)} '
      'appRssMiB=${(steadyApp.last / _mib).toStringAsFixed(1)} '
      'appSlopeMiBPerHour=${(appSlope / _mib).toStringAsFixed(2)} '
      'heapMiB=${(steadyHeap.last / _mib).toStringAsFixed(1)} '
      'heapSlopeMiBPerHour=${(heapSlope / _mib).toStringAsFixed(2)}',
    );
    expect(samples, greaterThan(minutes * 50), reason: 'about 1 sample/s');
    expect(helperSpread, lessThanOrEqualTo(0.10));
    expect(helperSlope / _mib, lessThan(1));
    expect(heapSlope / _mib, lessThan(1));
  }, timeout: Timeout(Duration(minutes: minutes + 10)));
}
