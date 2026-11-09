// Adapted from GitLama's remote workspaces
// (gitlama/lib/repositories/impl/remote/remote_channel_impl.dart).
import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'bootstrap.dart';
import 'frame_codec.dart';
import 'remote_process.dart';
import 'remote_timers.dart';
import 'wire_json.dart';

/// Runs CPU-bound decoding; production uses [Isolate.run].
typedef RemoteOffload = Future<Object?> Function(Object? Function() work);

Future<Object?> isolateOffload(Object? Function() work) => Isolate.run(work);

/// Fixed protocol and timing parameters of one product's helper.
final class RemoteChannelConfig {
  const RemoteChannelConfig({
    required this.magic,
    required this.buildId,
    required this.bootstrapPrefix,
    this.protocolMajor = 1,
    this.protocolMinor = 0,
    this.helloDeadline = const Duration(seconds: 10),
    this.interactiveDeadline = const Duration(seconds: 30),
    this.bulkDeadline = const Duration(seconds: 120),
    this.pingInterval = const Duration(seconds: 15),
    this.livenessTimeout = const Duration(seconds: 45),
    this.shutdownGrace = const Duration(seconds: 5),
    this.exitDrainGrace = const Duration(seconds: 2),
    this.maxConcurrentCalls = 8,
    this.maxFrameBytes = remoteMaxFrameBytes,
    this.helloFrameBytes = remoteHelloFrameBytes,
    this.offloadThresholdBytes = 256 * 1024,
    this.parseLimits = WireParseLimits.standard,
  });

  /// The `magic` a hello must carry.
  final String magic;

  /// The only helper build this client talks to.
  final String buildId;

  /// The status-line prefix of the launch script, for example
  /// `PRODUCT-BOOTSTRAP`.
  final String bootstrapPrefix;
  final int protocolMajor;
  final int protocolMinor;
  final Duration helloDeadline;
  final Duration interactiveDeadline;
  final Duration bulkDeadline;
  final Duration pingInterval;
  final Duration livenessTimeout;
  final Duration shutdownGrace;
  final Duration exitDrainGrace;
  final int maxConcurrentCalls;
  final int maxFrameBytes;
  final int helloFrameBytes;
  final int offloadThresholdBytes;
  final WireParseLimits parseLimits;
}

/// Why a channel could not open or stopped.
enum RemoteChannelFailureKind {
  /// `ssh` exited with 255 before a hello. Nothing more is known.
  sshConnectionFailed,

  /// The launch script ended with a status marker instead of a helper.
  bootstrapMarker,

  /// The output before the hello was neither a marker nor a start line.
  bootstrapFailed,

  /// No hello within the deadline.
  helloTimeout,

  /// The hello named another protocol major version or magic.
  protocolMismatch,

  /// The hello named another helper build.
  buildMismatch,

  /// A malformed frame, envelope or sequence.
  protocolViolation,

  /// A frame larger than the negotiated limit.
  frameTooLarge,

  /// No frame for the liveness timeout.
  heartbeatLost,

  /// The process or its output ended.
  disconnected,

  /// The caller canceled the connection attempt.
  canceled,

  /// The helper sent a `fatal` frame.
  fatal,
}

/// A connection attempt or an open channel failed.
final class RemoteChannelException implements Exception {
  const RemoteChannelException(this.kind, {this.marker, this.fatalCode});

  final RemoteChannelFailureKind kind;

  /// The status marker for [RemoteChannelFailureKind.bootstrapMarker].
  final StatusMarker? marker;

  /// The helper's code for [RemoteChannelFailureKind.fatal].
  final String? fatalCode;

  @override
  String toString() => 'RemoteChannelException(${kind.name})';
}

/// A call failed. [code] is a helper error code or one of [timedOut],
/// [disconnected], [capacity], [canceled] or [invalidRequest].
final class RemoteCallException implements Exception {
  const RemoteCallException(this.code);

  static const timedOut = 'timedOut';
  static const disconnected = 'disconnected';
  static const capacity = 'capacity';
  static const canceled = 'canceled';
  static const invalidRequest = 'invalidRequest';

  final String code;

  @override
  String toString() => 'RemoteCallException($code)';
}

/// A validated hello. [body] is the product's part, validated by the caller.
final class RemoteHello {
  const RemoteHello({
    required this.protocolMinor,
    required this.buildId,
    required this.incarnation,
    required this.frameBytes,
    required this.concurrentCalls,
    required this.body,
  });

