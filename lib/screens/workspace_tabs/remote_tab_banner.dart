import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import 'remote_host_dialogs.dart';
import 'remote_host_labels.dart';

/// The state line of a remote tab (§4.5): connecting, reconnecting or
/// stale with the time of the last sample and the reason, or failed; and
/// the hidepid notice while live. Nothing for the local tab.
class RemoteTabBanner extends StatelessWidget {
  const RemoteTabBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final process = context.read<ProcessService>();
    final descriptor = process.sourceDescriptor;
    if (descriptor is! RemoteProcessSourceDescriptor) {
      return const SizedBox.shrink();
    }
    final hosts = context.read<RemoteHostService>();
    final profileId = descriptor.profileId;
    final connection = hosts.connectionState(profileId);
    return ListenableBuilder(
      listenable: Listenable.merge([
        connection,
        process.sourceState,
        process.hostCapabilities,
        process.loadedSnapshotPath,
      ]),
      builder: (context, _) {
        if (process.loadedSnapshotPath.value != null) {
          return const SizedBox.shrink();
        }
        final banner = _banner(
          context,
          profileId: profileId,
          host: hosts.hosts.value.profile(profileId)?.displayName ?? '',
          state: connection.value,
          source: process.sourceState.value,
          capabilities: process.hostCapabilities.value,
        );
        if (banner == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          key: const ValueKey('remote-tab-banner'),
          padding: const EdgeInsets.fromLTRB(
            MeridianSpace.space3,
            0,
            MeridianSpace.space3,
            MeridianSpace.space3,
          ),
          child: banner,
        );
      },
    );
  }

  Widget? _banner(
    BuildContext context, {
    required String profileId,
    required String host,
    required RemoteHostConnectionState state,
    required ProcessSourceState source,
    required HostCapabilities capabilities,
  }) {
    final l10n = context.l10n;
    final reason = switch (state.failure) {
      null => '',
      final code => l10n.remoteFailure(code),
    };
    final reconnect = MeridianButton(
      key: const ValueKey('remote-tab-reconnect'),
      label: state.needsHelper
          ? l10n.remoteTabInstallHelper
          : l10n.remoteTabReconnect,
      size: MeridianControlSize.small,
      onPressed: () =>
          unawaited(remoteHostWorkflows(context).connect(profileId)),
    );
    final lastSample = source.lastSampleAt;
    switch (state.phase) {
      case RemoteConnectionPhase.live:
        if (capabilities.hidepid && source.phase == ProcessSourcePhase.live) {
          return MeridianBanner(
            tone: MeridianBannerTone.info,
            icon: MeridianIcons.info,
            message: l10n.remoteTabHidepid,
          );
        }
        if (lastSample == null) {
          return MeridianBanner(
            tone: MeridianBannerTone.info,
            icon: MeridianIcons.loaderCircle,
            message: l10n.remoteTabConnecting(host),
          );
        }
        return null;
      case RemoteConnectionPhase.idle ||
          RemoteConnectionPhase.probing ||
          RemoteConnectionPhase.installing ||
          RemoteConnectionPhase.handshaking:
        return MeridianBanner(
          tone: MeridianBannerTone.info,
          icon: MeridianIcons.loaderCircle,
          message: state.phase == RemoteConnectionPhase.installing
              ? l10n.remotePhaseInstalling
              : l10n.remoteTabConnecting(host),
        );
      case RemoteConnectionPhase.reconnecting ||
          RemoteConnectionPhase.disconnected ||
          RemoteConnectionPhase.failed:
        if (lastSample == null) {
          return MeridianBanner(
            tone: state.phase == RemoteConnectionPhase.reconnecting
                ? MeridianBannerTone.warning
                : MeridianBannerTone.error,
            icon: MeridianIcons.cloudOff,
            title: state.phase == RemoteConnectionPhase.reconnecting
                ? l10n.remoteTabReconnectingTitle(host)
                : l10n.remoteTabFailedTitle(host),
            message: reason,
            actions: [reconnect],
          );
        }
        return MeridianBanner(
          tone: MeridianBannerTone.warning,
          icon: MeridianIcons.wifiOff,
          title: state.phase == RemoteConnectionPhase.reconnecting
              ? l10n.remoteTabReconnectingTitle(host)
              : l10n.remoteTabStaleTitle(host),
          message: l10n
              .remoteTabStaleMessage(l10n.remoteClock(lastSample), reason)
              .trim(),
          actions: [reconnect],
        );
    }
  }
}
