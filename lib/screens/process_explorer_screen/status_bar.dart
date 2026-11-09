part of '../process_explorer_screen.dart';

/// The window's status strip: whether the tree is live, and the totals.
/// A remote tab adds its host, how long it has been connected or when it
/// last updated, and its refresh (§4.5).
class _ExplorerStatusBar extends StatelessWidget {
  const _ExplorerStatusBar({required this.tree, required this.settings});

  final ProcessTreeView tree;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lock = tree.lock;
    final queued = lock.hasQueuedStructuralMutations
        ? l10n.queuedCount('${lock.queuedProcessCount}')
        : '';
    final process = context.read<ProcessService>();
    final descriptor = process.sourceDescriptor;
    if (descriptor is RemoteProcessSourceDescriptor) {
      final hosts = context.read<RemoteHostService>();
      final connection = hosts.connectionState(descriptor.profileId);
      return ListenableBuilder(
        listenable: Listenable.merge([connection, process.sourceState]),
        builder: (context, _) => _bar(
          context,
          queued,
          remote: _remoteFields(
            context,
            host:
                hosts.hosts.value.profile(descriptor.profileId)?.displayName ??
                '',
            state: connection.value,
            source: process.sourceState.value,
          ),
        ),
      );
    }
    return _bar(context, queued);
  }

  /// The refresh dot and the host line of a remote tab.
  (Widget, Widget) _remoteFields(
    BuildContext context, {
    required String host,
    required RemoteHostConnectionState state,
    required ProcessSourceState source,
  }) {
    final l10n = context.l10n;
    final since = state.connectedSince;
    final lastSample = source.lastSampleAt;
    final live =
        state.phase == RemoteConnectionPhase.live &&
        source.phase == ProcessSourcePhase.live;
    final seconds = (settings.pollingIntervalMs / 1000).toStringAsFixed(1);
    final dot = live
        ? MeridianStatusDot(
            tone: MeridianStatusTone.success,
            halo: true,
            label: l10n.remoteStatusRefreshLive('$seconds s'),
          )
        : MeridianStatusDot(
            tone: remotePhaseTone(state.phase),
            label: l10n.remotePhase(state.phase),
          );
    final line = live && since != null
        ? l10n.remoteStatusConnected(
            host,
            l10n.remoteDuration(DateTime.now().difference(since)),
          )
        : lastSample != null
        ? l10n.remoteStatusLastUpdated(host, l10n.remoteClock(lastSample))
        : host;
    return (
      dot,
      Text(
        line,
        key: const ValueKey('remote-status-host'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _bar(BuildContext context, String queued, {(Widget, Widget)? remote}) {
    final l10n = context.l10n;
    final lock = tree.lock;
    return MeridianStatusBar(
      leading: [
        if (lock.isFrozen)
          MeridianStatusDot(label: l10n.statusTreeLocked)
        else if (remote != null)
          remote.$1
        else
          // Static on purpose: a pulsing dot would keep the engine drawing
          // every frame between refreshes.
          MeridianStatusDot(
            tone: MeridianStatusTone.success,
            halo: true,
            label: l10n.pollingStatus('${settings.pollingIntervalMs}'),
          ),
        if (remote != null) remote.$2,
        if (lock.isOrderLockedByInteraction)
          Tooltip(
            key: const ValueKey('order-locked-hint'),
            message: l10n.liveOrderingPausedTooltip,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MeridianIcon(
                  MeridianIcons.pause,
                  size: MeridianIconSize.small,
                ),
                const SizedBox(width: MeridianSpace.space2),
                Flexible(
                  child: Text(
                    l10n.liveOrderingPaused,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
      trailing: [
        Text(
          '${l10n.processCount('${tree.snapshot.processes.length}')}$queued',
        ),
      ],
    );
  }
}
