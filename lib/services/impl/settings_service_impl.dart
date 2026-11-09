import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../remote_hosts_settings.dart';
import '../settings_service.dart';

class SettingsServiceImpl implements SettingsService, RemoteHostsSettings {
  SettingsServiceImpl({
    required this.settingsRepository,
    RemoteHostsSettingsRepository? remoteHostsRepository,
  }) : remoteHostsRepository =
           remoteHostsRepository ??
           (settingsRepository is RemoteHostsSettingsRepository
               ? settingsRepository as RemoteHostsSettingsRepository
               : MemoryRemoteHostsSettingsRepository());

  final SettingsRepository settingsRepository;
  final RemoteHostsSettingsRepository remoteHostsRepository;
  final ValueNotifier<RemoteHostsState> _remoteHosts = ValueNotifier(
    const RemoteHostsState(),
  );

  /// Remote hosts saves run one at a time, in order.
  Future<void> _remoteHostsWrites = Future<void>.value();

  final ValueNotifier<AppSettings> _settings = ValueNotifier<AppSettings>(
    const AppSettings(),
  );

  /// Coalesces disk writes for drag-driven settings (column widths, inspector
  /// width). These change many times per second during a gesture, so writing on
  /// every call thrashes SharedPreferences. The in-memory value updates
  /// synchronously (so the UI tracks the pointer); only the persistence is
  /// delayed. See [_schedulePersist].
  Timer? _persistTimer;

  @override
  ValueListenable<AppSettings> get settings => _settings;

  @override
  ValueListenable<RemoteHostsState> get remoteHosts => _remoteHosts;

  @override
  Future<void> initialize() async {
    _settings.value = await settingsRepository.getSettings();
    _remoteHosts.value = await remoteHostsRepository.getRemoteHosts();
  }

  /// Publishes [apply] applied to the current value, saves it, and on a
  /// rejected save applies [restore] to the then-current value, so changes
  /// made meanwhile to other sections survive.
  Future<void> _changeRemoteHosts(
    String section,
    RemoteHostsState Function(RemoteHostsState current) apply,
    RemoteHostsState Function(RemoteHostsState current) restore,
  ) {
    _remoteHosts.value = apply(_remoteHosts.value);
    final write = _remoteHostsWrites.then((_) async {
      try {
        // The value at save time: a section restored after an earlier
        // rejected save is persisted too.
        await remoteHostsRepository.saveRemoteHosts(_remoteHosts.value);
      } on Object {
        _remoteHosts.value = restore(_remoteHosts.value);
        throw RemoteHostsSaveFailure(section);
      }
    });
    _remoteHostsWrites = write.catchError((Object _) {});
    return write;
  }

  void _validate(RemoteHostProfile profile) {
    if (!RemoteHostProfile.isValidAlias(profile.sshAlias)) {
      throw const RemoteHostProfileRejected(
        RemoteHostProfileRejection.invalidAlias,
      );
    }
    if (!RemoteHostProfile.isValidDisplayName(profile.displayName)) {
      throw const RemoteHostProfileRejected(
        RemoteHostProfileRejection.invalidDisplayName,
      );
    }
  }

  static List<RemoteHostProfile> _replace(
    List<RemoteHostProfile> profiles,
    String id,
    RemoteHostProfile Function(RemoteHostProfile profile) change,
  ) => List.unmodifiable([
    for (final profile in profiles)
      profile.id == id ? change(profile) : profile,
  ]);

  @override
  Future<void> addRemoteHostProfile(RemoteHostProfile profile) {
    _validate(profile);
    final current = _remoteHosts.value;
    if (current.profile(profile.id) != null) {
      throw const RemoteHostProfileRejected(
        RemoteHostProfileRejection.duplicateId,
      );
    }
    if (current.profiles.length >= maximumRemoteHostProfiles) {
      throw const RemoteHostProfileRejected(
        RemoteHostProfileRejection.tooManyProfiles,
      );
    }
    return _changeRemoteHosts(
      'profile',
      (state) => state.copyWith(
        profiles: List.unmodifiable([...state.profiles, profile]),
      ),
      (state) => state.copyWith(
        profiles: List.unmodifiable(
          state.profiles.where((stored) => stored.id != profile.id),
        ),
        openTabs: List.unmodifiable(
          state.openTabs.where((id) => id != profile.id),
        ),
      ),
    );
  }

