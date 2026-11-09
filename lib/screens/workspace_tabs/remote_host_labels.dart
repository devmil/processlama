import 'package:intl/intl.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../../models/models.dart';
import '../../services/services.dart';

/// The localized text of remote host states, failures and options.
extension RemoteHostLabels on AppLocalizations {
  String remoteFailure(RemoteFailureCode code) => switch (code) {
    RemoteFailureCode.sshMissing => remoteFailureSshMissing,
    RemoteFailureCode.sshTooOld => remoteFailureSshTooOld,
    RemoteFailureCode.sshConnectionFailed => remoteFailureSshConnectionFailed,
    RemoteFailureCode.hostKeyUntrusted => remoteFailureHostKeyUntrusted,
    RemoteFailureCode.authenticationInteractive =>
      remoteFailureAuthenticationInteractive,
    RemoteFailureCode.unsupportedPlatform => remoteFailureUnsupportedPlatform,
    RemoteFailureCode.helperNotInstalled => remoteFailureHelperNotInstalled,
    RemoteFailureCode.helperOutdated => remoteFailureHelperOutdated,
    RemoteFailureCode.helperDamaged => remoteFailureHelperDamaged,
    RemoteFailureCode.helperStartFailed => remoteFailureHelperStartFailed,
    RemoteFailureCode.installFailed => remoteFailureInstallFailed,
    RemoteFailureCode.installNoSpace => remoteFailureInstallNoSpace,
    RemoteFailureCode.installNoexec => remoteFailureInstallNoexec,
    RemoteFailureCode.installRefused => remoteFailureInstallRefused,
    RemoteFailureCode.protocolMismatch => remoteFailureProtocolMismatch,
    RemoteFailureCode.heartbeatLost => remoteFailureHeartbeatLost,
    RemoteFailureCode.frameTooLarge => remoteFailureFrameTooLarge,
    RemoteFailureCode.remoteRestricted => remoteFailureRemoteRestricted,
    RemoteFailureCode.canceled => remoteFailureCanceled,
    RemoteFailureCode.internal => remoteFailureInternal,
  };

  String remotePhase(RemoteConnectionPhase phase) => switch (phase) {
    RemoteConnectionPhase.idle => remotePhaseIdle,
    RemoteConnectionPhase.probing ||
    RemoteConnectionPhase.handshaking => remotePhaseConnecting,
    RemoteConnectionPhase.installing => remotePhaseInstalling,
    RemoteConnectionPhase.live => remotePhaseLive,
    RemoteConnectionPhase.reconnecting => remotePhaseReconnecting,
    RemoteConnectionPhase.disconnected => remotePhaseDisconnected,
    RemoteConnectionPhase.failed => remotePhaseFailed,
  };

  String remoteProbe(RemoteProbeResult result) => switch (result.outcome) {
    RemoteProbeOutcome.sshUnreachable => remoteHostProbeSshUnreachable,
    RemoteProbeOutcome.hostKeyUntrusted => remoteHostProbeHostKeyUntrusted,
    RemoteProbeOutcome.authenticationInteractive =>
      remoteHostProbeAuthenticationInteractive,
    RemoteProbeOutcome.unsupportedPlatform =>
      remoteHostProbeUnsupportedPlatform,
    RemoteProbeOutcome.helperMissing => remoteHostProbeHelperMissing,
    RemoteProbeOutcome.helperOutdated => remoteHostProbeHelperOutdated,
    RemoteProbeOutcome.ready => remoteHostProbeReady(
      remotePlatform(result.facts?.target ?? result.target),
      '${result.facts?.compatibility ?? '–'}',
    ),
  };

  String remoteRefresh(BackgroundRefreshMode mode) => switch (mode) {
    BackgroundRefreshMode.slow => remoteRefreshSlow,
    BackgroundRefreshMode.live => remoteRefreshLive,
    BackgroundRefreshMode.paused => remoteRefreshPaused,
  };

  /// A short duration: seconds, minutes, or hours and minutes.
  String remoteDuration(Duration duration) {
    if (duration.inSeconds < 60) {
      return remoteDurationSeconds('${duration.inSeconds}');
    }
    if (duration.inMinutes < 60) {
      return remoteDurationMinutes('${duration.inMinutes}');
    }
    return remoteDurationHours(
      '${duration.inHours}',
      '${duration.inMinutes.remainder(60)}',
    );
  }

  /// A wall-clock time, `hh:mm:ss` in the current locale.
  String remoteClock(DateTime time) => DateFormat.Hms(localeName).format(time);
}

/// `Linux/x86_64`-style platform names; the target names are not
/// translated.
String remotePlatform(RemoteHelperTarget? target) => switch (target) {
  null => '–',
  RemoteHelperTarget.linuxX8664 => 'Linux/x86_64',
  RemoteHelperTarget.linuxArm64 => 'Linux/arm64',
  RemoteHelperTarget.macosArm64 => 'macOS/arm64',
  RemoteHelperTarget.macosX8664 => 'macOS/x86_64',
};

/// The status dot tone of a connection phase.
MeridianStatusTone remotePhaseTone(RemoteConnectionPhase phase) =>
    switch (phase) {
      RemoteConnectionPhase.live => MeridianStatusTone.success,
      RemoteConnectionPhase.probing ||
      RemoteConnectionPhase.installing ||
      RemoteConnectionPhase.handshaking ||
      RemoteConnectionPhase.reconnecting => MeridianStatusTone.warning,
      RemoteConnectionPhase.failed => MeridianStatusTone.danger,
      RemoteConnectionPhase.idle ||
      RemoteConnectionPhase.disconnected => MeridianStatusTone.neutral,
    };
