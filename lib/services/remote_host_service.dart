import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../repositories/repositories.dart';
import 'process_session_factory.dart';

/// What one remote host's connection is doing.
@immutable
class RemoteHostConnectionState {
  const RemoteHostConnectionState({
    this.phase = RemoteConnectionPhase.idle,
    this.failure,
    this.missingTarget,
    this.hello,
    this.connectedSince,
    this.lastSampleAt,
  });

  static const idle = RemoteHostConnectionState();

  final RemoteConnectionPhase phase;

  /// Why the host is disconnected or failed.
  final RemoteFailureCode? failure;

  /// The host's platform when its helper is missing or outdated.
  final RemoteHelperTarget? missingTarget;

  /// The live helper's hello, kept while reconnecting.
  final RemoteHelperHello? hello;
  final DateTime? connectedSince;
  final DateTime? lastSampleAt;

  /// The helper is missing (or of another build) and could be installed.
  bool get needsHelper => failure == RemoteFailureCode.helperNotInstalled;

  RemoteHostConnectionState copyWith({
    RemoteConnectionPhase? phase,
    RemoteFailureCode? Function()? failure,
    RemoteHelperTarget? Function()? missingTarget,
    RemoteHelperHello? Function()? hello,
    DateTime? Function()? connectedSince,
  }) {
    return RemoteHostConnectionState(
      phase: phase ?? this.phase,
      failure: failure == null ? this.failure : failure(),
      missingTarget: missingTarget == null
          ? this.missingTarget
          : missingTarget(),
      hello: hello == null ? this.hello : hello(),
      connectedSince: connectedSince == null
          ? this.connectedSince
          : connectedSince(),
      lastSampleAt: lastSampleAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RemoteHostConnectionState &&
      other.phase == phase &&
      other.failure == failure &&
      other.missingTarget == missingTarget &&
      identical(other.hello, hello) &&
      other.connectedSince == connectedSince &&
      other.lastSampleAt == lastSampleAt;

  @override
  int get hashCode =>
      Object.hash(phase, failure, missingTarget, hello, connectedSince);
}

/// The typed result of "Test connection".
enum RemoteProbeOutcome {
  sshUnreachable,
  hostKeyUntrusted,
  authenticationInteractive,
  unsupportedPlatform,
  helperMissing,
  helperOutdated,
  ready,
}

@immutable
class RemoteProbeResult {
  const RemoteProbeResult(
    this.outcome, {
    this.failure,
    this.target,
    this.facts,
  });

  final RemoteProbeOutcome outcome;
  final RemoteFailureCode? failure;
  final RemoteHelperTarget? target;
  final RemoteHostFacts? facts;
}

/// A user-entered profile before it has an id.
@immutable
class RemoteHostProfileDraft {
  const RemoteHostProfileDraft({
    required this.sshAlias,
    this.displayName,
    this.autoInstallHelper = false,
    this.autoReconnect = true,
    this.openOnStartup,
    this.backgroundRefresh,
  });

  final String sshAlias;

  /// Defaults to the alias.
  final String? displayName;
  final bool autoInstallHelper;
  final bool autoReconnect;
  final bool? openOnStartup;
  final BackgroundRefreshMode? backgroundRefresh;
}

/// A source's claim on a profile's shared connection. The connection closes
/// when its last lease is released.
abstract interface class RemoteConnectionLease {
  String get profileId;

  /// The live connection, or null while connecting, reconnecting or failed.
  ValueListenable<RemoteHelperConnection?> get connection;

  ValueListenable<RemoteHostConnectionState> get state;

  /// Reports that a sample arrived (liveness for the status bar).
  void markSample();

  Future<void> release();
}

/// Owns remote host profiles, connections, helper installs and the
/// reconnect schedule. Owns [RemoteConnectionRepository] and
/// [RemoteHelperArtifactRepository].
abstract interface class RemoteHostService
    implements RemoteProcessSourceProvider {
  ValueListenable<RemoteHostsState> get hosts;

  ValueListenable<RemoteHostConnectionState> connectionState(String profileId);

  Future<void> initialize();

  Future<RemoteHostProfile> addProfile(RemoteHostProfileDraft draft);

  Future<void> updateProfile(RemoteHostProfile profile);

  Future<RemoteHostProfile> duplicateProfile(String profileId);

  /// Disconnects and removes the profile (and its tab).
  Future<void> removeProfile(String profileId);

  /// Runs the bootstrap probe for [alias] without opening a tab.
  Future<RemoteProbeResult> testConnection(String alias);

  /// Claims the profile's connection, connecting when needed.
  RemoteConnectionLease acquire(String profileId);

  /// Connects now (or joins a running attempt) and reports the resulting
  /// state. Installs a missing helper only when the profile allows it.
  Future<RemoteHostConnectionState> connect(String profileId);

  /// Closes the connection; leases stay and see it disconnected.
  Future<void> disconnect(String profileId);

  /// The bundled helper for [target], verified.
  Future<RemoteHelperArtifact?> bundledHelper(RemoteHelperTarget target);

  /// Installs the bundled helper for [target] on the profile's host.
  Future<RemoteInstallResult> installHelper(
    String profileId,
    RemoteHelperTarget target, {
    Future<void>? cancel,
  });

  /// Disconnects and removes every helper and its caches from the host. The
  /// profile is kept.
  Future<RemoteInstallResult> removeHelper(String profileId);

  Future<void> dispose();
}

/// Where release downloads are published.
const processLamaReleaseDownloads =
    'https://github.com/devmil/processlama/releases/download';

/// The shell command that installs the network service package of this
/// app build on a Linux host of [target] (§9.3), or null for other hosts.
/// The user runs it on the host; the app never runs sudo over SSH.
String? networkServiceInstallCommand({
  required String version,
  required int build,
  required RemoteHelperTarget target,
}) {
  final arch = switch (target) {
    RemoteHelperTarget.linuxX8664 => 'x86_64',
    RemoteHelperTarget.linuxArm64 => 'aarch64',
    RemoteHelperTarget.macosArm64 || RemoteHelperTarget.macosX8664 => null,
  };
  if (arch == null) {
    return null;
  }
  final name = 'processlama-network-service-$version-$build-linux-$arch';
  return 'curl -fsSLO $processLamaReleaseDownloads/v$version-$build/'
      '$name.tar.gz && tar -xzf $name.tar.gz && sudo ./$name/install.sh';
}
