import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/repositories.dart';
import 'package:processlama/services/impl/remote_process_source.dart';
import 'package:processlama/services/services.dart';

const _hello = RemoteHelperHello(
  facts: RemoteHostFacts(
    target: RemoteHelperTarget.linuxArm64,
    kernel: '6.8',
    hostInstanceId: '0123456789abcdef0123456789abcdef',
    hostnameHash: '0123456789abcdef',
    helperBuildId: '0000000000000000000000000000000000000001',
    compatibility: 1,
    processtreeRevision: 'a9aed83',
    uid: 1000,
  ),
  capabilities: HostCapabilities(
    operatingSystem: HostOperatingSystem.linux,
    signals: true,
  ),
);

ProcessSnapshot _snapshot(int at) => ProcessSnapshot(
  generatedAtUnixMs: at,
  platform: 'linux',
  processes: const [],
);

void main() {
  late _FakeLease lease;
  late RemoteProcessSource source;
  late List<ProcessSnapshot> delivered;

  setUp(() {
    lease = _FakeLease();
    source = RemoteProcessSource(
      profileId: 'p',
      lease: lease,
      pollingIntervalMs: () => 1000,
    );
    delivered = [];
    source.updates.listen(delivered.add);
  });

  Future<_FakeConnection> goLive() async {
    final connection = _FakeConnection();
    lease.state.value = const RemoteHostConnectionState(
      phase: RemoteConnectionPhase.live,
      hello: _hello,
    );
    lease.connection.value = connection;
    await pumpEventQueue();
    return connection;
  }

  test('subscribes when live and grants credit per applied sample', () async {
    await source.setCadence(const ProcessCadence.live(Duration(seconds: 1)));
    expect(source.state.value.phase, ProcessSourcePhase.connecting);
    final connection = await goLive();
    final telemetry = connection.streams.single;
    expect(telemetry.cadenceMs, 1000);
    expect(
      source.capabilities.value.operatingSystem,
      HostOperatingSystem.linux,
    );

    telemetry.emit(_snapshot(1));
    telemetry.emit(_snapshot(2));
    expect(delivered.map((snapshot) => snapshot.generatedAtUnixMs), [1, 2]);
    expect(telemetry.granted, 2);
    expect(source.state.value.phase, ProcessSourcePhase.live);
  });

  test('cadence changes reach the helper; background and pause map', () async {
    final connection = await goLive();
    final telemetry = connection.streams.single;
    await source.setCadence(
      const ProcessCadence.background(Duration(seconds: 5)),
    );
    expect(telemetry.cadenceChanges.last, 5000);
    await source.setCadence(ProcessCadence.paused);
    expect(telemetry.cadenceChanges.last, isNull);
  });

  test('a lost connection keeps the last sample and goes stale', () async {
    final connection = await goLive();
    connection.streams.single.emit(_snapshot(1));
    lease.connection.value = null;
    lease.state.value = const RemoteHostConnectionState(
      phase: RemoteConnectionPhase.reconnecting,
      failure: RemoteFailureCode.heartbeatLost,
      hello: _hello,
    );
    await pumpEventQueue();
    expect(source.state.value.phase, ProcessSourcePhase.stale);
    expect(source.state.value.failureCode, 'heartbeatLost');
    expect(connection.streams.single.canceled, isTrue);
    expect(delivered, hasLength(1));

    final again = await goLive();
    expect(
      again.streams,
      hasLength(1),
      reason: 'subscribes again with a fresh topology',
    );
    again.streams.single.emit(_snapshot(2));
    expect(source.state.value.phase, ProcessSourcePhase.live);
  });

  test('a cadence set while subscribing is sent afterwards', () async {
    final connection = await goLive();
    expect(connection.streams.single.cadenceMs, isNull);
    await source.setCadence(const ProcessCadence.live(Duration(seconds: 1)));
    expect(connection.streams.single.cadenceChanges, [1000]);
  });

  test('a malformed sample restarts the subscription', () async {
    final connection = await goLive();
    connection.streams.single.fail();
    await pumpEventQueue();
    expect(connection.streams, hasLength(2));
    expect(connection.streams.first.canceled, isTrue);
  });

  test('signals report typed outcomes and are never resent', () async {
    final connection = await goLive();
    const identity = ProcessIdentity(pid: 7, startTimeUnixMs: 1);
    await source.sendSignal(identity, ProcessSignal.terminate);
    connection.outcome = SignalOutcome.denied;
    await expectLater(
      source.sendSignal(identity, ProcessSignal.kill),
      throwsA(
        isA<ProcessSignalException>().having(
          (e) => e.outcome,
          'outcome',
          SignalOutcome.denied,
        ),
      ),
    );
    connection.callFails = true;
    await expectLater(
      source.sendSignal(identity, ProcessSignal.kill),
      throwsA(
        isA<ProcessSignalException>().having(
          (e) => e.outcome,
          'outcome',
          SignalOutcome.unknown,
        ),
      ),
    );
    expect(connection.signals, 3, reason: 'one attempt each');
    lease.connection.value = null;
    await expectLater(
      source.sendSignal(identity, ProcessSignal.kill),
      throwsA(isA<ProcessSignalException>()),
    );
  });

  test('dispose cancels telemetry and releases the lease', () async {
    final connection = await goLive();
    await source.dispose();
    expect(connection.streams.single.canceled, isTrue);
    expect(lease.released, isTrue);
  });
}

