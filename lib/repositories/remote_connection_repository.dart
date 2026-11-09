import 'dart:typed_data';

import '../models/models.dart';
import 'process_repository.dart';
import 'remote_helper_artifact_repository.dart';

/// A call to the helper failed with a typed code (`notFound`, `restricted`,
/// `timedOut`, `disconnected`, ...). Carries no received text.
final class RemoteCallFailure implements Exception {
  const RemoteCallFailure(this.code);

  final String code;

  @override
  String toString() => 'RemoteCallFailure($code)';
}

/// One subscription's publications. The client grants credit after it has
/// applied a publication; without credit the helper keeps only its newest.
abstract interface class RemoteHelperSubscription {
  Stream<Object?> get publications;

  void grant(int amount);

  void cancel();
}

/// A running telemetry subscription. Grant credit after a snapshot was
/// applied; without credit the helper keeps only its newest sample.
abstract interface class RemoteTelemetryStream {
  /// Decoded samples. A malformed sample is delivered as an error.
  Stream<ProcessSnapshot> get snapshots;

  void grant(int amount);

  /// Changes the cadence; null [cadenceMs] sends heartbeats only.
  Future<void> setCadence({required int? cadenceMs, required int pollingMs});

  void cancel();
}

/// One handshaken connection to a remote helper.
abstract interface class RemoteHelperConnection {
  RemoteHelperHello get hello;

  bool get isOpen;

  /// Completes once when the connection ends: null for an orderly close the
  /// client requested, otherwise the failure.
  Future<RemoteFailureCode?> get closed;

  /// Sends a call; completes with the decoded result or throws
  /// [RemoteCallFailure].
  Future<Object?> call(
    String method,
    Map<String, Object?> arguments, {
    bool bulk = false,
  });

  /// Starts a subscription; throws [RemoteCallFailure] when refused.
  Future<RemoteHelperSubscription> subscribe(
    String topic,
    Map<String, Object?> arguments, {
    int initialCredit,
  });

  Future<RemoteTelemetryStream> subscribeTelemetry({
    required int? cadenceMs,
    required int pollingMs,
  });

  /// Inspector sections; throws [RemoteCallFailure].
  Future<ProcessDetail> fetchDetail(ProcessIdentity identity);

  /// Sends one signal and returns its typed outcome; throws
  /// [RemoteCallFailure] when the answer did not arrive.
  Future<SignalOutcome> sendSignal(
    ProcessIdentity identity,
    ProcessSignal signal,
  );

  /// Normalized PNG bytes by SHA-256 for up to 64 hashes; hashes the helper
  /// does not know are missing from the result. Bytes are not yet validated.
  Future<Map<String, Uint8List>> fetchIcons(List<String> hashes);

  Future<void> close();
}

/// SSH transport to remote helpers. Owned by the remote host service.
///
/// Every failure is a [RemoteHostException] with a typed code; SSH output is
/// never parsed.
abstract interface class RemoteConnectionRepository {
  /// Starts the helper on [alias] through the launch script and completes the
  /// handshake. A missing helper fails with
  /// [RemoteFailureCode.helperNotInstalled] and the host's target.
  Future<RemoteHelperConnection> connect(String alias, {Future<void>? cancel});

  /// Streams [artifact] to [alias] through the install script.
  Future<RemoteInstallResult> installHelper(
    String alias,
    RemoteHelperArtifact artifact, {
    Future<void>? cancel,
  });

  /// Deletes helper builds unused for 30 days, never [keepBuildId] and never
  /// a running one. Best effort.
  Future<void> pruneHelpers(String alias, {required String keepBuildId});

  /// Removes every installed helper and its caches from [alias].
  Future<RemoteInstallResult> removeHelpers(String alias);
}
