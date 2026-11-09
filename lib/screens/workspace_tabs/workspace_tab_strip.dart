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

/// Opens [profileId] in a tab (or selects its tab) and connects, asking to
/// install the helper when the host needs it.
Future<void> openRemoteHostTab(BuildContext context, String profileId) async {
  final tabs = context.read<WorkspaceTabsService>();
  final workflows = remoteHostWorkflows(context);
  final l10n = context.l10n;
  final opened = await tabs.openTab(RemoteWorkspaceTab(profileId));
  if (!opened) {
    if (context.mounted) {
      showMeridianToast(
        context,
        message: l10n.remoteTabLimit('$maximumRemoteTabs'),
        tone: MeridianToastTone.error,
      );
    }
    return;
  }
  await workflows.connect(profileId);
}

/// The main window's tabs (§4.1): Local first and fixed, the remote tabs
/// in a Meridian tab strip, a chevron menu when they do not fit, and the
/// `+` menu.
///
/// Meridian's strip has no tab that cannot be closed, so Local is a pill
/// of its own before the strip.
class WorkspaceTabStrip extends StatefulWidget {
  const WorkspaceTabStrip({super.key, required this.onManageRemoteHosts});

  /// Opens Settings → Remote hosts.
  final VoidCallback onManageRemoteHosts;

  @override
  State<WorkspaceTabStrip> createState() => WorkspaceTabStripState();
}

class WorkspaceTabStripState extends State<WorkspaceTabStrip> {
  final _addButton = GlobalKey(debugLabel: 'workspace-tab-add');

  late final WorkspaceTabsService _tabs = context.read<WorkspaceTabsService>();
  late final RemoteHostService _hosts = context.read<RemoteHostService>();

  /// The connection states of the hosts with a tab, merged so one builder
  /// follows all of them.
  Listenable _states = const _NoListenable();
  List<String> _stateIds = const [];

  Listenable _stateListenable(List<WorkspaceTab> tabs) {
    final ids = [
      for (final tab in tabs)
        if (tab case RemoteWorkspaceTab(:final profileId)) profileId,
    ];
    if (!listEquals(ids, _stateIds)) {
      _stateIds = ids;
      _states = Listenable.merge([
        for (final id in ids) _hosts.connectionState(id),
      ]);
    }
    return _states;
  }

