// The --containers lane of scripts/verify_remote_hosts.py: probe, install,
// connect and uninstall against Ubuntu 22.04 sshd containers (x86_64 and
// arm64 under qemu) and hostile variants, each with its expected typed
// outcome. Fails rather than skips without the lane's fixture.
@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

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

/// Streams the container's tree, sends `terminate` to a `sleep` started in
/// the container and checks the typed outcome and that the process leaves.
Future<void> _streamAndSignal(
  RemoteHostServiceImpl service,
  String profileId,
  String container,
) async {
  final started = await Process.run('podman', [
    'exec',
    '--user',
    'tester',
    '--detach',
    container,
    'sleep',
    '600',
  ]);
  expect(started.exitCode, 0);
  final source = service.createSource(profileId)!;
  addTearDown(source.dispose);
  final samples = <ProcessSnapshot>[];
  source.updates.listen(samples.add);
  await source.setCadence(const ProcessCadence.live(Duration(seconds: 1)));
  ProcessRecord? sleeper;
  for (var attempt = 0; attempt < 300 && sleeper == null; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    sleeper = samples.lastOrNull?.processes
        .where((record) => record.name == 'sleep')
        .firstOrNull;
  }
  expect(sleeper, isNotNull, reason: 'the container tree streams');
  expect(samples.last.processes.any((record) => record.name == 'sshd'), isTrue);
  await source.sendSignal(sleeper!.identity, ProcessSignal.terminate);
  var gone = false;
  for (var attempt = 0; attempt < 300 && !gone; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    gone = !samples.last.processes.any(
      (record) => record.identity == sleeper!.identity,
    );
  }
  expect(gone, isTrue, reason: 'the terminated process leaves the tree');
}

void main() {
  final hosts = (jsonDecode(_fixture('PROCESSLAMA_TEST_CONTAINERS')) as List)
      .cast<Map<String, Object?>>();

  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        _fixture('PROCESSLAMA_NATIVE_LIBRARY'),
      ),
    );
  });

  Future<(RemoteHostServiceImpl, RemoteHostWorkflows, _Port)> services() async {
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
    final port = _Port();
    addTearDown(service.dispose);
    return (
      service,
      RemoteHostWorkflows(remoteHosts: service, port: port),
      port,
    );
  }

  for (final host in hosts) {
    final alias = host['alias']! as String;
    final variant = host['variant']! as String;
    final arch = host['arch']! as String;
    final target = arch == 'arm64'
        ? RemoteHelperTarget.linuxArm64
        : RemoteHelperTarget.linuxX8664;

    test('$variant on $arch', () async {
      final (service, workflows, port) = await services();
      final probe = await service.testConnection(alias);
      final profile = await service.addProfile(
        RemoteHostProfileDraft(sshAlias: alias),
      );
      switch (variant) {
        case 'login-stdin':
          // The login script blocks on standard input: no hello arrives.
          expect(probe.failure, RemoteFailureCode.helperStartFailed);
          return;
        case 'noexec':
          expect(probe.outcome, RemoteProbeOutcome.helperMissing);
          final state = await workflows.connect(profile.id);
          expect(state.phase, RemoteConnectionPhase.failed);
          expect(state.failure, RemoteFailureCode.installNoexec);
          expect(port.reports.single.kind, RemoteHostReportKind.installFailed);
          expect(
            await workflows.removeHelper(profile.id),
            RemoteInstallResult.ok,
          );
          return;
      }
      expect(probe.outcome, RemoteProbeOutcome.helperMissing);
      expect(probe.target, target);
      final state = await workflows.connect(profile.id);
      expect(
        state.phase,
        RemoteConnectionPhase.live,
        reason: '${state.failure}',
      );
      if (variant == 'zsh') {
        // zsh is the login shell; the scripts still run under sh, so the
        // connection prunes the stale build the entrypoint planted.
        final stale = '/home/tester/.local/lib/processlama/remote/${'0' * 40}';
        var pruned = false;
        for (var attempt = 0; attempt < 100 && !pruned; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final probe = await Process.run('podman', [
            'exec',
            host['container']! as String,
            'test',
            '-e',
            stale,
          ]);
          pruned = probe.exitCode == 1;
        }
        expect(pruned, isTrue, reason: 'the stale build is pruned');
      }
      final capabilities = state.hello!.capabilities;
      expect(state.hello!.facts.target, target);
      expect(capabilities.hidepid, variant == 'hidepid');
      if (variant == 'ebpf') {
        expect(capabilities.networkSource, NetworkRateSource.ebpf);
      } else {
        expect(capabilities.networkSource, NetworkRateSource.none);
        expect(
          capabilities.networkUnavailableReason,
          NetworkUnavailableReason.serviceNotInstalled,
        );
      }
      expect(
        (await service.testConnection(alias)).outcome,
        RemoteProbeOutcome.ready,
      );
      if (variant == 'base') {
        await _streamAndSignal(
          service,
          profile.id,
          host['container']! as String,
        );
      }
      expect(await workflows.removeHelper(profile.id), RemoteInstallResult.ok);
      expect(
        (await service.testConnection(alias)).outcome,
        RemoteProbeOutcome.helperMissing,
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}
