import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:devmil_remote/devmil_remote.dart';
import 'package:flutter/foundation.dart';

import '../../../models/models.dart';
import '../../remote_connection_repository.dart';
import '../../remote_helper_artifact_repository.dart';
import 'native_remote_process.dart';
import 'remote_scripts.dart';
import 'wire/contract.g.dart';
import 'wire/messages.dart';
import 'wire/telemetry_codec.dart';
import '../../process_repository.dart';

/// Reads `ssh -V` output, or null when the probe failed.
typedef SshVersionReader = Future<String?> Function(String executable);

/// The isolated SSH configuration test harnesses pass through
/// `PROCESSLAMA_SSH_CONFIG`. Release builds never read it.
String? sshConfigOverride(
  Map<String, String> environment, {
  bool releaseBuild = kReleaseMode,
}) {
  if (releaseBuild) {
    return null;
  }
  final value = environment['PROCESSLAMA_SSH_CONFIG'];
  if (value == null || value.isEmpty || !value.startsWith('/')) {
    return null;
  }
  return value;
}

/// The channel parameters of ProcessLama's helper, from the wire contract.
const remoteChannelConfig = RemoteChannelConfig(
  magic: remoteHelperMagic,
  buildId: remoteHelperBuildId,
  bootstrapPrefix: remoteBootstrapPrefix,
  protocolMajor: remoteProtocolMajor,
  protocolMinor: remoteProtocolMinor,
  helloDeadline: RemoteWireDeadlines.hello,
  interactiveDeadline: RemoteWireDeadlines.interactive,
  bulkDeadline: RemoteWireDeadlines.bulk,
  pingInterval: RemoteWireDeadlines.ping,
  livenessTimeout: RemoteWireDeadlines.liveness,
  maxConcurrentCalls: RemoteWireLimits.concurrentCalls,
  maxFrameBytes: RemoteWireLimits.frameBytes,
  helloFrameBytes: RemoteWireLimits.helloBytes,
);

/// Most output bytes kept from an install, prune or uninstall script; login
/// scripts may print before the status line.
const _scriptOutputBytes = 4096;

/// [RemoteConnectionRepository] over the system OpenSSH client.
///
/// On macOS and Linux the Rust core owns the SSH child processes, so the Dart
/// VM never reaps native children while a remote tab is open; Windows uses
/// `dart:io` with a process-tree kill.
class SshRemoteConnectionRepository implements RemoteConnectionRepository {
  SshRemoteConnectionRepository({
    ProcessStarter? startProcess,
    SshVersionReader? readVersion,
    Map<String, String>? environment,
    bool? windows,
    String? currentDirectory,
    bool Function(String path)? isFile,
    String? configFile,
    this._timer = systemRemoteTimer,
    this._offload = isolateOffload,
  }) : _windows = windows ?? Platform.isWindows,
       _environment = environment ?? Platform.environment,
       _currentDirectory = currentDirectory ?? Directory.current.path,
       _isFile = isFile ?? ((path) => File(path).existsSync()) {
    _startProcess =
        startProcess ??
        (_windows ? startIoRemoteProcess : startNativeRemoteProcess);
    _readVersion =
        readVersion ?? (_windows ? readSshVersion : readNativeSshVersion);
    _configFile = configFile ?? sshConfigOverride(_environment);
  }

  final bool _windows;
  final Map<String, String> _environment;
  final String _currentDirectory;
  final bool Function(String path) _isFile;
  final RemoteTimerFactory _timer;
  final RemoteOffload _offload;
  late final ProcessStarter _startProcess;
  late final SshVersionReader _readVersion;
  late final String? _configFile;
  Future<String>? _ssh;

  /// The verified OpenSSH executable; the probe runs once per launch.
  Future<String> _sshExecutable() =>
      _ssh ??= _resolveSsh().catchError((Object error) {
        _ssh = null;
        throw error;
      });

  Future<String> _resolveSsh() async {
    final executable = resolveSshExecutable(
      windows: _windows,
      environment: _environment,
      currentDirectory: _currentDirectory,
      isFile: _isFile,
    );
    if (executable == null) {
      throw const RemoteHostException(RemoteFailureCode.sshMissing);
    }
    final version = await _readVersion(executable);
    if (version == null) {
      throw const RemoteHostException(RemoteFailureCode.sshMissing);
    }
    if (!isSupportedOpenSsh(version)) {
      throw const RemoteHostException(RemoteFailureCode.sshTooOld);
    }
    return executable;
  }

  Future<RemoteProcess> _start(String alias, String script) async {
    final executable = await _sshExecutable();
    final List<String> arguments;
    try {
      arguments = sshArguments(
        alias: alias,
        // The account's login shell may be zsh or fish; scripts are sh.
        remoteCommand: posixShellCommand(script),
        configFile: _configFile,
      );
    } on InvalidSshAlias {
      throw const RemoteHostException(RemoteFailureCode.internal);
    }
    try {
      return await _startProcess(executable, arguments);
    } on ProcessException {
      throw const RemoteHostException(RemoteFailureCode.sshMissing);
    }
  }

