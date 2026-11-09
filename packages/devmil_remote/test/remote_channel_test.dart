import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:devmil_remote/devmil_remote.dart';
import 'package:devmil_remote/testing.dart';
import 'package:test/test.dart';

const _build = '0000000000000000000000000000000000000001';
const _config = RemoteChannelConfig(
  magic: 'test-helper',
  buildId: _build,
  bootstrapPrefix: 'TEST-BOOTSTRAP',
);

Future<Object?> _inline(Object? Function() work) async => work();

final class _Harness {
  _Harness({
    Map<String, FakeCallHandler> handlers = const {},
    String preamble = '',
    int concurrentCalls = 8,
    String buildId = _build,
  }) : process = FakeRemoteProcess() {
    helper = FakeRemoteHelper(
      process: process,
      magic: 'test-helper',
      buildId: buildId,
      bootstrapPrefix: 'TEST-BOOTSTRAP',
      handlers: handlers,
      preamble: preamble,
      concurrentCalls: concurrentCalls,
      body: const {'os': 'linux'},
    );
  }

  final timers = FakeTimers();
  final FakeRemoteProcess process;
  late final FakeRemoteHelper helper;

  Future<RemoteChannel> connect({Future<void>? cancel}) {
    final channel = RemoteChannel.connect(
      process: process,
      config: _config,
      timer: timers.call,
      offload: _inline,
      cancel: cancel,
    );
    return channel;
  }

  Future<RemoteChannel> open() async {
    final channel = connect();
    helper.start();
    return channel;
  }
}

