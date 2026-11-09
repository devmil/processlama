// The --disconnect-matrix lane of scripts/verify_remote_hosts.py: streams an
// Ubuntu 22.04 sshd container, breaks the connection in each documented way
// and checks the phases, the failure code, that the tab keeps its last
// sample while stale, that histories show a gap, and that no process is
// reported gone because of the outage. Prints one DISCONNECT line per case.
@TestOn('linux')
library;

import 'dart:io' hide ProcessSignal;
import 'dart:io' as io show ProcessSignal;

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

late final String _container;
late final String _alias;
late final String _sshConfig;

Future<String> _exec(List<String> command, {bool check = true}) async {
  final result = await Process.run('podman', ['exec', _container, ...command]);
  if (check) {
    expect(result.exitCode, 0, reason: '$command: ${result.stderr}');
  }
  return '${result.stdout}';
}

/// The PIDs of the helper processes in the container.
Future<List<int>> _helperPids() async => [
  for (final line in (await _exec([
    'pgrep',
    '-f',
    'processlama-remote-helper',
  ], check: false)).split('\n'))
    ?int.tryParse(line.trim()),
];

/// The local ssh client carrying the helper channel.
Future<List<int>> _sshPids() async {
  final listing = await Process.run('ps', ['-eo', 'pid=,comm=,args=']);
  return [
    for (final line in '${listing.stdout}'.split('\n'))
      if (line.trim().split(RegExp(r'\s+')) case [
        final pid,
        'ssh',
        ...final args,
      ])
        if (args.contains(_sshConfig) && args.contains(_alias)) int.parse(pid),
  ];
}

Future<void> _until(
  bool Function() condition,
  Duration timeout,
  String what,
) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out after ${timeout.inSeconds} s waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

/// Runs a tc command for every interface, loopback included: pasta splices
/// forwarded local connections through the container's loopback.
Future<String> _tcEverywhere(String arguments) => _exec([
  'sh',
  '-c',
  'for device in \$(ls /sys/class/net); do tc qdisc $arguments; done',
]);

/// One way of breaking the connection.
final class _Case {
  const _Case({
    required this.name,
    required this.breakIt,
    required this.codes,
    this.restore,
    this.outage = Duration.zero,
    this.recovers = true,
  });

  final String name;
  final Future<void> Function() breakIt;

  /// Undoes [breakIt] after [outage].
  final Future<void> Function()? restore;
  final Duration outage;

  /// The failure codes the host may report for this break.
  final Set<RemoteFailureCode> codes;

  /// Whether the tab comes back on its own, or stays stale.
  final bool recovers;
}

final _cases = <_Case>[
  _Case(
    name: 'ssh-killed',
    breakIt: () async {
      final pids = await _sshPids();
      expect(pids, isNotEmpty, reason: 'the ssh client is found');
      for (final pid in pids) {
        Process.killPid(pid, io.ProcessSignal.sigkill);
      }
    },
    codes: {RemoteFailureCode.sshConnectionFailed},
  ),
  _Case(
    name: 'helper-killed',
    breakIt: () async {
      expect(await _helperPids(), hasLength(1));
      await _exec(['pkill', '-KILL', '-f', 'processlama-remote-helper']);
    },
    codes: {RemoteFailureCode.sshConnectionFailed},
  ),
  _Case(
    name: 'stdout-stalled',
    breakIt: () async {
      expect(await _helperPids(), hasLength(1));
      await _exec(['pkill', '-STOP', '-f', 'processlama-remote-helper']);
    },
    codes: {RemoteFailureCode.heartbeatLost},
  ),
  _Case(
    name: 'network-cut',
    breakIt: () => _tcEverywhere(r'add dev "$device" root netem loss 100%'),
    outage: const Duration(seconds: 70),
    restore: () => _tcEverywhere(r'del dev "$device" root'),
    codes: {
      RemoteFailureCode.heartbeatLost,
      RemoteFailureCode.sshConnectionFailed,
    },
  ),
  _Case(
    name: 'helper-removed',
    breakIt: () async {
      await _exec([
        'rm',
        '-rf',
        '/home/tester/.local/lib/processlama',
        '/home/tester/.cache/processlama',
      ]);
      for (final pid in await _sshPids()) {
        Process.killPid(pid, io.ProcessSignal.sigkill);
      }
    },
    codes: {RemoteFailureCode.sshConnectionFailed},
    recovers: false,
  ),
];

