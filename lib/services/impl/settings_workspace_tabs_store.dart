import 'dart:async';

import '../../models/models.dart';
import '../remote_hosts_settings.dart';
import '../workspace_tabs_service.dart';

/// Persists the tab layout in the remote hosts settings section.
///
/// On startup the remote tabs open when they were open at quit, unless the
/// profile says to always or never open them.
final class SettingsWorkspaceTabsStore implements WorkspaceTabsStore {
  SettingsWorkspaceTabsStore(this.settings);

  final RemoteHostsSettings settings;

  @override
  WorkspaceTabsLayout read() {
    final state = settings.remoteHosts.value;
    final open = <String>[
      for (final id in state.openTabs)
        if (state.profile(id)?.openOnStartup != false) id,
      for (final profile in state.profiles)
        if (profile.openOnStartup == true &&
            !state.openTabs.contains(profile.id))
          profile.id,
    ];
    final active = state.activeTab;
    return WorkspaceTabsLayout(
      remoteTabs: [for (final id in open) RemoteWorkspaceTab(id)],
      activeTab: active == null || active == WorkspaceTab.local.key
          ? WorkspaceTab.local
          : active.startsWith('remote:')
          ? RemoteWorkspaceTab(active.substring('remote:'.length))
          : null,
    );
  }

  @override
  Future<void> write(WorkspaceTabsLayout layout) => settings.updateRemoteTabs([
    for (final tab in layout.remoteTabs) tab.profileId,
  ], layout.activeTab?.key);
}
