// The --ssh-loopback lane of scripts/verify_remote_hosts.py: real OpenSSH to
// a user-mode sshd with an isolated remote home, driving the real remote host
// service, workflows and Rust-owned SSH processes. Fails rather than skips
// when the lane's fixture is missing.
@TestOn('linux || mac-os')
library;

import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/repositories.dart';
import 'package:processlama/repositories/impl/remote/bundled_remote_helper_repository.dart';
import 'package:processlama/repositories/impl/remote/ssh_remote_connection_repository.dart';
import 'package:processlama/repositories/impl/remote/wire/contract.g.dart';
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
  final reports = <RemoteHostReport>[];

  @override
  bool get isActive => true;

  @override
  Future<RemoteInstallChoice> confirmInstall(
    RemoteInstallRequest request,
  ) async => RemoteInstallChoice.install;

  @override
  Future<bool> confirmHelperRemoval(RemoteHostProfile profile) async => true;

  @override
  void report(RemoteHostReport report) => reports.add(report);
}

class _NoAppSettings implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late String alias;
  late String untrustedAlias;
  late Directory remoteHome;
  late RemoteHostServiceImpl service;
  late RemoteHostWorkflows workflows;
  late _Port port;
  late SettingsServiceImpl settings;

  Directory installRoot() =>
      Directory('${remoteHome.path}/.local/lib/processlama');

  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        _fixture('PROCESSLAMA_NATIVE_LIBRARY'),
      ),
    );
  });

  setUp(() async {
    alias = _fixture('PROCESSLAMA_TEST_ALIAS');
    untrustedAlias = _fixture('PROCESSLAMA_TEST_UNTRUSTED_ALIAS');
    remoteHome = Directory(_fixture('PROCESSLAMA_TEST_REMOTE_HOME'));
    settings = SettingsServiceImpl(
      settingsRepository: _NoAppSettings(),
      remoteHostsRepository: MemoryRemoteHostsSettingsRepository(),
    );
    await settings.initialize();
    service = RemoteHostServiceImpl(
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
    port = _Port();
    workflows = RemoteHostWorkflows(remoteHosts: service, port: port);
  });

  tearDown(() => service.dispose());

  test('an untrusted host key is only a connection failure', () async {
    final result = await service.testConnection(untrustedAlias);
    expect(result.outcome, RemoteProbeOutcome.sshUnreachable);
    expect(result.failure, RemoteFailureCode.sshConnectionFailed);
  });

  test('the probe reports the missing helper and the host platform', () async {
    final result = await service.testConnection(alias);
    expect(result.outcome, RemoteProbeOutcome.helperMissing);
    expect(result.target, isNotNull);
  });

  test('connecting installs after confirmation and goes live', () async {
    final profile = await service.addProfile(
      RemoteHostProfileDraft(sshAlias: alias),
    );
    final state = await workflows.connect(profile.id);
    expect(state.phase, RemoteConnectionPhase.live, reason: '${state.failure}');
    expect(port.reports.map((report) => report.kind), [
      RemoteHostReportKind.helperInstalled,
    ]);
    final helper = File(
      '${installRoot().path}/remote/$remoteHelperBuildId/'
      '$remoteHelperExecutable',
    );
    expect(helper.existsSync(), isTrue);
    expect(state.hello!.facts.helperBuildId, remoteHelperBuildId);
    expect(
      settings.remoteHosts.value.profile(profile.id)!.lastKnown,
      state.hello!.facts,
    );

    final probe = await service.testConnection(alias);
    expect(probe.outcome, RemoteProbeOutcome.ready);
  });

  test('disconnect and reconnect reuse the installed helper', () async {
    final profile = await service.addProfile(
      RemoteHostProfileDraft(sshAlias: alias),
    );
    expect(
      (await service.connect(profile.id)).phase,
      RemoteConnectionPhase.live,
    );
    await service.disconnect(profile.id);
    expect(
      service.connectionState(profile.id).value.phase,
      RemoteConnectionPhase.disconnected,
    );
    expect(
      (await service.connect(profile.id)).phase,
      RemoteConnectionPhase.live,
    );
    final connection = service.acquire(profile.id);
    expect(connection.connection.value, isNotNull);
    expect(
      await connection.connection.value!
          .call('process.nothing', const {})
          .then((_) => 'ok', onError: (Object error) => '$error'),
      contains('unsupportedCommand'),
    );
    await connection.release();
  });

  test('a tab streams the tree, details and a typed signal', () async {
    final profile = await service.addProfile(
      RemoteHostProfileDraft(sshAlias: alias),
    );
    expect(
      (await service.connect(profile.id)).phase,
      RemoteConnectionPhase.live,
    );
    final sleeper = await Process.start('sleep', ['600']);
    addTearDown(() => sleeper.kill());
    final source = service.createSource(profile.id)!;
    addTearDown(source.dispose);
    final samples = <ProcessSnapshot>[];
    source.updates.listen(samples.add);
    await source.setCadence(
      const ProcessCadence.live(Duration(milliseconds: 500)),
    );
    ProcessRecord? target;
    for (var attempt = 0; attempt < 100 && target == null; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      target = samples.lastOrNull?.processes
          .where((record) => record.pid == sleeper.pid)
          .firstOrNull;
    }
    expect(target, isNotNull, reason: 'the sleeper appears in the remote tree');
    expect(samples.last.processes.length, greaterThan(10));
    expect(samples.last.topology, isNotNull);
    expect(source.state.value.phase, ProcessSourcePhase.live);

    final detail = await source.fetchDetail(target!.identity);
    expect(detail, isNotNull);
    expect(
      detail!.files,
      isA<ProcessDetailAvailable<List<FileDescriptorInfo>>>(),
    );

    await source.sendSignal(target.identity, ProcessSignal.terminate);
    expect(await sleeper.exitCode, isNot(0));
    var gone = false;
    for (var attempt = 0; attempt < 50 && !gone; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      gone = !samples.last.processes.any((record) => record.pid == sleeper.pid);
    }
    expect(gone, isTrue);
    await expectLater(
      source.sendSignal(target.identity, ProcessSignal.terminate),
      throwsA(
        isA<ProcessSignalException>().having(
          (error) => error.outcome,
          'outcome',
          SignalOutcome.notFound,
        ),
      ),
    );
  });

  test('a connection prunes stale builds but keeps the current one', () async {
    final stale = Directory(
      '${installRoot().path}/remote/0000000000000000000000000000000000000000',
    )..createSync(recursive: true);
    await Process.run('touch', ['-t', '202001010000', stale.path]);
    final profile = await service.addProfile(
      RemoteHostProfileDraft(sshAlias: alias),
    );
    expect(
      (await service.connect(profile.id)).phase,
      RemoteConnectionPhase.live,
    );
    for (var attempt = 0; attempt < 100 && stale.existsSync(); attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(stale.existsSync(), isFalse);
    expect(
      Directory(
        '${installRoot().path}/remote/$remoteHelperBuildId',
      ).existsSync(),
      isTrue,
    );
  });

  test('removing the helper deletes it and its caches', () async {
    final cache = Directory('${remoteHome.path}/$remoteCacheRoot/icons')
      ..createSync(recursive: true);
    final profile = await service.addProfile(
      RemoteHostProfileDraft(sshAlias: alias),
    );
    expect(await workflows.removeHelper(profile.id), RemoteInstallResult.ok);
    expect(port.reports.last.kind, RemoteHostReportKind.helperRemoved);
    expect(installRoot().existsSync(), isFalse);
    expect(cache.existsSync(), isFalse);
    final probe = await service.testConnection(alias);
    expect(probe.outcome, RemoteProbeOutcome.helperMissing);
  });
}