void main() {
  test('opens after login text and answers calls', () async {
    final harness = _Harness(
      preamble: 'Welcome to build-box\n',
      handlers: {'echo': (arguments) => arguments['value']},
    );
    final channel = await harness.open();
    expect(channel.hello.body, {'os': 'linux'});
    expect(await channel.call('echo', {'value': 42}), 42);
    await settle();
    expect(harness.helper.nonce, hasLength(32));
  });

  test('a helper error code fails only that call', () async {
    final harness = _Harness(
      handlers: {'deny': (_) => throw const FakeHelperError('denied')},
    );
    final channel = await harness.open();
    await expectLater(
      channel.call('deny', const {}),
      throwsA(
        isA<RemoteCallException>().having((e) => e.code, 'code', 'denied'),
      ),
    );
    expect(channel.isOpen, isTrue);
  });

  test('a status marker before any frame is reported', () async {
    final harness = _Harness();
    final channel = harness.connect();
    harness.process.emit(
      utf8.encode('motd\nTEST-BOOTSTRAP 1 missing linux/x86_64\n'),
    );
    await harness.process.exit(0);
    await expectLater(
      channel,
      throwsA(
        isA<RemoteChannelException>()
            .having(
              (e) => e.kind,
              'kind',
              RemoteChannelFailureKind.bootstrapMarker,
            )
            .having((e) => e.marker!.words, 'words', [
              'missing',
              'linux/x86_64',
            ]),
      ),
    );
    expect(harness.process.terminated, isTrue);
  });

  test('ssh exit 255 is only a connection failure', () async {
    final harness = _Harness();
    final channel = harness.connect();
    harness.process.emit(utf8.encode('Permission denied (publickey).\n'));
    await harness.process.exit(255);
    await expectLater(
      channel,
      throwsA(
        isA<RemoteChannelException>().having(
          (e) => e.kind,
          'kind',
          RemoteChannelFailureKind.sshConnectionFailed,
        ),
      ),
    );
  });

  test('no hello within the deadline fails the handshake', () async {
    final harness = _Harness();
    final channel = harness.connect();
    harness.timers.elapse(const Duration(seconds: 10));
    await expectLater(
      channel,
      throwsA(
        isA<RemoteChannelException>().having(
          (e) => e.kind,
          'kind',
          RemoteChannelFailureKind.helloTimeout,
        ),
      ),
    );
  });

  test('another build is rejected before any call', () async {
    final harness = _Harness(
      buildId: '0000000000000000000000000000000000000002',
    );
    await expectLater(
      harness.open(),
      throwsA(
        isA<RemoteChannelException>().having(
          (e) => e.kind,
          'kind',
          RemoteChannelFailureKind.buildMismatch,
        ),
      ),
    );
    expect(harness.helper.nonce, isNull);
  });

  test('cancel during the handshake terminates the process', () async {
    final harness = _Harness();
    final cancel = Completer<void>();
    final channel = harness.connect(cancel: cancel.future);
    cancel.complete();
    await expectLater(
      channel,
      throwsA(
        isA<RemoteChannelException>().having(
          (e) => e.kind,
          'kind',
          RemoteChannelFailureKind.canceled,
        ),
      ),
    );
    expect(harness.process.terminated, isTrue);
  });

  test('an unanswered call times out and is canceled on the wire', () async {
    final never = Completer<Object?>();
    final harness = _Harness(handlers: {'slow': (_) => never.future});
    final channel = await harness.open();
    final call = channel.call('slow', const {});
    await settle();
    harness.timers.elapse(const Duration(seconds: 30));
    await expectLater(
      call,
      throwsA(
        isA<RemoteCallException>().having((e) => e.code, 'code', 'timedOut'),
      ),
    );
    await settle();
    final cancel = harness.helper.received.singleWhere(
      (message) => message['kind'] == 'cancel',
    );
    expect((cancel['payload'] as Map)['target'], 1);
  });

  test('bulk calls get the longer deadline', () async {
    final never = Completer<Object?>();
    final harness = _Harness(handlers: {'slow': (_) => never.future});
    final channel = await harness.open();
    var done = false;
    unawaited(
      channel.call('slow', const {}, bulk: true).catchError((Object _) {
        done = true;
        return null;
      }),
    );
    // Step in ping intervals so pongs keep the connection alive.
    for (var step = 0; step < 7; step++) {
      harness.timers.elapse(const Duration(seconds: 15));
      await settle();
    }
    expect(done, isFalse);
    harness.timers.elapse(const Duration(seconds: 15));
    await settle();
    expect(done, isTrue);
    expect(channel.isOpen, isTrue);
  });

  test('more concurrent calls than the limit fail with capacity', () async {
    final never = Completer<Object?>();
    final harness = _Harness(
      concurrentCalls: 2,
      handlers: {'slow': (_) => never.future},
    );
    final channel = await harness.open();
    unawaited(channel.call('slow', const {}).catchError((Object _) => null));
    unawaited(channel.call('slow', const {}).catchError((Object _) => null));
    await expectLater(
      channel.call('slow', const {}),
      throwsA(
        isA<RemoteCallException>().having((e) => e.code, 'code', 'capacity'),
      ),
    );
  });

  test('pings every 15 seconds and fails after 45 silent seconds', () async {
    final harness = _Harness();
    final channel = await harness.open();
    harness.helper.answerPings = false;
    harness.timers.elapse(const Duration(seconds: 15));
    await settle();
    expect(harness.helper.received.last['kind'], 'ping');
    harness.timers.elapse(const Duration(seconds: 30));
    final failure = await channel.closed;
    expect(failure!.kind, RemoteChannelFailureKind.heartbeatLost);
    expect(harness.process.terminated, isTrue);
  });

  test('answered pings keep the connection alive', () async {
    final harness = _Harness();
    final channel = await harness.open();
    for (var index = 0; index < 8; index++) {
      harness.timers.elapse(const Duration(seconds: 15));
      await settle();
    }
    expect(channel.isOpen, isTrue);
  });

  test('subscriptions deliver only granted publications', () async {
    final harness = _Harness();
    final channel = await harness.open();
    late RemoteSubscription subscription;
    final data = <Object?>[];
    await channel.subscribe(
      'telemetry',
      const {'cadenceMs': 1000},
      onSubscription: (created) {
        subscription = created;
        created.data.listen(data.add);
      },
    );
    expect(harness.helper.publish(subscription.id, 1), isTrue);
    expect(harness.helper.publish(subscription.id, 2), isTrue);
    expect(harness.helper.publish(subscription.id, 3), isFalse);
    await settle();
    subscription.grant(1);
    await settle();
    expect(harness.helper.publish(subscription.id, 3), isTrue);
    await settle();
    expect(data, [1, 2, 3]);

    subscription.cancel();
    await settle();
    expect(harness.helper.subscriptions, isEmpty);
  });

  test('a frame over the limit fails the channel', () async {
    final harness = _Harness();
    final channel = await harness.open();
    final header = Uint8List(4)
      ..buffer.asByteData().setUint32(0, remoteMaxFrameBytes + 1);
    harness.process.emit(header);
    final failure = await channel.closed;
    expect(failure!.kind, RemoteChannelFailureKind.frameTooLarge);
  });

  test('an envelope with a wrong nonce is a protocol violation', () async {
    final harness = _Harness();
    final channel = await harness.open();
    await settle();
    harness.helper.nonce = 'ffffffffffffffffffffffffffffffff';
    harness.helper.send(0, 'pong', const {});
    final failure = await channel.closed;
    expect(failure!.kind, RemoteChannelFailureKind.protocolViolation);
  });

  test('a fatal frame reports its code', () async {
    final harness = _Harness();
    final channel = await harness.open();
    await settle();
    harness.helper.send(0, 'fatal', const {'code': 'buildMismatch'});
    final failure = await channel.closed;
    expect(failure!.kind, RemoteChannelFailureKind.fatal);
    expect(failure.fatalCode, 'buildMismatch');
  });

  test('close sends shutdown and completes with null', () async {
    final harness = _Harness();
    final channel = await harness.open();
    await settle();
    await channel.close();
    expect(await channel.closed, isNull);
    expect(
      harness.helper.received.map((message) => message['kind']),
      contains('shutdown'),
    );
    await expectLater(
      channel.call('echo', const {}),
      throwsA(isA<RemoteCallException>()),
    );
  });

  test('the end of output fails pending calls once', () async {
    final never = Completer<Object?>();
    final harness = _Harness(handlers: {'slow': (_) => never.future});
    final channel = await harness.open();
    final call = channel.call('slow', const {});
    await settle();
    await harness.process.exit(0);
    await expectLater(
      call,
      throwsA(
        isA<RemoteCallException>().having(
          (e) => e.code,
          'code',
          'disconnected',
        ),
      ),
    );
    expect((await channel.closed)!.kind, RemoteChannelFailureKind.disconnected);
  });
}