void main() {
  late RemoteHostServiceImpl service;
  late RemoteHostWorkflows workflows;
  late RemoteHostProfile profile;

  setUpAll(() async {
    _container = _fixture('PROCESSLAMA_TEST_CONTAINER');
    _alias = _fixture('PROCESSLAMA_TEST_ALIAS');
    _sshConfig = _fixture('PROCESSLAMA_SSH_CONFIG');
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        _fixture('PROCESSLAMA_NATIVE_LIBRARY'),
      ),
    );
    final settings = SettingsServiceImpl(
      settingsRepository: _NoAppSettings(),
      remoteHostsRepository: MemoryRemoteHostsSettingsRepository(),
    );
    await settings.initialize();
    service = RemoteHostServiceImpl(
      connections: SshRemoteConnectionRepository(configFile: _sshConfig),
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
    workflows = RemoteHostWorkflows(remoteHosts: service, port: _Port());
    profile = await service.addProfile(
      RemoteHostProfileDraft(sshAlias: _alias),
    );
    await _exec(['su', 'tester', '-c', 'setsid sleep 3600 >/dev/null 2>&1 &']);
  });

  tearDownAll(() async {
    await workflows.removeHelper(profile.id);
    await service.dispose();
  });

  for (final scenario in _cases) {
    test(scenario.name, () async {
      final connected = await workflows.connect(profile.id);
      expect(connected.phase, RemoteConnectionPhase.live);
      final source = service.createSource(profile.id)!;
      final session = ProcessSession(
        source: source,
        snapshotRepository: _NoSnapshots(),
        repositoryOperationTracker: _NoTracking(),
      );
      addTearDown(() async {
        await session.dispose();
        await source.dispose();
        await service.disconnect(profile.id);
      });
      final samples = <(DateTime, ProcessSnapshot)>[];
      source.updates.listen((sample) => samples.add((DateTime.now(), sample)));
      final hostPhases = <RemoteConnectionPhase>[];
      final hostState = service.connectionState(profile.id);
      void onHost() => hostPhases.add(hostState.value.phase);
      hostState.addListener(onHost);
      addTearDown(() => hostState.removeListener(onHost));
      final sourcePhases = <ProcessSourcePhase>[];
      void onSource() => sourcePhases.add(source.state.value.phase);
      source.state.addListener(onSource);
      addTearDown(() => source.state.removeListener(onSource));
      await source.setCadence(const ProcessCadence.live(Duration(seconds: 1)));

      bool hasSleeper(ProcessSnapshot snapshot) => snapshot.processes.any(
        (record) => record.name == 'sleep' && record.uid == 1000,
      );
      await _until(
        () => samples.length >= 3 && hasSleeper(samples.last.$2),
        const Duration(seconds: 30),
        'a live tree with the sleeper',
      );
      final sleeper = samples.last.$2.processes.firstWhere(
        (record) => record.name == 'sleep' && record.uid == 1000,
      );

      final brokenAt = DateTime.now();
      await scenario.breakIt();
      await _until(
        () => hostState.value.phase != RemoteConnectionPhase.live,
        const Duration(seconds: 90),
        'the host to leave live',
      );
      // A sample in flight when the connection broke may still land.
      final before = samples.length;
      final failure = hostState.value.failure;
      expect(scenario.codes, contains(failure), reason: '$failure');
      await _until(
        () => source.state.value.phase == ProcessSourcePhase.stale,
        const Duration(seconds: 5),
        'the tab to turn stale',
      );
      // The last sample stays visible: the session still shows the sleeper.
      expect(hasSleeper(session.snapshot.value), isTrue);

      if (scenario.restore case final restore?) {
        final elapsed = DateTime.now().difference(brokenAt);
        if (elapsed < scenario.outage) {
          await Future<void>.delayed(scenario.outage - elapsed);
        }
        await restore();
      }
      final restoredAt = DateTime.now();

      String outcome;
      if (scenario.recovers) {
        await _until(
          () =>
              hostState.value.phase == RemoteConnectionPhase.live &&
              samples.length > before + 1,
          const Duration(minutes: 3),
          'the host to reconnect and stream again',
        );
        expect(source.state.value.phase, ProcessSourcePhase.live);
        expect(hostPhases, contains(RemoteConnectionPhase.reconnecting));
        final after = samples.last.$2;
        expect(
          after.processes.any((record) => record.identity == sleeper.identity),
          isTrue,
          reason: 'the sleeper keeps its identity across the reconnect',
        );
        final row = session.tree.value.visibleRows.firstWhere(
          (row) => row.record.identity == sleeper.identity,
          orElse: () => fail('the sleeper row is gone'),
        );
        expect(
          row.cpuHistory.any((value) => value.isNaN),
          isTrue,
          reason: 'the history shows a gap across the outage',
        );
        outcome =
            'recovered=${DateTime.now().difference(restoredAt).inMilliseconds}ms';
      } else {
        // The reconnect finds no helper: the tab stays stale with its sample.
        await _until(
          () =>
              hostState.value.phase == RemoteConnectionPhase.failed ||
              hostState.value.phase == RemoteConnectionPhase.disconnected,
          const Duration(seconds: 60),
          'the reconnect to give up',
        );
        expect(hostState.value.failure, RemoteFailureCode.helperNotInstalled);
        expect(source.state.value.phase, ProcessSourcePhase.stale);
        expect(samples.length, before);
        expect(hasSleeper(session.snapshot.value), isTrue);
        outcome = 'stale failure=${hostState.value.failure!.name}';
      }
      // No sample of the whole case lost the sleeper.
      expect(samples.every((sample) => hasSleeper(sample.$2)), isTrue);
      expect(
        sourcePhases.where((phase) => phase == ProcessSourcePhase.failed),
        isEmpty,
        reason: 'a tab with a sample never turns failed',
      );

      if (scenario.name == 'stdout-stalled') {
        // The stalled helper resumes, finds its channel closed and exits.
        await _exec(['pkill', '-CONT', '-f', 'processlama-remote-helper']);
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while ((await _helperPids()).length > 1 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        expect(await _helperPids(), hasLength(1));
      }
      // ignore: avoid_print
      print(
        'DISCONNECT case=${scenario.name} failure=${failure!.name} '
        'phases=${hostPhases.map((phase) => phase.name).toSet().join('>')} '
        '$outcome',
      );
    }, timeout: const Timeout(Duration(minutes: 6)));
  }
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