  final int protocolMinor;
  final String buildId;
  final String incarnation;

  /// The effective frame limit: the smaller of both peers' values.
  final int frameBytes;

  /// The effective concurrent call limit.
  final int concurrentCalls;
  final Map<String, Object?> body;
}

bool isLowerHex(String text, int length) =>
    text.length == length &&
    text.codeUnits.every(
      (unit) =>
          (unit >= 0x30 && unit <= 0x39) || (unit >= 0x61 && unit <= 0x66),
    );

/// A fresh connection nonce: 16 random bytes as 32 lowercase hex digits.
String newConnectionNonce([Random? random]) {
  final source = random ?? Random.secure();
  final buffer = StringBuffer();
  for (var index = 0; index < 16; index += 1) {
    buffer.write(source.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

const _helloKeys = {
  'kind',
  'magic',
  'protocolMajor',
  'protocolMinor',
  'buildId',
  'incarnation',
  'limits',
  'body',
};

const _envelopeKeys = {
  'protocolMajor',
  'nonce',
  'incarnation',
  'requestId',
  'kind',
  'payload',
};

/// Largest request ID; IDs stay exact JSON integers.
const _maxRequestId = 9007199254740991;

enum _Stage { handshake, open, closing, closed }

final class _PendingCall {
  _PendingCall(this.completer);
  final Completer<Object?> completer;
  Timer? deadline;
}

/// One live subscription. Publications arrive on [data]; the helper sends
/// at most as many as granted and replaces an unsent sample with a newer
/// one, so a slow client lowers the rate instead of growing latency.
final class RemoteSubscription {
  RemoteSubscription._(this._channel, this.id);

  final RemoteChannel _channel;

  /// The request ID of the `subscribe` envelope.
  final int id;
  final _data = StreamController<Object?>(sync: true);
  var _closed = false;

  Stream<Object?> get data => _data.stream;

  /// Grants the helper [amount] more publications.
  void grant(int amount) {
    if (_closed || amount <= 0) {
      return;
    }
    _channel._sendControl('credit', {'target': id, 'amount': amount});
  }

  /// Ends the subscription; later publications are dropped.
  void cancel() {
    if (_closed) {
      return;
    }
    _channel._subscriptions.remove(id);
    _channel._sendControl('unsubscribe', {'target': id});
    _close();
  }

  void _close() {
    if (_closed) {
      return;
    }
    _closed = true;
    unawaited(_data.close());
  }
}

/// A channel to one helper process over its standard input and output.
final class RemoteChannel {
  RemoteChannel._(
    this._process,
    this._config,
    this._timer,
    this._offload,
    this._random,
  );

  /// Performs the handshake on [process] and returns the open channel.
  /// Throws [RemoteChannelException]; the process is terminated on failure.
  static Future<RemoteChannel> connect({
    required RemoteProcess process,
    required RemoteChannelConfig config,
    Future<void>? cancel,
    RemoteTimerFactory timer = systemRemoteTimer,
    RemoteOffload offload = isolateOffload,
    Random? random,
  }) {
    final channel = RemoteChannel._(
      process,
      config,
      timer,
      offload,
      random ?? Random.secure(),
    );
    channel._start(cancel);
    return channel._handshake.future;
  }

  final RemoteProcess _process;
  final RemoteChannelConfig _config;
  final RemoteTimerFactory _timer;
  final RemoteOffload _offload;
  final Random _random;

  final _handshake = Completer<RemoteChannel>();
  final _closed = Completer<RemoteChannelException?>();
  final _goodbye = Completer<void>();
  final _pending = <int, _PendingCall>{};
  final _subscriptions = <int, RemoteSubscription>{};
  late final _probe = BootstrapProbe(prefix: _config.bootstrapPrefix);
  late final _decoder = FrameDecoder(
    maxFrameBytes: _config.helloFrameBytes,
    onDeadline: () => _protocolFailure(),
    timer: _timer,
  );

  var _stage = _Stage.handshake;
  late StreamSubscription<List<int>> _stdout;
  RemoteHello? _hello;
  String? _nonce;
  var _lastRequestId = 0;
  var _lastSequence = 0;
  var _busy = false;
  var _stdoutDone = false;
  int? _exitCode;
  Timer? _helloTimer;
  Timer? _exitDrainTimer;
  Timer? _pingTimer;
  Timer? _livenessTimer;
  Future<void>? _closing;

  RemoteHello get hello => _hello!;

  /// Completes once when the channel becomes unusable: null for an orderly
  /// close the client requested, otherwise the failure.
  Future<RemoteChannelException?> get closed => _closed.future;

  bool get isOpen => _stage == _Stage.open;

  // Lifecycle

  void _start(Future<void>? cancel) {
    _helloTimer = _timer(
      _config.helloDeadline,
      () => _failHandshake(
        const RemoteChannelException(RemoteChannelFailureKind.helloTimeout),
      ),
    );
    _stdout = _process.stdout.listen(
      _onData,
      onError: (Object _) => _onStdoutEnd(),
      onDone: _onStdoutEnd,
      cancelOnError: true,
    );
    _process.exitCode.then<void>(_onExit, onError: (Object _) => _onExit(-1));
    cancel?.then<void>(
      (_) => _failHandshake(
        const RemoteChannelException(RemoteChannelFailureKind.canceled),
      ),
      onError: (Object _) => _failHandshake(
        const RemoteChannelException(RemoteChannelFailureKind.canceled),
      ),
    );
  }

  void _onExit(int code) {
    _exitCode = code;
    if (_stdoutDone || _stage == _Stage.closed) {
      return;
    }
    // A descendant (ProxyCommand) can hold stdout open after ssh exited.
    _exitDrainTimer = _timer(_config.exitDrainGrace, _onStdoutEnd);
  }

  void _onStdoutEnd() {
    if (_stdoutDone) {
      return;
    }
    _stdoutDone = true;
    _exitDrainTimer?.cancel();
    switch (_stage) {
      case _Stage.handshake:
        unawaited(_bootstrapEnded());
      case _Stage.open:
        _fail(
          const RemoteChannelException(RemoteChannelFailureKind.disconnected),
        );
      case _Stage.closing:
        if (!_goodbye.isCompleted) {
          _goodbye.complete();
        }
      case _Stage.closed:
        break;
    }
  }

  Future<void> _bootstrapEnded() async {
    if (_exitCode == null) {
      await completesWithin(_process.exitCode, _config.exitDrainGrace, _timer);
    }
    if (_exitCode == 255) {
      _failHandshake(
        const RemoteChannelException(
          RemoteChannelFailureKind.sshConnectionFailed,
        ),
      );
      return;
    }
    final marker = _probe.marker();
    _failHandshake(
      marker == null
          ? const RemoteChannelException(
              RemoteChannelFailureKind.bootstrapFailed,
            )
          : RemoteChannelException(
              RemoteChannelFailureKind.bootstrapMarker,
              marker: marker,
            ),
    );
  }

  void _failHandshake(RemoteChannelException failure) {
    if (_stage != _Stage.handshake) {
      return;
    }
    _stage = _Stage.closed;
    _release();
    if (!_closed.isCompleted) {
      _closed.complete(failure);
    }
    _handshake.completeError(failure);
  }

  void _fail(RemoteChannelException failure) {
    if (_stage == _Stage.closing) {
      if (!_goodbye.isCompleted) {
        _goodbye.complete();
      }
      return;
    }
    if (_stage != _Stage.open) {
      return;
    }
    _stage = _Stage.closed;
    _release();
    _closed.complete(failure);
  }

  void _protocolFailure([
    RemoteChannelFailureKind kind = RemoteChannelFailureKind.protocolViolation,
  ]) {
    if (_stage == _Stage.handshake) {
      _failHandshake(
        RemoteChannelException(
          kind == RemoteChannelFailureKind.protocolViolation
              ? RemoteChannelFailureKind.bootstrapFailed
              : kind,
        ),
      );
    } else {
      _fail(RemoteChannelException(kind));
    }
  }

  /// Stops timers and input, fails every pending call once and terminates
  /// the process.
  void _release() {
    for (final timer in [
      _helloTimer,
      _exitDrainTimer,
      _pingTimer,
      _livenessTimer,
    ]) {
      timer?.cancel();
    }
    _decoder.close();
    unawaited(_stdout.cancel().catchError((Object _) {}));
    _failPending();
    _closeSubscriptions();
    unawaited(_terminate());
  }

  void _failPending() {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final call in pending) {
      call.deadline?.cancel();
      call.completer.completeError(
        const RemoteCallException(RemoteCallException.disconnected),
      );
    }
  }

  void _closeSubscriptions() {
    final subscriptions = _subscriptions.values.toList();
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      subscription._close();
    }
  }

  Future<void> _terminate() => _process.terminate().catchError((Object _) {});

  /// Graceful shutdown, bounded, followed by process termination.
  Future<void> close() => _closing ??= _closeGracefully();

  Future<void> _closeGracefully() async {
    switch (_stage) {
      case _Stage.handshake:
        _failHandshake(
          const RemoteChannelException(RemoteChannelFailureKind.canceled),
        );
        await _terminate();
        return;
      case _Stage.closed || _Stage.closing:
        await _terminate();
        return;
      case _Stage.open:
        break;
    }
    _stage = _Stage.closing;
    _closed.complete(null);
    _pingTimer?.cancel();
    _livenessTimer?.cancel();
    _failPending();
    _closeSubscriptions();
    _sendControl('shutdown', const {});
    if (!_stdoutDone) {
      await completesWithin(
        Future.any<Object?>([_goodbye.future, _process.exitCode]),
        _config.shutdownGrace,
        _timer,
      );
    }
    _stage = _Stage.closed;
    _release();
    await _terminate();
  }

  // Input

  void _onData(List<int> chunk) {
    if (_stage == _Stage.closed) {
      return;
    }
    var bytes = chunk;
    if (_stage == _Stage.handshake && _probe.state != BootstrapState.frames) {
      final rest = _probe.add(chunk);
      if (_probe.state == BootstrapState.failed) {
        _failHandshake(
          const RemoteChannelException(
            RemoteChannelFailureKind.bootstrapFailed,
          ),
        );
        return;
      }
      if (rest == null) {
        return;
      }
      bytes = rest;
    }
    _decoder.add(bytes);
    _drain();
  }

  void _drain() {
    while (!_busy && _stage != _Stage.closed) {
      final Uint8List? frame;
      try {
        frame = _decoder.next();
      } on WireFormatException catch (error) {
        _protocolFailure(
          error.reason == 'frame length'
              ? RemoteChannelFailureKind.frameTooLarge
              : RemoteChannelFailureKind.protocolViolation,
        );
        return;
      }
      if (frame == null) {
        return;
      }
      if (_stage == _Stage.handshake) {
        _onHello(frame);
        continue;
      }
      _touchLiveness();
      if (frame.length >= _config.offloadThresholdBytes) {
        _runOffloaded(_frameJob(frame, _config.parseLimits));
        return;
      }
      final Object? value;
      try {
        value = parseWireJson(frame, _config.parseLimits);
      } on WireFormatException {
        _protocolFailure();
        return;
      }
      _onEnvelope(value);
    }
  }

  /// Decodes off the UI isolate while input waits, preserving frame order.
  void _runOffloaded(Object? Function() job) {
    _busy = true;
    _stdout.pause();
    _offload(job).then<void>(
      (value) {
        _busy = false;
        if (_stage == _Stage.closed) {
          return;
        }
        _onEnvelope(value);
        if (_stage == _Stage.closed) {
          return;
        }
        _stdout.resume();
        _drain();
      },
      onError: (Object _) {
        _busy = false;
        _protocolFailure();
      },
    );
  }

  void _onHello(Uint8List frame) {
    final RemoteHello hello;
    try {
      hello = _parseHello(frame);
    } on RemoteChannelException catch (failure) {
      _failHandshake(failure);
      return;
    } on WireFormatException {
      _failHandshake(
        const RemoteChannelException(RemoteChannelFailureKind.bootstrapFailed),
      );
      return;
    }
    final nonce = newConnectionNonce(_random);
    _hello = hello;
    _nonce = nonce;
    _decoder.maxFrameBytes = hello.frameBytes;
    _helloTimer?.cancel();
    _write({
      'kind': 'ack',
      'protocolMajor': _config.protocolMajor,
      'buildId': hello.buildId,
      'incarnation': hello.incarnation,
      'nonce': nonce,
    });
    _stage = _Stage.open;
    _schedulePing();
    _touchLiveness();
    _handshake.complete(this);
  }

  RemoteHello _parseHello(Uint8List frame) {
    final value = parseWireJson(frame, _config.parseLimits);
    if (value is! Map<String, Object?> ||
        value.length != _helloKeys.length ||
        !value.keys.every(_helloKeys.contains) ||
        value['kind'] != 'hello') {
      throw const WireFormatException('hello');
    }
    if (value['magic'] != _config.magic ||
        value['protocolMajor'] != _config.protocolMajor) {
      throw const RemoteChannelException(
        RemoteChannelFailureKind.protocolMismatch,
      );
    }
    final buildId = value['buildId'];
    final incarnation = value['incarnation'];
    final minor = value['protocolMinor'];
    final limits = value['limits'];
    final body = value['body'];
    if (buildId is! String ||
        incarnation is! String ||
        !isLowerHex(incarnation, 32) ||
        minor is! int ||
        minor < 0 ||
        limits is! Map<String, Object?> ||
        body is! Map<String, Object?>) {
      throw const WireFormatException('hello');
    }
    if (buildId != _config.buildId) {
      throw const RemoteChannelException(
        RemoteChannelFailureKind.buildMismatch,
      );
    }
    final frameBytes = limits['frameBytes'];
    final concurrentCalls = limits['concurrentCalls'];
    if (limits.length != 2 ||
        frameBytes is! int ||
        concurrentCalls is! int ||
        frameBytes < 1024 ||
        concurrentCalls < 1) {
      throw const WireFormatException('limits');
    }
    return RemoteHello(
      protocolMinor: minor,
      buildId: buildId,
      incarnation: incarnation,
      frameBytes: min(frameBytes, _config.maxFrameBytes),
      concurrentCalls: min(concurrentCalls, _config.maxConcurrentCalls),
      body: body,
    );
  }

  void _onEnvelope(Object? value) {
    if (_stage == _Stage.closed) {
      return;
    }
    if (value is! Map<String, Object?> ||
        value.length != _envelopeKeys.length ||
        !value.keys.every(_envelopeKeys.contains) ||
        value['protocolMajor'] != _config.protocolMajor ||
        value['nonce'] != _nonce ||
        value['incarnation'] != _hello!.incarnation) {
      _protocolFailure();
      return;
    }
    final requestId = value['requestId'];
    final kind = value['kind'];
    final payload = value['payload'];
    if (requestId is! int ||
        requestId < 0 ||
        requestId > _lastRequestId ||
        kind is! String ||
        payload is! Map<String, Object?>) {
      _protocolFailure();
      return;
    }
    switch (kind) {
      case 'result':
        _onResult(requestId, payload);
      case 'publication':
        _onPublication(requestId, payload);
      case 'pong':
        if (requestId == 0 || payload.isNotEmpty) {
          _protocolFailure();
        }
      case 'goodbye':
        if (!_goodbye.isCompleted) {
          _goodbye.complete();
        }
      case 'fatal':
        final code = payload['code'];
        _fail(
          RemoteChannelException(
            RemoteChannelFailureKind.fatal,
            fatalCode: code is String && code.length <= 64 ? code : null,
          ),
        );
      default:
        _protocolFailure();
    }
  }

  void _onResult(int requestId, Map<String, Object?> payload) {
    if (requestId == 0 || payload.length != 1) {
      _protocolFailure();
      return;
    }
    final call = _pending.remove(requestId);
    // A retired, timed out or unknown request: the late result is ignored.
    if (call == null) {
      return;
    }
    call.deadline?.cancel();
    if (payload.containsKey('ok')) {
      call.completer.complete(payload['ok']);
      return;
    }
    final error = payload['error'];
    final code = error is Map<String, Object?> ? error['code'] : null;
    if (error is! Map<String, Object?> ||
        error.length != 1 ||
        code is! String ||
        code.isEmpty ||
        code.length > 64) {
      call.completer.completeError(
        const RemoteCallException(RemoteCallException.invalidRequest),
      );
      _protocolFailure();
      return;
    }
    call.completer.completeError(RemoteCallException(code));
  }

  void _onPublication(int requestId, Map<String, Object?> payload) {
    final subscription = payload['subscription'];
    final sequence = payload['sequence'];
    if (requestId != 0 ||
        payload.length != 3 ||
        subscription is! int ||
        sequence is! int ||
        sequence <= _lastSequence ||
        !payload.containsKey('data')) {
      _protocolFailure();
      return;
    }
    _lastSequence = sequence;
    // A publication for an ended subscription may still be in flight.
    _subscriptions[subscription]?._data.add(payload['data']);
  }

  // Output

  int _nextRequestId() {
    if (_lastRequestId >= _maxRequestId) {
      throw const RemoteCallException(RemoteCallException.disconnected);
    }
    return _lastRequestId += 1;
  }

  /// Sends a call and completes with the decoded `ok` value or throws a
  /// [RemoteCallException]. [bulk] selects the bulk deadline.
  Future<Object?> call(
    String method,
    Map<String, Object?> arguments, {
    bool bulk = false,
  }) {
    if (_stage != _Stage.open) {
      return Future.error(
        const RemoteCallException(RemoteCallException.disconnected),
      );
    }
    if (_pending.length >= _hello!.concurrentCalls) {
      return Future.error(
        const RemoteCallException(RemoteCallException.capacity),
      );
    }
    return _request('call', {'method': method, 'args': arguments}, bulk: bulk);
  }

  /// Starts a subscription to [topic]. The returned future completes with
  /// the helper's acknowledgement value; [onSubscription] receives the
  /// subscription before any publication can arrive.
  Future<Object?> subscribe(
    String topic,
    Map<String, Object?> arguments, {
    required void Function(RemoteSubscription subscription) onSubscription,
    int initialCredit = 2,
  }) {
    if (_stage != _Stage.open) {
      return Future.error(
        const RemoteCallException(RemoteCallException.disconnected),
      );
    }
    int? allocated;
    return _request(
      'subscribe',
      {'topic': topic, 'args': arguments, 'credit': initialCredit},
      onAllocated: (requestId) {
        allocated = requestId;
        final subscription = RemoteSubscription._(this, requestId);
        _subscriptions[requestId] = subscription;
        onSubscription(subscription);
      },
    ).catchError((Object error) {
      // A refused subscription never delivers.
      if (allocated case final id?) {
        _subscriptions.remove(id)?._close();
      }
      throw error;
    });
  }

  Future<Object?> _request(
    String kind,
    Map<String, Object?> payload, {
    bool bulk = false,
    void Function(int requestId)? onAllocated,
  }) {
    final int requestId;
    try {
      requestId = _nextRequestId();
    } on RemoteCallException catch (error) {
      _fail(
        const RemoteChannelException(RemoteChannelFailureKind.disconnected),
      );
      return Future.error(error);
    }
    final Uint8List frame;
    try {
      frame = encodeFrame(
        encodeWireJson(_envelope(requestId, kind, payload)),
        maxFrameBytes: _hello!.frameBytes,
      );
    } on Object {
      // Unencodable or oversized arguments never reach the helper.
      return Future.error(
        const RemoteCallException(RemoteCallException.invalidRequest),
      );
    }
    final pending = _PendingCall(Completer<Object?>());
    _pending[requestId] = pending;
    pending.deadline = _timer(
      bulk ? _config.bulkDeadline : _config.interactiveDeadline,
      () => _expire(requestId),
    );
    onAllocated?.call(requestId);
    _process.write(frame);
    return pending.completer.future;
  }

  void _expire(int requestId) {
    final call = _pending.remove(requestId);
    if (call == null) {
      return;
    }
    call.completer.completeError(
      const RemoteCallException(RemoteCallException.timedOut),
    );
    // Expiry is not proof the helper stopped; a late result is ignored.
    _sendControl('cancel', {'target': requestId});
  }

  Map<String, Object?> _envelope(
    int requestId,
    String kind,
    Map<String, Object?> payload,
  ) => {
    'protocolMajor': _config.protocolMajor,
    'nonce': _nonce,
    'incarnation': _hello!.incarnation,
    'requestId': requestId,
    'kind': kind,
    'payload': payload,
  };

  void _sendControl(String kind, Map<String, Object?> payload) {
    if (_stage != _Stage.open && _stage != _Stage.closing) {
      return;
    }
    final int requestId;
    try {
      requestId = _nextRequestId();
    } on RemoteCallException {
      _fail(
        const RemoteChannelException(RemoteChannelFailureKind.disconnected),
      );
      return;
    }
    _write(_envelope(requestId, kind, payload));
  }

  void _write(Map<String, Object?> message) =>
      _process.write(encodeFrame(encodeWireJson(message)));

  void _schedulePing() {
    _pingTimer = _timer(_config.pingInterval, () {
      if (_stage != _Stage.open) {
        return;
      }
      _sendControl('ping', const {});
      _schedulePing();
    });
  }

  void _touchLiveness() {
    _livenessTimer?.cancel();
    if (_stage != _Stage.open) {
      return;
    }
    _livenessTimer = _timer(
      _config.livenessTimeout,
      () => _fail(
        const RemoteChannelException(RemoteChannelFailureKind.heartbeatLost),
      ),
    );
  }
}

// Built outside instance methods so the closure captures only its bytes.
Object? Function() _frameJob(Uint8List bytes, WireParseLimits limits) =>
    () => parseWireJson(bytes, limits);