  @override
  Future<RemoteHelperConnection> connect(
    String alias, {
    Future<void>? cancel,
  }) async {
    final process = await _start(alias, bootstrapScript(remoteHelperBuildId));
    final RemoteChannel channel;
    try {
      channel = await RemoteChannel.connect(
        process: process,
        config: remoteChannelConfig,
        cancel: cancel,
        timer: _timer,
        offload: _offload,
      );
    } on RemoteChannelException catch (failure) {
      throw remoteHostExceptionFor(failure);
    }
    final RemoteHelperHello hello;
    try {
      hello = parseHelloBody(
        channel.hello.body,
        buildId: channel.hello.buildId,
      );
    } on InvalidRemoteMessage {
      await channel.close();
      throw const RemoteHostException(RemoteFailureCode.protocolMismatch);
    }
    return _ChannelConnection(channel, hello);
  }

  @override
  Future<RemoteInstallResult> installHelper(
    String alias,
    RemoteHelperArtifact artifact, {
    Future<void>? cancel,
  }) async {
    final bytes = await artifact.read();
    final script = installScript(
      buildId: artifact.buildId,
      sha256: artifact.sha256,
      size: artifact.size,
    );
    return _runScript(
      alias,
      script,
      stdin: bytes,
      deadline: RemoteWireDeadlines.install,
      cancel: cancel,
    );
  }

  @override
  Future<void> pruneHelpers(String alias, {required String keepBuildId}) async {
    await _runScript(
      alias,
      pruneScript(keepBuildId: keepBuildId),
      deadline: RemoteWireDeadlines.probe,
    );
  }

  @override
  Future<RemoteInstallResult> removeHelpers(String alias) => _runScript(
    alias,
    uninstallScript(buildId: remoteHelperBuildId),
    deadline: RemoteWireDeadlines.probe,
  );

  /// Runs a fixed script and reads its `PROCESSLAMA-INSTALL 1 <result>` line.
  Future<RemoteInstallResult> _runScript(
    String alias,
    String script, {
    List<int>? stdin,
    required Duration deadline,
    Future<void>? cancel,
  }) async {
    final process = await _start(alias, script);
    final output = ListQueue<int>();
    final done = Completer<void>();
    final subscription = process.stdout.listen(
      (chunk) {
        output.addAll(chunk);
        while (output.length > _scriptOutputBytes) {
          output.removeFirst();
        }
      },
      onDone: () => done.isCompleted ? null : done.complete(),
      onError: (Object _) => done.isCompleted ? null : done.complete(),
      cancelOnError: true,
    );
    var canceled = false;
    unawaited(
      cancel?.then((_) {
        canceled = true;
        return process.terminate();
      }),
    );
    if (stdin != null) {
      process.write(stdin);
    }
    await process.closeStdin();
    final finished = await completesWithin(
      Future.wait<Object?>([process.exitCode, done.future]),
      deadline,
      _timer,
    );
    if (!finished) {
      await process.terminate();
      await subscription.cancel();
      throw const RemoteHostException(RemoteFailureCode.installFailed);
    }
    final exitCode = await process.exitCode;
    await subscription.cancel();
    if (canceled) {
      throw const RemoteHostException(RemoteFailureCode.canceled);
    }
    final marker = StatusMarker.parse(
      lastNonEmptyLine(output.toList()),
      remoteInstallPrefix,
    );
    if (marker == null || marker.version != 1 || marker.words.length != 1) {
      throw RemoteHostException(
        exitCode == 255
            ? RemoteFailureCode.sshConnectionFailed
            : RemoteFailureCode.installFailed,
      );
    }
    return remoteInstallResultFromWire(marker.words.single) ??
        (throw const RemoteHostException(RemoteFailureCode.installFailed));
  }
}

/// The typed failure for a channel that could not open or stopped.
RemoteHostException remoteHostExceptionFor(RemoteChannelException failure) {
  switch (failure.kind) {
    case RemoteChannelFailureKind.sshConnectionFailed:
    case RemoteChannelFailureKind.disconnected:
      return const RemoteHostException(RemoteFailureCode.sshConnectionFailed);
    case RemoteChannelFailureKind.bootstrapMarker:
      final words = failure.marker?.words ?? const <String>[];
      if (failure.marker?.version == 1 &&
          words.length == 2 &&
          words.first == 'missing') {
        final target = helperTargetFromMarker(words[1]);
        if (target != null) {
          return RemoteHostException(
            RemoteFailureCode.helperNotInstalled,
            hostTarget: target,
          );
        }
      }
      if (words.length == 1 && words.single == 'unsupported') {
        return const RemoteHostException(RemoteFailureCode.unsupportedPlatform);
      }
      return const RemoteHostException(RemoteFailureCode.helperStartFailed);
    case RemoteChannelFailureKind.bootstrapFailed:
    case RemoteChannelFailureKind.helloTimeout:
      return const RemoteHostException(RemoteFailureCode.helperStartFailed);
    case RemoteChannelFailureKind.buildMismatch:
      return const RemoteHostException(RemoteFailureCode.helperOutdated);
    case RemoteChannelFailureKind.protocolMismatch:
    case RemoteChannelFailureKind.protocolViolation:
    case RemoteChannelFailureKind.fatal:
      return const RemoteHostException(RemoteFailureCode.protocolMismatch);
    case RemoteChannelFailureKind.frameTooLarge:
      return const RemoteHostException(RemoteFailureCode.frameTooLarge);
    case RemoteChannelFailureKind.heartbeatLost:
      return const RemoteHostException(RemoteFailureCode.heartbeatLost);
    case RemoteChannelFailureKind.canceled:
      return const RemoteHostException(RemoteFailureCode.canceled);
  }
}