  @override
  Future<void> updateRemoteHostProfile(RemoteHostProfile profile) {
    _validate(profile);
    final previous = _remoteHosts.value.profile(profile.id);
    if (previous == null) {
      throw const RemoteHostProfileRejected(
        RemoteHostProfileRejection.unknownProfile,
      );
    }
    RemoteHostProfile edit(RemoteHostProfile stored, RemoteHostProfile from) =>
        stored.copyWith(
          displayName: from.displayName.trim(),
          sshAlias: from.sshAlias,
          autoInstallHelper: from.autoInstallHelper,
          autoReconnect: from.autoReconnect,
          openOnStartup: () => from.openOnStartup,
          backgroundRefresh: () => from.backgroundRefresh,
          // A different host behind a new alias is not the one we knew.
          lastKnown: from.sshAlias == stored.sshAlias ? null : () => null,
        );
    return _changeRemoteHosts(
      'profile',
      (state) => state.copyWith(
        profiles: _replace(
          state.profiles,
          profile.id,
          (stored) => edit(stored, profile),
        ),
      ),
      (state) => state.copyWith(
        profiles: _replace(
          state.profiles,
          profile.id,
          (stored) => edit(
            stored,
            previous,
          ).copyWith(lastKnown: () => previous.lastKnown),
        ),
      ),
    );
  }

  @override
  Future<void> removeRemoteHostProfile(String id) {
    final current = _remoteHosts.value;
    final index = current.profiles.indexWhere((profile) => profile.id == id);
    if (index < 0) {
      return Future<void>.value();
    }
    final removed = current.profiles[index];
    final tabIndex = current.openTabs.indexOf(id);
    return _changeRemoteHosts(
      'profile',
      (state) => state.copyWith(
        profiles: List.unmodifiable(
          state.profiles.where((profile) => profile.id != id),
        ),
        openTabs: List.unmodifiable(state.openTabs.where((tab) => tab != id)),
        activeTab: state.activeTab == 'remote:$id' ? () => 'local' : null,
      ),
      (state) {
        final profiles = [...state.profiles];
        profiles.insert(index.clamp(0, profiles.length), removed);
        final tabs = [...state.openTabs];
        if (tabIndex >= 0) {
          tabs.insert(tabIndex.clamp(0, tabs.length), id);
        }
        return state.copyWith(
          profiles: List.unmodifiable(profiles),
          openTabs: List.unmodifiable(tabs),
        );
      },
    );
  }

  @override
  Future<void> updateRemoteHostFacts(String id, RemoteHostFacts facts) {
    final previous = _remoteHosts.value.profile(id);
    if (previous == null || previous.lastKnown == facts) {
      return Future<void>.value();
    }
    return _changeRemoteHosts(
      'profile',
      (state) => state.copyWith(
        profiles: _replace(
          state.profiles,
          id,
          (stored) => stored.copyWith(lastKnown: () => facts),
        ),
      ),
      (state) => state.copyWith(
        profiles: _replace(
          state.profiles,
          id,
          (stored) => stored.copyWith(lastKnown: () => previous.lastKnown),
        ),
      ),
    );
  }

  @override
  Future<void> updateRemoteTabs(List<String> openTabs, String? activeTab) {
    final previous = _remoteHosts.value;
    final known = {for (final profile in previous.profiles) profile.id};
    final tabs = List<String>.unmodifiable(
      openTabs.where(known.contains).toSet(),
    );
    if (listEquals(tabs, previous.openTabs) &&
        activeTab == previous.activeTab) {
      return Future<void>.value();
    }
    return _changeRemoteHosts(
      'tabs',
      (state) => state.copyWith(openTabs: tabs, activeTab: () => activeTab),
      (state) => state.copyWith(
        openTabs: List.unmodifiable(
          previous.openTabs.where(
            (id) => state.profiles.any((profile) => profile.id == id),
          ),
        ),
        activeTab: () => previous.activeTab,
      ),
    );
  }

  @override
  Future<void> updateRemoteIconCacheBytes(int bytes) {
    final previous = _remoteHosts.value.iconCacheBytes;
    final next = bytes.clamp(1024 * 1024, 4096 * 1024 * 1024);
    if (next == previous) {
      return Future<void>.value();
    }
    return _changeRemoteHosts(
      'options',
      (state) => state.copyWith(iconCacheBytes: next),
      (state) => state.copyWith(iconCacheBytes: previous),
    );
  }

  @override
  Future<void> updateDefaultBackgroundRefresh(BackgroundRefreshMode mode) {
    final previous = _remoteHosts.value.defaultBackgroundRefresh;
    if (mode == previous) {
      return Future<void>.value();
    }
    return _changeRemoteHosts(
      'options',
      (state) => state.copyWith(defaultBackgroundRefresh: mode),
      (state) => state.copyWith(defaultBackgroundRefresh: previous),
    );
  }

  @override
  void dispose() {
    final timer = _persistTimer;
    if (timer != null) {
      timer.cancel();
      _persistTimer = null;
      unawaited(settingsRepository.saveSettings(_settings.value));
    }
  }