final class _FakeLease implements RemoteConnectionLease {
  @override
  final ValueNotifier<RemoteHelperConnection?> connection = ValueNotifier(null);

  @override
  final ValueNotifier<RemoteHostConnectionState> state = ValueNotifier(
    const RemoteHostConnectionState(phase: RemoteConnectionPhase.probing),
  );

  var released = false;

  @override
  String get profileId => 'p';

  @override
  void markSample() {}

  @override
  Future<void> release() async => released = true;
}

final class _FakeTelemetry implements RemoteTelemetryStream {
  _FakeTelemetry(this.cadenceMs);

  final int? cadenceMs;
  final _controller = StreamController<ProcessSnapshot>(sync: true);
  final cadenceChanges = <int?>[];
  var granted = 0;
  var canceled = false;

  void emit(ProcessSnapshot snapshot) => _controller.add(snapshot);

  void fail() => _controller.addError(StateError('malformed'));

  @override
  Stream<ProcessSnapshot> get snapshots => _controller.stream;

  @override
  void grant(int amount) => granted += amount;

  @override
  Future<void> setCadence({
    required int? cadenceMs,
    required int pollingMs,
  }) async => cadenceChanges.add(cadenceMs);

  @override
  void cancel() => canceled = true;
}

final class _FakeConnection implements RemoteHelperConnection {
  final streams = <_FakeTelemetry>[];
  SignalOutcome outcome = SignalOutcome.sent;
  var callFails = false;
  var signals = 0;

  @override
  RemoteHelperHello get hello => _hello;

  @override
  bool get isOpen => true;

  @override
  Future<RemoteFailureCode?> get closed =>
      Completer<RemoteFailureCode?>().future;

  @override
  Future<RemoteTelemetryStream> subscribeTelemetry({
    required int? cadenceMs,
    required int pollingMs,
  }) async {
    final stream = _FakeTelemetry(cadenceMs);
    streams.add(stream);
    return stream;
  }

  @override
  Future<SignalOutcome> sendSignal(
    ProcessIdentity identity,
    ProcessSignal signal,
  ) async {
    signals++;
    if (callFails) throw const RemoteCallFailure('timedOut');
    return outcome;
  }

  @override
  Future<ProcessDetail> fetchDetail(ProcessIdentity identity) =>
      throw UnimplementedError();

  @override
  Future<Object?> call(
    String method,
    Map<String, Object?> arguments, {
    bool bulk = false,
  }) => throw UnimplementedError();

  @override
  Future<RemoteHelperSubscription> subscribe(
    String topic,
    Map<String, Object?> arguments, {
    int initialCredit = 2,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, Uint8List>> fetchIcons(List<String> hashes) async =>
      const {};

  @override
  Future<void> close() async {}
}