final class _ChannelConnection implements RemoteHelperConnection {
  _ChannelConnection(this._channel, this.hello);

  final RemoteChannel _channel;

  @override
  final RemoteHelperHello hello;

  @override
  bool get isOpen => _channel.isOpen;

  @override
  late final Future<RemoteFailureCode?> closed = _channel.closed.then(
    (failure) => failure == null ? null : remoteHostExceptionFor(failure).code,
  );

  @override
  Future<Object?> call(
    String method,
    Map<String, Object?> arguments, {
    bool bulk = false,
  }) async {
    try {
      return await _channel.call(method, arguments, bulk: bulk);
    } on RemoteCallException catch (error) {
      throw RemoteCallFailure(error.code);
    }
  }

  @override
  Future<RemoteHelperSubscription> subscribe(
    String topic,
    Map<String, Object?> arguments, {
    int initialCredit = RemoteWireLimits.telemetryCredit,
  }) async {
    late RemoteSubscription created;
    try {
      await _channel.subscribe(
        topic,
        arguments,
        initialCredit: initialCredit,
        onSubscription: (subscription) => created = subscription,
      );
    } on RemoteCallException catch (error) {
      throw RemoteCallFailure(error.code);
    }
    return _Subscription(created);
  }

  @override
  Future<RemoteTelemetryStream> subscribeTelemetry({
    required int? cadenceMs,
    required int pollingMs,
  }) async {
    final subscription = await subscribe(
      RemoteWireTopics.telemetry,
      telemetryArguments(cadenceMs: cadenceMs, pollingMs: pollingMs),
    );
    return _TelemetryStream(this, subscription);
  }

  @override
  Future<ProcessDetail> fetchDetail(ProcessIdentity identity) async {
    final value = await call(RemoteWireMethods.processDetail, {
      'pid': identity.pid,
      'start': identity.startTimeUnixMs,
    });
    try {
      return decodeProcessDetail(value);
    } on InvalidRemoteMessage {
      throw const RemoteCallFailure(RemoteCallException.invalidRequest);
    }
  }

  @override
  Future<SignalOutcome> sendSignal(
    ProcessIdentity identity,
    ProcessSignal signal,
  ) async {
    final value = await call(
      RemoteWireMethods.processSignal,
      signalArguments(identity, signal),
    );
    try {
      return decodeSignalOutcome(value);
    } on InvalidRemoteMessage {
      throw const RemoteCallFailure(RemoteCallException.invalidRequest);
    }
  }

  @override
  Future<Map<String, Uint8List>> fetchIcons(List<String> hashes) async {
    final value = await call(RemoteWireMethods.iconsFetch, {
      'hashes': hashes,
    }, bulk: true);
    try {
      return decodeIcons(value, hashes.toSet());
    } on InvalidRemoteMessage {
      throw const RemoteCallFailure(RemoteCallException.invalidRequest);
    }
  }

  @override
  Future<void> close() => _channel.close();
}

final class _TelemetryStream implements RemoteTelemetryStream {
  _TelemetryStream(this._connection, this._subscription) {
    final decoder = RemoteTelemetryDecoder();
    snapshots = _subscription.publications.transform(
      StreamTransformer.fromHandlers(
        handleData: (data, sink) {
          try {
            sink.add(decoder.decode(data));
          } on InvalidRemoteMessage catch (error) {
            sink.addError(error);
          }
        },
      ),
    );
  }

  final _ChannelConnection _connection;
  final RemoteHelperSubscription _subscription;

  @override
  late final Stream<ProcessSnapshot> snapshots;

  @override
  void grant(int amount) => _subscription.grant(amount);

  @override
  Future<void> setCadence({required int? cadenceMs, required int pollingMs}) =>
      _connection.call(
        RemoteWireMethods.telemetryCadence,
        telemetryArguments(cadenceMs: cadenceMs, pollingMs: pollingMs),
      );

  @override
  void cancel() => _subscription.cancel();
}

final class _Subscription implements RemoteHelperSubscription {
  _Subscription(this._subscription);

  final RemoteSubscription _subscription;

  @override
  Stream<Object?> get publications => _subscription.data;

  @override
  void grant(int amount) => _subscription.grant(amount);

  @override
  void cancel() => _subscription.cancel();
}