  @override
  Future<void> flush() {
    final timer = _persistTimer;
    if (timer == null) {
      return Future<void>.value();
    }
    timer.cancel();
    _persistTimer = null;
    return settingsRepository.saveSettings(_settings.value);
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, () {
      _persistTimer = null;
      settingsRepository.saveSettings(_settings.value);
    });
  }

  @override
  Future<void> updatePollingIntervalMs(int value) async {
    final normalized = value.clamp(250, 10000);
    final next = _settings.value.copyWith(pollingIntervalMs: normalized);
    await settingsRepository.saveSettings(next);
    _settings.value = next;
  }

  @override
  Future<void> updateRememberTreeExpansion(bool value) async {
    final next = _settings.value.copyWith(rememberTreeExpansion: value);
    await settingsRepository.saveSettings(next);
    _settings.value = next;
  }

  @override
  Future<void> updateSavedFilters(List<String> value) async {
    final normalized = _normalizeFilters(value);
    final next = _settings.value.copyWith(savedFilters: normalized);
    await settingsRepository.saveSettings(next);
    _settings.value = next;
  }

  @override
  Future<void> addSavedFilter(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return;
    }

    await updateSavedFilters(<String>[
      normalized,
      ..._settings.value.savedFilters.where(
        (filter) => filter.toLowerCase() != normalized.toLowerCase(),
      ),
    ]);
  }

  @override
  Future<void> removeSavedFilter(String value) async {
    await updateSavedFilters(<String>[
      for (final filter in _settings.value.savedFilters)
        if (filter != value) filter,
    ]);
  }

  @override
  Future<void> updateVisibleColumns(List<String> value) async {
    final normalized = _normalizeColumns(value);
    final next = _settings.value.copyWith(
      visibleColumns: normalized.isEmpty
          ? AppSettings.defaultVisibleColumns
          : normalized,
    );
    await settingsRepository.saveSettings(next);
    _settings.value = next;
  }

  @override
  Future<void> updateColumnWidths(Map<String, double> value) async {
    // In-memory state updates synchronously so the divider tracks the pointer
    // this frame; the disk write is debounced via [_schedulePersist] so a drag
    // does not rewrite every key on every frame.
    final next = _settings.value.copyWith(
      columnWidths: _normalizeColumnWidths(value),
    );
    _settings.value = next;
    _schedulePersist();
  }

  @override
  Future<void> updateInspectorWidth(double value) async {
    final next = _settings.value.copyWith(
      inspectorWidth: value.clamp(_minInspectorWidth, _maxInspectorWidth),
    );
    _settings.value = next;
    _schedulePersist();
  }

  @override
  Future<void> updateProcessSort(
    ProcessSortColumn column,
    ProcessSortDirection direction,
  ) async {
    final next = _settings.value.copyWith(
      processSortColumn: column,
      processSortDirection: direction,
    );
    await settingsRepository.saveSettings(next);
    _settings.value = next;
  }

  @override
  Future<void> updateAppearanceMode(AppAppearanceMode value) async {
    final next = _settings.value.copyWith(appearanceMode: value);
    await settingsRepository.saveSettings(next);
    _settings.value = next;
  }

  @override
  Future<void> updateRowHeatmap(bool value) async {
    final next = _settings.value.copyWith(rowHeatmap: value);
    await settingsRepository.saveSettings(next);
    _settings.value = next;
  }

  @override
  Future<void> updateRowDensity(AppRowDensity value) async {
    final next = _settings.value.copyWith(rowDensity: value);
    await settingsRepository.saveSettings(next);
    _settings.value = next;
  }

  @override
  Future<void> updateLanguageCode(String value) async {
    final next = _settings.value.copyWith(languageCode: value);
    await settingsRepository.saveSettings(next);
    _settings.value = next;
  }

  @override
  Future<void> updateReleaseChannel(AppReleaseChannel value) async {
    final next = _settings.value.copyWith(releaseChannel: value);
    await settingsRepository.saveSettings(next);
    _settings.value = next;
  }

  List<String> _normalizeFilters(List<String> value) {
    final filters = <String>[];
    final seen = <String>{};
    for (final filter in value) {
      final normalized = filter.trim();
      final key = normalized.toLowerCase();
      if (normalized.isEmpty || seen.contains(key)) {
        continue;
      }
      seen.add(key);
      filters.add(normalized);
    }
    return filters.take(10).toList();
  }

  List<String> _normalizeColumns(List<String> value) {
    final columns = <String>[];
    for (final column in value) {
      if (!AppSettings.availableColumns.contains(column) ||
          columns.contains(column)) {
        continue;
      }
      columns.add(column);
    }
    if (!columns.contains('name')) {
      columns.insert(0, 'name');
    }
    return columns;
  }

  Map<String, double> _normalizeColumnWidths(Map<String, double> value) {
    return <String, double>{
      for (final entry in value.entries)
        if (AppSettings.availableColumns.contains(entry.key))
          entry.key: entry.value.clamp(52, 720).toDouble(),
    };
  }

  static const double _minInspectorWidth = 240;
  static const double _maxInspectorWidth = 720;

  /// How long after the last drag-driven change to wait before persisting.
  /// Short enough to feel immediate on release, long enough to coalesce the
  /// ~60 updates/second a drag generates into a single disk write.
  static const Duration _persistDebounce = Duration(milliseconds: 400);
}
