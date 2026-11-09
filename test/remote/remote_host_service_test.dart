import 'dart:async';
import 'dart:typed_data';

import 'package:devmil_remote/devmil_remote.dart';
import 'package:devmil_remote/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/repositories.dart';
import 'package:processlama/repositories/impl/remote/wire/contract.g.dart';
import 'package:processlama/services/impl/remote_host_service_impl.dart';
import 'package:processlama/services/impl/settings_service_impl.dart';
import 'package:processlama/services/services.dart';

const _facts = RemoteHostFacts(
  target: RemoteHelperTarget.linuxX8664,
  kernel: '6.8',
  hostInstanceId: '0123456789abcdef0123456789abcdef',
  hostnameHash: '0123456789abcdef',
  helperBuildId: remoteHelperBuildId,
  compatibility: remoteHelperCompatibility,
  processtreeRevision: 'a9aed83',
  uid: 1000,
);

void main() {
  late _FakeConnections connections;
  late SettingsServiceImpl settings;
  late FakeTimers timers;
  late RemoteHostServiceImpl service;

  setUp(() async {
    connections = _FakeConnections();
    settings = SettingsServiceImpl(
      settingsRepository: _NoAppSettings(),
      remoteHostsRepository: MemoryRemoteHostsSettingsRepository(),
    );
    await settings.initialize();
    timers = FakeTimers();
    service = RemoteHostServiceImpl(
      connections: connections,
      artifacts: _FakeArtifacts(),
      remoteHostsSettings: settings,
      settingsService: settings,
      reconnectorFactory: ({required attempt, required onExhausted}) =>
          RemoteReconnector(
            attempt: attempt,
            onExhausted: onExhausted,
            timer: timers.call,
            clock: () => timers.now,
          ),
    );
  });

  Future<RemoteHostProfile> addProfile({bool autoInstall = false}) =>
      service.addProfile(
        RemoteHostProfileDraft(
          sshAlias: 'build-box',
          autoInstallHelper: autoInstall,
        ),
      );

  Future<void> advance(Duration duration) async {
    final end = timers.now + duration;
    while (timers.now < end) {
      timers.elapse(const Duration(seconds: 1));
      await settle();
    }
  }

  test('a connection goes live, records facts and prunes once', () async {
    final profile = await addProfile();
    connections.outcomes.add(_FakeConnection());

    final state = await service.connect(profile.id);

    expect(state.phase, RemoteConnectionPhase.live);
    expect(state.hello!.facts, _facts);
    await settle();
    expect(settings.remoteHosts.value.profile(profile.id)!.lastKnown, _facts);
    expect(connections.prunes, [remoteHelperBuildId]);
    expect(RemoteHostProfile.isValidAlias(profile.sshAlias), isTrue);
    expect(profile.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
  });

  test(
    'a missing helper is reported, not installed, without consent',
    () async {
      final profile = await addProfile();
      connections.outcomes.add(_missing());

      final state = await service.connect(profile.id);

      expect(state.phase, RemoteConnectionPhase.failed);
      expect(state.needsHelper, isTrue);
      expect(state.missingTarget, RemoteHelperTarget.linuxArm64);
      expect(connections.installs, isEmpty);
    },
  );

  test('auto-install installs a missing helper and connects', () async {
    final profile = await addProfile(autoInstall: true);
    connections.outcomes
      ..add(_missing())
      ..add(_FakeConnection());

    final state = await service.connect(profile.id);

    expect(state.phase, RemoteConnectionPhase.live);
    expect(connections.installs, [RemoteHelperTarget.linuxArm64]);
  });

  test('a failed auto-install reports its typed code', () async {
    final profile = await addProfile(autoInstall: true);
    connections.outcomes.add(_missing());
    connections.installResult = RemoteInstallResult.noexec;

    final state = await service.connect(profile.id);

    expect(state.phase, RemoteConnectionPhase.failed);
    expect(state.failure, RemoteFailureCode.installNoexec);
  });

  test('a lost connection reconnects on the bounded schedule', () async {
    final profile = await addProfile();
    final first = _FakeConnection();
    connections.outcomes.add(first);
    final lease = service.acquire(profile.id);
    await settle();
    expect(lease.connection.value, same(first));

    connections.outcomes
      ..add(const RemoteHostException(RemoteFailureCode.sshConnectionFailed))
      ..add(_FakeConnection());
    first.fail(RemoteFailureCode.heartbeatLost);
    await settle();
    expect(lease.state.value.phase, RemoteConnectionPhase.reconnecting);
    expect(lease.connection.value, isNull);

    await advance(const Duration(seconds: 2));
    expect(lease.state.value.phase, RemoteConnectionPhase.reconnecting);
    await advance(const Duration(seconds: 5));
    expect(lease.state.value.phase, RemoteConnectionPhase.live);
    expect(lease.connection.value, isNotNull);
    await lease.release();
  });

  test('reconnecting stops after the window and stays stale', () async {
    final profile = await addProfile();
    final first = _FakeConnection();
    connections.outcomes.add(first);
    final lease = service.acquire(profile.id);
    await settle();
    connections.fallback = const RemoteHostException(
      RemoteFailureCode.sshConnectionFailed,
    );
    first.fail(RemoteFailureCode.sshConnectionFailed);
    await settle();

    await advance(const Duration(minutes: 11));

    expect(lease.state.value.phase, RemoteConnectionPhase.disconnected);
    expect(lease.state.value.failure, RemoteFailureCode.sshConnectionFailed);
    final attempts = connections.connects;
    await advance(const Duration(minutes: 5));
    expect(connections.connects, attempts);
    await lease.release();
  });

  test('failures that need the user are not retried', () async {
    final profile = await addProfile();
    final first = _FakeConnection();
    connections.outcomes.add(first);
    final lease = service.acquire(profile.id);
    await settle();
    first.fail(RemoteFailureCode.protocolMismatch);
    await settle();
    await advance(const Duration(minutes: 1));
    expect(lease.state.value.phase, RemoteConnectionPhase.disconnected);
    expect(connections.connects, 1);
    await lease.release();
  });

  test('profiles without auto-reconnect stay disconnected', () async {
    final profile = await addProfile();
    await service.updateProfile(profile.copyWith(autoReconnect: false));
    final first = _FakeConnection();
    connections.outcomes.add(first);
    final lease = service.acquire(profile.id);
    await settle();
    first.fail(RemoteFailureCode.heartbeatLost);
    await settle();
    await advance(const Duration(minutes: 1));
    expect(lease.state.value.phase, RemoteConnectionPhase.disconnected);
    expect(connections.connects, 1);
    await lease.release();
  });

  test('the connection closes when its last lease is released', () async {
    final profile = await addProfile();
    final connection = _FakeConnection();
    connections.outcomes.add(connection);
    final first = service.acquire(profile.id);
    final second = service.acquire(profile.id);
    await settle();
    expect(connections.connects, 1, reason: 'one connection per profile');

    await first.release();
    expect(connection.closedByClient, isFalse);
    await second.release();
    expect(connection.closedByClient, isTrue);
    expect(
      service.connectionState(profile.id).value.phase,
      RemoteConnectionPhase.disconnected,
    );
  });

  test('a connection finishing after disconnect is closed', () async {
    final profile = await addProfile();
    final gate = Completer<RemoteHelperConnection>();
    connections.pending = gate;
    final attempt = service.connect(profile.id);
    await settle();
    await service.disconnect(profile.id);
    final late = _FakeConnection();
    gate.complete(late);
    await attempt;
    expect(late.closedByClient, isTrue);
    expect(
      service.connectionState(profile.id).value.phase,
      RemoteConnectionPhase.disconnected,
    );
  });

  test('changing the alias disconnects the old host', () async {
    final profile = await addProfile();
    final connection = _FakeConnection();
    connections.outcomes.add(connection);
    await service.connect(profile.id);
    await service.updateProfile(profile.copyWith(sshAlias: 'other-box'));
    expect(connection.closedByClient, isTrue);
  });

  test('test connection maps typed outcomes', () async {
    connections.outcomes
      ..add(_FakeConnection())
      ..add(_missing())
      ..add(const RemoteHostException(RemoteFailureCode.sshConnectionFailed))
      ..add(const RemoteHostException(RemoteFailureCode.unsupportedPlatform))
      ..add(const RemoteHostException(RemoteFailureCode.helperOutdated));
    final outcomes = [
      for (var index = 0; index < 5; index++)
        (await service.testConnection('build-box')).outcome,
    ];
    expect(outcomes, [
      RemoteProbeOutcome.ready,
      RemoteProbeOutcome.helperMissing,
      RemoteProbeOutcome.sshUnreachable,
      RemoteProbeOutcome.unsupportedPlatform,
      RemoteProbeOutcome.helperOutdated,
    ]);
  });

  test('removing the helper disconnects first and keeps the profile', () async {
    final profile = await addProfile();
    final connection = _FakeConnection();
    connections.outcomes.add(connection);
    await service.connect(profile.id);
    final result = await service.removeHelper(profile.id);
    expect(result, RemoteInstallResult.ok);
    expect(connection.closedByClient, isTrue);
    expect(connections.removals, 1);
    expect(settings.remoteHosts.value.profile(profile.id), isNotNull);
  });

  test('background cadence follows the profile, then the default', () async {
    final profile = await addProfile();
    expect(
      service.backgroundCadenceFor(profile.id),
      const ProcessCadence.background(defaultBackgroundRefreshInterval),
    );
    await service.updateProfile(
      profile.copyWith(backgroundRefresh: () => BackgroundRefreshMode.paused),
    );
    expect(service.backgroundCadenceFor(profile.id), ProcessCadence.paused);
  });

  group('workflows', () {
    late _FakePort port;
    late RemoteHostWorkflows workflows;

    setUp(() {
      port = _FakePort();
      workflows = RemoteHostWorkflows(remoteHosts: service, port: port);
    });

    test('a confirmed install connects afterwards', () async {
      final profile = await addProfile();
      connections.outcomes
        ..add(_missing())
        ..add(_FakeConnection());
      port.choice = RemoteInstallChoice.install;

      final state = await workflows.connect(profile.id);

      expect(state.phase, RemoteConnectionPhase.live);
      expect(port.requests.single.target, RemoteHelperTarget.linuxArm64);
      expect(port.requests.single.isUpdate, isFalse);
      expect(port.requests.single.installPath, contains(remoteHelperBuildId));
      expect(port.reports.map((report) => report.kind), [
        RemoteHostReportKind.helperInstalled,
      ]);
      expect(
        settings.remoteHosts.value.profile(profile.id)!.autoInstallHelper,
        isFalse,
      );
    });

    test('install and always install remembers the choice', () async {
      final profile = await addProfile();
      connections.outcomes
        ..add(_missing())
        ..add(_FakeConnection());
      port.choice = RemoteInstallChoice.installAlways;
      await workflows.connect(profile.id);
      expect(
        settings.remoteHosts.value.profile(profile.id)!.autoInstallHelper,
        isTrue,
      );
    });

    test('an update is offered when an older build was known', () async {
      final profile = await addProfile();
      await settings.updateRemoteHostFacts(
        profile.id,
        const RemoteHostFacts(
          target: RemoteHelperTarget.linuxArm64,
          kernel: '6.8',
          hostInstanceId: '0123456789abcdef0123456789abcdef',
          hostnameHash: '0123456789abcdef',
          helperBuildId: '0000000000000000000000000000000000000000',
          compatibility: 0,
          processtreeRevision: 'a9aed83',
          uid: 1000,
        ),
      );
      connections.outcomes.add(_missing());
      port.choice = RemoteInstallChoice.cancel;
      await workflows.connect(profile.id);
      expect(port.requests.single.isUpdate, isTrue);
      expect(connections.installs, isEmpty);
    });

    test('a window closing during an install hears nothing more', () async {
      final profile = await addProfile();
      connections.outcomes
        ..add(_missing())
        ..add(_FakeConnection());
      port.choice = RemoteInstallChoice.install;
      final installing = Completer<void>();
      connections.installGate = installing;
      final flow = workflows.connect(profile.id);
      await settle();
      expect(connections.installs, hasLength(1));
      port.active = false;
      installing.complete();
      final state = await flow;
      expect(state.phase, RemoteConnectionPhase.live);
      expect(port.reports, isEmpty);
    });

    test('a failed connection is reported with its code', () async {
      final profile = await addProfile();
      connections.outcomes.add(
        const RemoteHostException(RemoteFailureCode.unsupportedPlatform),
      );
      await workflows.connect(profile.id);
      expect(port.reports.single.kind, RemoteHostReportKind.connectFailed);
      expect(
        port.reports.single.failure,
        RemoteFailureCode.unsupportedPlatform,
      );
    });

    test('helper removal needs confirmation', () async {
      final profile = await addProfile();
      port.removalConfirmed = false;
      expect(await workflows.removeHelper(profile.id), isNull);
      expect(connections.removals, 0);
      port.removalConfirmed = true;
      expect(await workflows.removeHelper(profile.id), RemoteInstallResult.ok);
      expect(port.reports.last.kind, RemoteHostReportKind.helperRemoved);
    });
  });
}

RemoteHostException _missing() => const RemoteHostException(
  RemoteFailureCode.helperNotInstalled,
  hostTarget: RemoteHelperTarget.linuxArm64,
);

final class _FakeConnection implements RemoteHelperConnection {
  final _closed = Completer<RemoteFailureCode?>();
  var closedByClient = false;

  void fail(RemoteFailureCode code) {
    if (!_closed.isCompleted) _closed.complete(code);
  }

  @override
  RemoteHelperHello get hello => const RemoteHelperHello(
    facts: _facts,
    capabilities: HostCapabilities(operatingSystem: HostOperatingSystem.linux),
  );

  @override
  bool get isOpen => !_closed.isCompleted;

  @override
  Future<RemoteFailureCode?> get closed => _closed.future;

  @override
  Future<Object?> call(
    String method,
    Map<String, Object?> arguments, {
    bool bulk = false,
  }) async => null;

  @override
  Future<RemoteHelperSubscription> subscribe(
    String topic,
    Map<String, Object?> arguments, {
    int initialCredit = 2,
  }) => throw UnimplementedError();

  @override
  Future<RemoteTelemetryStream> subscribeTelemetry({
    required int? cadenceMs,
    required int pollingMs,
  }) => throw UnimplementedError();

  @override
  Future<ProcessDetail> fetchDetail(ProcessIdentity identity) =>
      throw UnimplementedError();

  @override
  Future<SignalOutcome> sendSignal(
    ProcessIdentity identity,
    ProcessSignal signal,
  ) => throw UnimplementedError();

  @override
  Future<Map<String, Uint8List>> fetchIcons(List<String> hashes) async =>
      const {};

  @override
  Future<void> close() async {
    closedByClient = true;
    if (!_closed.isCompleted) _closed.complete(null);
  }
}

final class _FakeConnections implements RemoteConnectionRepository {
  final outcomes = <Object>[];
  Object? fallback;
  Completer<RemoteHelperConnection>? pending;
  Completer<void>? installGate;
  RemoteInstallResult installResult = RemoteInstallResult.ok;
  final installs = <RemoteHelperTarget>[];
  final prunes = <String>[];
  var removals = 0;
  var connects = 0;

  @override
  Future<RemoteHelperConnection> connect(
    String alias, {
    Future<void>? cancel,
  }) async {
    connects++;
    final waiting = pending;
    if (waiting != null) {
      pending = null;
      return waiting.future;
    }
    final outcome = outcomes.isEmpty ? fallback : outcomes.removeAt(0);
    if (outcome is RemoteHelperConnection) return outcome;
    if (outcome is RemoteHostException) throw outcome;
    throw const RemoteHostException(RemoteFailureCode.internal);
  }

  @override
  Future<RemoteInstallResult> installHelper(
    String alias,
    RemoteHelperArtifact artifact, {
    Future<void>? cancel,
  }) async {
    installs.add(artifact.target);
    await installGate?.future;
    return installResult;
  }

  @override
  Future<void> pruneHelpers(String alias, {required String keepBuildId}) async {
    prunes.add(keepBuildId);
  }

  @override
  Future<RemoteInstallResult> removeHelpers(String alias) async {
    removals++;
    return RemoteInstallResult.ok;
  }
}

final class _FakeArtifacts implements RemoteHelperArtifactRepository {
  @override
  Future<RemoteHelperArtifact?> bundledHelper(
    RemoteHelperTarget target,
  ) async => RemoteHelperArtifact(
    target: target,
    buildId: remoteHelperBuildId,
    size: 4,
    sha256: 'a' * 64,
    read: () async => Uint8List(4),
  );
}

final class _FakePort implements RemoteHostInteractionPort {
  var active = true;
  RemoteInstallChoice choice = RemoteInstallChoice.cancel;
  var removalConfirmed = true;
  final requests = <RemoteInstallRequest>[];
  final reports = <RemoteHostReport>[];

  @override
  bool get isActive => active;

  @override
  Future<RemoteInstallChoice> confirmInstall(
    RemoteInstallRequest request,
  ) async {
    requests.add(request);
    return choice;
  }

  @override
  Future<bool> confirmHelperRemoval(RemoteHostProfile profile) async =>
      removalConfirmed;

  @override
  void report(RemoteHostReport report) => reports.add(report);
}

class _NoAppSettings implements SettingsRepository {
  @override
  Future<AppSettings> getSettings() async => const AppSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
