import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../src/frame_codec.dart';
import '../src/wire_json.dart';
import 'fake_remote_process.dart';

/// Answers a `call` with a value, or throws [FakeHelperError].
typedef FakeCallHandler =
    FutureOr<Object?> Function(Map<String, Object?> arguments);

/// Thrown by a [FakeCallHandler] to answer with an error code.
final class FakeHelperError implements Exception {
  const FakeHelperError(this.code);
  final String code;
}

/// An in-memory helper speaking the devmil_remote envelope protocol over a
/// [FakeRemoteProcess]: it sends a hello, validates the acknowledgement and
/// answers calls, subscriptions, credit, pings and shutdown.
final class FakeRemoteHelper {
  FakeRemoteHelper({
    required this.process,
    required this.magic,
    required this.buildId,
    required this.bootstrapPrefix,
    this.incarnation = '0123456789abcdef0123456789abcdef',
    this.body = const {},
    this.frameBytes = remoteMaxFrameBytes,
    this.concurrentCalls = 8,
    this.handlers = const {},
    this.preamble = '',
  }) {
    _input = process.stdin.listen(_onInput);
  }

  final FakeRemoteProcess process;
  final String magic;
  final String buildId;
  final String bootstrapPrefix;
  final String incarnation;
  final Map<String, Object?> body;
  final int frameBytes;
  final int concurrentCalls;

  /// Call handlers by method name.
  final Map<String, FakeCallHandler> handlers;

  /// Text a login script printed before the start line.
  final String preamble;

  final _decoder = FrameDecoder(
    maxFrameBytes: remoteMaxFrameBytes,
    onDeadline: () {},
  );
  late final StreamSubscription<Uint8List> _input;
  String? nonce;
  var _sequence = 0;
  final received = <Map<String, Object?>>[];
  final credits = <int, int>{};
  final subscriptions = <int, Map<String, Object?>>{};
  var answerPings = true;

  /// Writes the preamble, the start line and the hello.
  void start() {
    process.emit(utf8.encode('$preamble$bootstrapPrefix 1 start\n'));
    sendRaw({
      'kind': 'hello',
      'magic': magic,
      'protocolMajor': 1,
      'protocolMinor': 0,
      'buildId': buildId,
      'incarnation': incarnation,
      'limits': {'frameBytes': frameBytes, 'concurrentCalls': concurrentCalls},
      'body': body,
    });
  }

  void sendRaw(Object? value) =>
      process.emit(encodeFrame(encodeWireJson(value)));

  void send(int requestId, String kind, Map<String, Object?> payload) {
    sendRaw({
      'protocolMajor': 1,
      'nonce': nonce,
      'incarnation': incarnation,
      'requestId': requestId,
      'kind': kind,
      'payload': payload,
    });
  }

  /// Publishes [data] on [subscription] when it has credit; returns whether
  /// it was sent.
  bool publish(int subscription, Object? data) {
    final credit = credits[subscription] ?? 0;
    if (credit <= 0) {
      return false;
    }
    credits[subscription] = credit - 1;
    _sequence++;
    send(0, 'publication', {
      'subscription': subscription,
      'sequence': _sequence,
      'data': data,
    });
    return true;
  }

  void _onInput(Uint8List bytes) {
    _decoder.add(bytes);
    while (true) {
      final frame = _decoder.next();
      if (frame == null) {
        return;
      }
      final value = parseWireJson(frame, WireParseLimits.standard);
      if (value is! Map<String, Object?>) {
        continue;
      }
      received.add(value);
      if (value['kind'] == 'ack') {
        nonce = value['nonce'] as String?;
        continue;
      }
      unawaited(_onEnvelope(value));
    }
  }

  Future<void> _onEnvelope(Map<String, Object?> envelope) async {
    final requestId = envelope['requestId'] as int;
    final payload = envelope['payload'] as Map<String, Object?>;
    switch (envelope['kind']) {
      case 'call':
        final handler = handlers[payload['method']];
        if (handler == null) {
          send(requestId, 'result', {
            'error': {'code': 'unsupportedCommand'},
          });
          return;
        }
        try {
          final value = await handler(
            (payload['args'] as Map<String, Object?>?) ?? const {},
          );
          send(requestId, 'result', {'ok': value});
        } on FakeHelperError catch (error) {
          send(requestId, 'result', {
            'error': {'code': error.code},
          });
        }
      case 'subscribe':
        subscriptions[requestId] = payload;
        credits[requestId] = payload['credit'] as int? ?? 0;
        send(requestId, 'result', {'ok': <String, Object?>{}});
      case 'credit':
        final target = payload['target'] as int;
        credits[target] = (credits[target] ?? 0) + (payload['amount'] as int);
      case 'unsubscribe':
        final target = payload['target'] as int;
        subscriptions.remove(target);
        credits.remove(target);
      case 'ping':
        if (answerPings) {
          send(requestId, 'pong', const {});
        }
      case 'shutdown':
        send(requestId, 'goodbye', const {});
        await process.exit(0);
    }
  }

  Future<void> dispose() => _input.cancel();
}
