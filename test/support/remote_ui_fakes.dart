import 'package:flutter/foundation.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/repositories.dart';
import 'package:processlama/services/services.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

/// A [RemoteHostService] driven by the test: profiles and connection states
/// are notifiers; connecting reports [connectResult].
class FakeRemoteHostService implements RemoteHostService {
  FakeRemoteHostService({List<RemoteHostProfile> profiles = const []})
    : hostsNotifier = ValueNotifier(RemoteHostsState(profiles: profiles));

  final ValueNotifier<RemoteHostsState> hostsNotifier;
  final states = <String, ValueNotifier<RemoteHostConnectionState>>{};
  final connects = <String>[];
  final disconnects = <String>[];
  RemoteProbeResult probeResult = const RemoteProbeResult(
    RemoteProbeOutcome.helperMissing,
  );
  RemoteHostConnectionState connectResult = const RemoteHostConnectionState(
    phase: RemoteConnectionPhase.live,
  );
  var _nextId = 1;

  void setState(String profileId, RemoteHostConnectionState state) =>
      connectionState(profileId) as ValueNotifier..value = state;

  @override
  ValueListenable<RemoteHostsState> get hosts => hostsNotifier;

  @override
  ValueListenable<RemoteHostConnectionState> connectionState(
    String profileId,
  ) => states.putIfAbsent(
    profileId,
    () => ValueNotifier(RemoteHostConnectionState.idle),
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<RemoteHostProfile> addProfile(RemoteHostProfileDraft draft) async {
    final profile = RemoteHostProfile(
      id: 'profile-${_nextId++}',
      displayName: draft.displayName ?? draft.sshAlias,
      sshAlias: draft.sshAlias,
      autoInstallHelper: draft.autoInstallHelper,
      autoReconnect: draft.autoReconnect,
      openOnStartup: draft.openOnStartup,
      backgroundRefresh: draft.backgroundRefresh,
    );
    final state = hostsNotifier.value;
    hostsNotifier.value = state.copyWith(
      profiles: [...state.profiles, profile],
    );
    return profile;
  }

  @override
  Future<void> updateProfile(RemoteHostProfile profile) async {
    final state = hostsNotifier.value;
    hostsNotifier.value = state.copyWith(
      profiles: [
        for (final existing in state.profiles)
          existing.id == profile.id ? profile : existing,
      ],
    );
  }

  @override
  Future<RemoteHostProfile> duplicateProfile(String profileId) async {
    final source = hostsNotifier.value.profile(profileId)!;
    return addProfile(
      RemoteHostProfileDraft(
        sshAlias: source.sshAlias,
        displayName: '${source.displayName} 2',
      ),
    );
  }

  @override
  Future<void> removeProfile(String profileId) async {
    final state = hostsNotifier.value;
    hostsNotifier.value = state.copyWith(
      profiles: [
        for (final profile in state.profiles)
          if (profile.id != profileId) profile,
      ],
    );
  }

  @override
  Future<RemoteProbeResult> testConnection(String alias) async => probeResult;

  @override
  Future<RemoteHostConnectionState> connect(String profileId) async {
    connects.add(profileId);
    setState(profileId, connectResult);
    return connectResult;
  }

  @override
  Future<void> disconnect(String profileId) async => disconnects.add(profileId);

  @override
  Future<RemoteHelperArtifact?> bundledHelper(
    RemoteHelperTarget target,
  ) async => null;

  @override
  Future<RemoteInstallResult> removeHelper(String profileId) async =>
      RemoteInstallResult.ok;

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A [WorkspaceTabsService] that keeps the tab list only; it creates no
/// sessions.
class FakeWorkspaceTabsService implements WorkspaceTabsService {
  FakeWorkspaceTabsService({List<String> remoteTabs = const []})
    : tabsNotifier = ValueNotifier([
        WorkspaceTab.local,
        for (final id in remoteTabs) RemoteWorkspaceTab(id),
      ]);

  final ValueNotifier<List<WorkspaceTab>> tabsNotifier;
  final activeNotifier = ValueNotifier<WorkspaceTab>(WorkspaceTab.local);
  final closed = <WorkspaceTab>[];

  @override
  ValueListenable<List<WorkspaceTab>> get tabs => tabsNotifier;

  @override
  ValueListenable<WorkspaceTab> get activeTab => activeNotifier;

  @override
  Future<bool> openTab(RemoteWorkspaceTab tab, {bool activate = true}) async {
    if (!tabsNotifier.value.contains(tab)) {
      if (tabsNotifier.value.length - 1 >= maximumRemoteTabs) {
        return false;
      }
      tabsNotifier.value = [...tabsNotifier.value, tab];
    }
    if (activate) {
      activeNotifier.value = tab;
    }
    return true;
  }

  @override
  Future<void> closeTab(WorkspaceTab tab) async {
    if (tab is! RemoteWorkspaceTab) {
      return;
    }
    closed.add(tab);
    tabsNotifier.value = [
      for (final open in tabsNotifier.value)
        if (open != tab) open,
    ];
    if (activeNotifier.value == tab) {
      activeNotifier.value = WorkspaceTab.local;
    }
  }

  @override
  void activate(WorkspaceTab tab) {
    if (tabsNotifier.value.contains(tab)) {
      activeNotifier.value = tab;
    }
  }

  @override
  void activateIndex(int index) {
    if (index >= 0 && index < tabsNotifier.value.length) {
      activeNotifier.value = tabsNotifier.value[index];
    }
  }

  @override
  void cycle({bool backwards = false}) {
    final all = tabsNotifier.value;
    final next = all.indexOf(activeNotifier.value) + (backwards ? -1 : 1);
    activeNotifier.value = all[next % all.length];
  }

  @override
  void reorder(int oldIndex, int newIndex) {
    final order = [...tabsNotifier.value];
    final moved = order.removeAt(oldIndex);
    order.insert(newIndex.clamp(1, order.length), moved);
    tabsNotifier.value = order;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records the remote hosts options that were changed.
class FakeRemoteHostsSettings implements RemoteHostsSettings {
  FakeRemoteHostsSettings(this.hosts);

  final FakeRemoteHostService hosts;

  @override
  ValueListenable<RemoteHostsState> get remoteHosts => hosts.hostsNotifier;

  @override
  Future<void> updateRemoteIconCacheBytes(int bytes) async =>
      hosts.hostsNotifier.value = hosts.hostsNotifier.value.copyWith(
        iconCacheBytes: bytes,
      );

  @override
  Future<void> updateDefaultBackgroundRefresh(
    BackgroundRefreshMode mode,
  ) async => hosts.hostsNotifier.value = hosts.hostsNotifier.value.copyWith(
    defaultBackgroundRefresh: mode,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeProcessIconService implements ProcessIconService {
  var clears = 0;

  @override
  int cacheBytes = 0;

  @override
  Future<void> clearCache() async {
    clears++;
    cacheBytes = 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The remote host services the explorer screen reads, as fakes.
List<SingleChildWidget> remoteUiProviders({
  FakeRemoteHostService? hosts,
  FakeWorkspaceTabsService? tabs,
  FakeProcessIconService? icons,
}) {
  final remoteHosts = hosts ?? FakeRemoteHostService();
  return [
    Provider<RemoteHostService>.value(value: remoteHosts),
    Provider<WorkspaceTabsService>.value(
      value: tabs ?? FakeWorkspaceTabsService(),
    ),
    Provider<RemoteHostsSettings>.value(
      value: FakeRemoteHostsSettings(remoteHosts),
    ),
    Provider<ProcessIconService>.value(
      value: icons ?? FakeProcessIconService(),
    ),
  ];
}