  /// Opens the `+` menu at its button.
  void openMenu() {
    final box = _addButton.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return;
    }
    final origin = box.localToGlobal(Offset.zero);
    unawaited(
      showMeridianMenu(
        context,
        anchor: origin & box.size,
        entries: _addMenuEntries(),
      ),
    );
  }

  List<MeridianMenuEntry> _addMenuEntries() {
    final l10n = context.l10n;
    final open = {
      for (final tab in _tabs.tabs.value)
        if (tab case RemoteWorkspaceTab(:final profileId)) profileId,
    };
    final closed = [
      for (final profile in _hosts.hosts.value.profiles)
        if (!open.contains(profile.id)) profile,
    ];
    return [
      for (final profile in closed)
        MeridianMenuItem(
          label: profile.displayName,
          leading: MeridianStatusDot(
            tone: remotePhaseTone(
              _hosts.connectionState(profile.id).value.phase,
            ),
          ),
          hint: l10n.remotePhase(
            _hosts.connectionState(profile.id).value.phase,
          ),
          onSelected: () => unawaited(openRemoteHostTab(context, profile.id)),
        ),
      if (closed.isEmpty) MeridianMenuItem(label: l10n.remoteHostMenuEmpty),
      const MeridianMenuDivider(),
      MeridianMenuItem(
        label: l10n.remoteHostAddMenu,
        icon: MeridianIcons.circlePlus,
        onSelected: () => unawaited(_addHost()),
      ),
      MeridianMenuItem(
        label: l10n.remoteHostManageMenu,
        icon: MeridianIcons.server,
        onSelected: widget.onManageRemoteHosts,
      ),
    ];
  }

  Future<void> _addHost() async {
    final profile = await showRemoteHostEditor(context);
    if (profile != null && mounted) {
      await openRemoteHostTab(context, profile.id);
    }
  }

  void _openAllTabsMenu(Rect anchor, List<WorkspaceTab> tabs) {
    final l10n = context.l10n;
    final active = _tabs.activeTab.value;
    unawaited(
      showMeridianMenu(
        context,
        anchor: anchor,
        entries: [
          for (final tab in tabs)
            MeridianMenuItem(
              label: switch (tab) {
                LocalWorkspaceTab() => l10n.remoteTabLocal,
                RemoteWorkspaceTab(:final profileId) =>
                  _hosts.hosts.value.profile(profileId)?.displayName ?? '',
              },
              checked: tab == active,
              onSelected: () => _tabs.activate(tab),
            ),
        ],
      ),
    );
  }

  MeridianStripTab<String, String> _remoteTab(
    BuildContext context,
    RemoteWorkspaceTab tab,
  ) {
    final l10n = context.l10n;
    final profile = _hosts.hosts.value.profile(tab.profileId);
    final state = _hosts.connectionState(tab.profileId).value;
    final name = profile?.displayName ?? '';
    final facts = state.hello?.facts ?? profile?.lastKnown;
    final status = l10n.remotePhase(state.phase);
    return MeridianStripTab<String, String>(
      id: tab.profileId,
      label: name,
      leading: MeridianStatusDot(
        key: ValueKey('remote-tab-status-${tab.profileId}'),
        tone: remotePhaseTone(state.phase),
        halo: state.phase == RemoteConnectionPhase.live,
      ),
      tooltip: facts == null
          ? profile?.sshAlias
          : l10n.remoteTabTooltip(
              profile?.sshAlias ?? '',
              remotePlatform(facts.target),
              '${facts.compatibility}',
            ),
      semanticLabel: l10n.remoteTabSemantics(name, status),
      renamable: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      key: const ValueKey('workspace-tab-strip'),
      height: MeridianLayout.tabStripHeight,
      color: context.meridian.colors.ground,
      padding: const EdgeInsets.symmetric(horizontal: MeridianSpace.space3),
      child: ValueListenableBuilder<List<WorkspaceTab>>(
        valueListenable: _tabs.tabs,
        builder: (context, tabs, _) => ListenableBuilder(
          listenable: Listenable.merge([
            _tabs.activeTab,
            _hosts.hosts,
            _stateListenable(tabs),
          ]),
          builder: (context, _) {
            final active = _tabs.activeTab.value;
            final remote = [
              for (final tab in tabs)
                if (tab is RemoteWorkspaceTab) tab,
            ];
            return LayoutBuilder(
              builder: (context, constraints) {
                const controls = MeridianSize.controlSm * 2;
                final stripWidth =
                    (constraints.maxWidth -
                            _LocalTabPill.width -
                            controls -
                            MeridianSpace.space3)
                        .clamp(0.0, double.infinity);
                final overflowing =
                    remote.length * MeridianLayout.tabPillMinWidth > stripWidth;
                return Row(
                  children: [
                    _LocalTabPill(
                      selected: active is LocalWorkspaceTab,
                      onPressed: () => _tabs.activate(WorkspaceTab.local),
                    ),
                    if (remote.isNotEmpty)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: stripWidth),
                        child: MeridianTabStrip<String, String>(
                          tabs: [
                            for (final tab in remote) _remoteTab(context, tab),
                          ],
                          activeTab: active is RemoteWorkspaceTab
                              ? active.profileId
                              : null,
                          onActivate: (id) =>
                              _tabs.activate(RemoteWorkspaceTab(id)),
                          onClose: (id) =>
                              unawaited(_tabs.closeTab(RemoteWorkspaceTab(id))),
                          onMoveTab: (id, index, _) {
                            final from = tabs.indexOf(RemoteWorkspaceTab(id));
                            _tabs.reorder(from, index + 1);
                          },
                          labels: MeridianTabStripLabels(
                            close: l10n.remoteTabClose,
                            moveLeft: l10n.remoteTabMoveLeft,
                            moveRight: l10n.remoteTabMoveRight,
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (overflowing)
                      Builder(
                        builder: (buttonContext) => MeridianIconButton(
                          key: const ValueKey('workspace-tab-overflow'),
                          label: l10n.remoteTabMore,
                          icon: MeridianIcons.chevronDown,
                          size: MeridianControlSize.small,
                          onGround: true,
                          onPressed: () {
                            final box =
                                buttonContext.findRenderObject()! as RenderBox;
                            _openAllTabsMenu(
                              box.localToGlobal(Offset.zero) & box.size,
                              tabs,
                            );
                          },
                        ),
                      ),
                    MeridianIconButton(
                      key: _addButton,
                      label: l10n.remoteTabOpenMenu,
                      icon: MeridianIcons.plus,
                      size: MeridianControlSize.small,
                      onGround: true,
                      onPressed: openMenu,
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// The Local tab: a strip pill that can be selected but never closed.
class _LocalTabPill extends StatelessWidget {
  const _LocalTabPill({required this.selected, required this.onPressed});

  static const double width = MeridianLayout.tabPillMinWidth;

  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final meridian = context.meridian;
    final colors = meridian.colors;
    final l10n = context.l10n;
    final radius = BorderRadius.circular(meridian.radius.md);
    return Semantics(
      key: const ValueKey('workspace-tab-local'),
      excludeSemantics: true,
      button: true,
      selected: selected,
      label: l10n.remoteTabLocal,
      onTap: onPressed,
      child: MeridianInteraction(
        onTap: onPressed,
        borderRadius: radius,
        builder: (context, state) => Center(
          child: AnimatedContainer(
            duration: meridianHoverDuration(context, state.hovered),
            width: width,
            height: MeridianLayout.tabPillHeight,
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: MeridianSpace.space4,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? colors.pane
                  : state.hovered
                  ? colors.groundHover
                  : meridianClear(colors.groundHover),
              borderRadius: radius,
              boxShadow: selected ? meridian.shadows.shadowPane : null,
            ),
            child: Row(
              children: [
                MeridianIcon(
                  MeridianIcons.monitor,
                  size: MeridianIconSize.small,
                  color: selected ? colors.ink : colors.inkMuted,
                ),
                const SizedBox(width: MeridianSpace.space3),
                Flexible(
                  child: Text(
                    l10n.remoteTabLocal,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: meridian.text.label.copyWith(
                      color: selected || state.hovered
                          ? colors.ink
                          : colors.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoListenable implements Listenable {
  const _NoListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
