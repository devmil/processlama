// The --mac lane of scripts/verify_remote_hosts.py: probe, install, connect
// and uninstall against the macOS test host. Fails rather than skips without
// the lane's fixture.
@TestOn('linux || mac-os')
library;

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

void main() {
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        _fixture('PROCESSLAMA_NATIVE_LIBRARY'),
      ),
    );
  });

  test('probe, install, connect and uninstall on macOS', () async {
    final alias = _fixture('PROCESSLAMA_TEST_ALIAS');
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

    final probe = await service.testConnection(alias);
    expect(probe.outcome, RemoteProbeOutcome.helperMissing);
    expect(probe.target, RemoteHelperTarget.macosArm64);

    final profile = await service.addProfile(
      RemoteHostProfileDraft(sshAlias: alias),
    );
    final state = await workflows.connect(profile.id);
    expect(state.phase, RemoteConnectionPhase.live, reason: '${state.failure}');
    expect(state.hello!.facts.target, RemoteHelperTarget.macosArm64);
    expect(
      state.hello!.capabilities.operatingSystem,
      HostOperatingSystem.macos,
    );
    expect(state.hello!.capabilities.networkSource, NetworkRateSource.nettop);
    expect(state.hello!.capabilities.inspectorSecurity, isTrue);
    expect(
      (await service.testConnection(alias)).outcome,
      RemoteProbeOutcome.ready,
    );

    final source = service.createSource(profile.id)!;
    final samples = <ProcessSnapshot>[];
    source.updates.listen(samples.add);
    await source.setCadence(const ProcessCadence.live(Duration(seconds: 1)));
    for (var attempt = 0; attempt < 200 && samples.isEmpty; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(samples, isNotEmpty);
    final processes = samples.last.processes;
    expect(processes.length, greaterThan(50));
    // Which inspector sections an SSH session without TCC grants can read.
    final restricted = <String, Set<String>>{};
    final probes = [
      ...processes.where((record) => record.uid != 0).take(10),
      ...processes.where((record) => record.uid == 0).take(10),
    ];
    for (final record in probes) {
      final detail = await source.fetchDetail(record.identity);
      if (detail == null) continue;
      final owner = record.uid == 0 ? 'root' : 'own';
      for (final (name, section) in [
        ('files', detail.files),
        ('sockets', detail.sockets),
        ('threads', detail.threads),
        ('security', detail.security),
      ]) {
        final state = switch (section) {
          ProcessDetailAvailable() => 'available',
          ProcessDetailRestricted() => 'restricted',
          ProcessDetailUnsupported() => 'unsupported',
          ProcessDetailNotFound() => 'notFound',
        };
        restricted.putIfAbsent('$owner.$name', () => <String>{}).add(state);
      }
    }
    // ignore: avoid_print
    print('MAC_RESTRICTED_SECTIONS $restricted');
    await source.dispose();

    expect(await workflows.removeHelper(profile.id), RemoteInstallResult.ok);
    expect(
      (await service.testConnection(alias)).outcome,
      RemoteProbeOutcome.helperMissing,
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
