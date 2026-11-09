import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../repositories/repositories.dart';
import 'remote_host_service.dart';

/// The user's answer to an install or update confirmation.
enum RemoteInstallChoice { install, installAlways, cancel }

/// What the install dialog shows.
@immutable
class RemoteInstallRequest {
  const RemoteInstallRequest({
    required this.profile,
    required this.target,
    required this.artifact,
    required this.isUpdate,
  });

  final RemoteHostProfile profile;
  final RemoteHelperTarget target;
  final RemoteHelperArtifact artifact;

  /// An older helper build was installed before.
  final bool isUpdate;

  /// Where the helper is installed, relative to the host account's home.
  String get installPath =>
      '~/.local/lib/processlama/remote/${artifact.buildId}/'
      'processlama-remote-helper';

  String get sha256Prefix => artifact.sha256.substring(0, 12);
}

/// Outcomes a workflow tells the window about.
enum RemoteHostReportKind {
  helperInstalled,
  installFailed,
  helperUnavailable,
  connectFailed,
  helperRemoved,
  removalFailed,
}

@immutable
class RemoteHostReport {
  const RemoteHostReport(this.kind, {required this.profileId, this.failure});

  final RemoteHostReportKind kind;
  final String profileId;
  final RemoteFailureCode? failure;
}

/// What a remote host workflow asks and tells its window. The window
/// implements it once and disposes it with the window; a workflow stops
/// asking and reporting once [isActive] is false.
abstract interface class RemoteHostInteractionPort {
  bool get isActive;

  Future<RemoteInstallChoice> confirmInstall(RemoteInstallRequest request);

  Future<bool> confirmHelperRemoval(RemoteHostProfile profile);

  void report(RemoteHostReport report);
}

/// Multi-step remote host flows: connect with install or update, and helper
/// removal. Every decision except the user's answers is made here.
class RemoteHostWorkflows {
  RemoteHostWorkflows({required this.remoteHosts, required this.port});

  final RemoteHostService remoteHosts;
  final RemoteHostInteractionPort port;

  void _report(RemoteHostReport report) {
    if (port.isActive) {
      port.report(report);
    }
  }

  /// Connects [profileId]. A missing or outdated helper is installed after
  /// the user confirms it (or right away when the profile allows it).
  Future<RemoteHostConnectionState> connect(String profileId) async {
    var state = await remoteHosts.connect(profileId);
    final target = state.missingTarget;
    if (state.needsHelper && target != null) {
      state = await _install(profileId, target) ?? state;
    } else if (state.phase == RemoteConnectionPhase.failed) {
      _report(
        RemoteHostReport(
          RemoteHostReportKind.connectFailed,
          profileId: profileId,
          failure: state.failure,
        ),
      );
    }
    return state;
  }

  /// Installs the helper for the missing [target], then connects. Returns
  /// the state after a failed install, or null when the user declined.
  Future<RemoteHostConnectionState?> _install(
    String profileId,
    RemoteHelperTarget target,
  ) async {
    final profile = remoteHosts.hosts.value.profile(profileId);
    if (profile == null || !port.isActive) {
      return null;
    }
    final artifact = await remoteHosts.bundledHelper(target);
    if (artifact == null) {
      _report(
        RemoteHostReport(
          RemoteHostReportKind.helperUnavailable,
          profileId: profileId,
          failure: RemoteFailureCode.unsupportedPlatform,
        ),
      );
      return null;
    }
    final previousBuild = profile.lastKnown?.helperBuildId;
    final choice = await port.confirmInstall(
      RemoteInstallRequest(
        profile: profile,
        target: target,
        artifact: artifact,
        isUpdate: previousBuild != null && previousBuild != artifact.buildId,
      ),
    );
    if (choice == RemoteInstallChoice.cancel) {
      return null;
    }
    if (choice == RemoteInstallChoice.installAlways) {
      await remoteHosts.updateProfile(
        profile.copyWith(autoInstallHelper: true),
      );
    }
    final RemoteInstallResult result;
    try {
      result = await remoteHosts.installHelper(profileId, target);
    } on RemoteHostException catch (error) {
      _report(
        RemoteHostReport(
          RemoteHostReportKind.installFailed,
          profileId: profileId,
          failure: error.code,
        ),
      );
      return remoteHosts.connectionState(profileId).value;
    }
    if (result != RemoteInstallResult.ok) {
      final state = remoteHosts.connectionState(profileId).value;
      _report(
        RemoteHostReport(
          RemoteHostReportKind.installFailed,
          profileId: profileId,
          failure: state.failure,
        ),
      );
      return state;
    }
    _report(
      RemoteHostReport(
        RemoteHostReportKind.helperInstalled,
        profileId: profileId,
      ),
    );
    return remoteHosts.connect(profileId);
  }

  /// Removes the helper from the profile's host after the user confirms.
  Future<RemoteInstallResult?> removeHelper(String profileId) async {
    final profile = remoteHosts.hosts.value.profile(profileId);
    if (profile == null || !port.isActive) {
      return null;
    }
    if (!await port.confirmHelperRemoval(profile)) {
      return null;
    }
    try {
      final result = await remoteHosts.removeHelper(profileId);
      _report(
        RemoteHostReport(
          result == RemoteInstallResult.ok
              ? RemoteHostReportKind.helperRemoved
              : RemoteHostReportKind.removalFailed,
          profileId: profileId,
          failure: result == RemoteInstallResult.ok
              ? null
              : RemoteFailureCode.installRefused,
        ),
      );
      return result;
    } on RemoteHostException catch (error) {
      _report(
        RemoteHostReport(
          RemoteHostReportKind.removalFailed,
          profileId: profileId,
          failure: error.code,
        ),
      );
      return null;
    }
  }
}
