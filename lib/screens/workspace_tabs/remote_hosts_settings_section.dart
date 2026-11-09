import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import 'remote_host_dialogs.dart';
import 'remote_host_labels.dart';

/// The icon cache sizes offered, in MiB.
const _iconCacheChoicesMiB = [16, 32, 64, 128, 256];

/// The Remote hosts page of the preferences (§4.3): the profiles with their
/// actions, the default background refresh and the remote icon cache.
class RemoteHostsSettingsSection extends StatefulWidget {
  const RemoteHostsSettingsSection({super.key});

  @override
  State<RemoteHostsSettingsSection> createState() =>
      _RemoteHostsSettingsSectionState();
}

class _RemoteHostsSettingsSectionState
    extends State<RemoteHostsSettingsSection> {
  late final RemoteHostService _hosts = context.read<RemoteHostService>();
  late final RemoteHostsSettings _settings = context
      .read<RemoteHostsSettings>();
  late final ProcessIconService _icons = context.read<ProcessIconService>();

  Future<void> _remove(RemoteHostProfile profile) async {
    final l10n = context.l10n;
    final confirmed = await showMeridianConfirm(
      context,
      title: l10n.remoteHostRemoveTitle(profile.displayName),
      description: l10n.remoteHostRemoveBody,
      confirmLabel: l10n.remoteHostRemove,
      cancelLabel: l10n.remoteHostCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await context.read<WorkspaceTabsService>().closeTab(
      RemoteWorkspaceTab(profile.id),
    );
    await _hosts.removeProfile(profile.id);
  }

  void _openActions(Rect anchor, RemoteHostProfile profile) {
    final l10n = context.l10n;
    final phase = _hosts.connectionState(profile.id).value.phase;
    final connected =
        phase == RemoteConnectionPhase.live ||
        phase == RemoteConnectionPhase.reconnecting;
    unawaited(
      showMeridianMenu(
        context,
        anchor: anchor,
        entries: [
          MeridianMenuItem(
            label: l10n.remoteHostEdit,
            icon: MeridianIcons.pencil,
            onSelected: () =>
                unawaited(showRemoteHostEditor(context, profile: profile)),
          ),
          if (connected)
            MeridianMenuItem(
              label: l10n.remoteHostDisconnect,
              icon: MeridianIcons.cloudOff,
              onSelected: () => unawaited(_hosts.disconnect(profile.id)),
            )
          else
            MeridianMenuItem(
              label: l10n.remoteHostConnect,
              icon: MeridianIcons.cloud,
              onSelected: () =>
                  unawaited(remoteHostWorkflows(context).connect(profile.id)),
            ),
          MeridianMenuItem(
            label: l10n.remoteHostDuplicate,
            icon: MeridianIcons.copy,
            onSelected: () => unawaited(_hosts.duplicateProfile(profile.id)),
          ),
          MeridianMenuItem(
            label: l10n.remoteHostRemove,
            icon: MeridianIcons.trash2,
            danger: true,
            onSelected: () => unawaited(_remove(profile)),
          ),
          const MeridianMenuDivider(),
          MeridianMenuItem(
            label: l10n.remoteHelperRemoveMenu,
            icon: MeridianIcons.trash,
            danger: true,
            onSelected: () => unawaited(
              remoteHostWorkflows(context).removeHelper(profile.id),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearIcons() async {
    await _icons.clearCache();
    if (mounted) {
      setState(() {});
      showMeridianToast(
        context,
        message: context.l10n.remoteIconCacheCleared,
        tone: MeridianToastTone.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ValueListenableBuilder<RemoteHostsState>(
      valueListenable: _hosts.hosts,
      builder: (context, state, _) {
        final limitMiB = (state.iconCacheBytes / (1024 * 1024)).round();
        final choices = {..._iconCacheChoicesMiB, limitMiB}.toList()..sort();
        return MeridianSettingsGroup(
          key: const ValueKey('remote-hosts-settings'),
          children: [
            MeridianSettingsRow(
              label: l10n.remoteHostsProfiles,
              children: [
                if (state.profiles.isEmpty)
                  Text(
                    l10n.remoteHostsEmpty,
                    style: context.meridian.text.caption.copyWith(
                      color: context.meridian.colors.inkMuted,
                    ),
                  ),
                for (final profile in state.profiles)
                  _ProfileRow(
                    key: ValueKey('remote-host-row-${profile.id}'),
                    profile: profile,
                    state: _hosts.connectionState(profile.id),
                    onActions: (anchor) => _openActions(anchor, profile),
                  ),
                MeridianButton(
                  key: const ValueKey('remote-host-add'),
                  label: l10n.remoteHostAdd,
                  icon: MeridianIcons.circlePlus,
                  size: MeridianControlSize.small,
                  onPressed: () => unawaited(showRemoteHostEditor(context)),
                ),
              ],
            ),
            MeridianSettingsRow(
              label: l10n.remoteHostsDefaultRefresh,
              children: [
                MeridianSegmented<BackgroundRefreshMode>(
                  label: l10n.remoteHostsDefaultRefresh,
                  value: state.defaultBackgroundRefresh,
                  onChanged: (mode) =>
                      unawaited(_settings.updateDefaultBackgroundRefresh(mode)),
                  segments: [
                    for (final mode in BackgroundRefreshMode.values)
                      MeridianSegment(
                        value: mode,
                        label: l10n.remoteRefresh(mode),
                      ),
                  ],
                ),
              ],
            ),
            MeridianSettingsRow(
              label: l10n.remoteIconCache,
              help: l10n.remoteIconCacheUsage(
                formatRemoteBytes(_icons.cacheBytes),
                formatRemoteBytes(state.iconCacheBytes),
              ),
              children: [
                // Wraps the button below the select when large text or a
                // narrow page leaves no room beside it.
                Wrap(
                  spacing: MeridianSpace.space3,
                  runSpacing: MeridianSpace.space3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    MeridianSelect<int>(
                      label: l10n.remoteIconCache,
                      value: limitMiB,
                      values: choices,
                      valueLabel: (mib) => formatRemoteBytes(mib * 1024 * 1024),
                      onChanged: (mib) => unawaited(
                        _settings.updateRemoteIconCacheBytes(mib * 1024 * 1024),
                      ),
                    ),
                    MeridianButton(
                      key: const ValueKey('remote-icon-cache-clear'),
                      label: l10n.remoteIconCacheClear,
                      size: MeridianControlSize.small,
                      onPressed: () => unawaited(_clearIcons()),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    super.key,
    required this.profile,
    required this.state,
    required this.onActions,
  });

  final RemoteHostProfile profile;
  final ValueListenable<RemoteHostConnectionState> state;
  final ValueChanged<Rect> onActions;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final meridian = context.meridian;
    final facts = profile.lastKnown;
    final details = [
      profile.sshAlias,
      facts == null
          ? l10n.remoteHostNeverConnected
          : l10n.remoteHostLastSeen(
              remotePlatform(facts.target),
              '${facts.compatibility}',
            ),
      if (profile.autoInstallHelper) l10n.remoteHostAutoInstallOn,
    ].join(' · ');
    return ValueListenableBuilder<RemoteHostConnectionState>(
      valueListenable: state,
      builder: (context, connection, _) => Row(
        children: [
          MeridianStatusDot(
            tone: remotePhaseTone(connection.phase),
            semanticLabel: l10n.remotePhase(connection.phase),
          ),
          const SizedBox(width: MeridianSpace.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  profile.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: meridian.text.label,
                ),
                Text(
                  details,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: meridian.text.caption.copyWith(
                    color: meridian.colors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          Builder(
            builder: (buttonContext) => MeridianIconButton(
              label: l10n.remoteHostActions(profile.displayName),
              icon: MeridianIcons.ellipsis,
              size: MeridianControlSize.small,
              onPressed: () {
                final box = buttonContext.findRenderObject()! as RenderBox;
                onActions(box.localToGlobal(Offset.zero) & box.size);
              },
            ),
          ),
        ],
      ),
    );
  }
}
