import 'dart:convert';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/models.dart';
import '../repositories.dart';

class SettingsRepositoryImpl
    implements SettingsRepository, RemoteHostsSettingsRepository {
  static const String _pollingIntervalMsKey = 'polling_interval_ms';
  static const String _rememberTreeExpansionKey = 'remember_tree_expansion';
  static const String _savedFiltersKey = 'saved_filters';
  static const String _visibleColumnsKey = 'visible_columns';
  static const String _columnWidthsKey = 'column_widths';
  static const String _inspectorWidthKey = 'inspector_width';
  static const String _processSortColumnKey = 'process_sort_column';
  static const String _processSortDirectionKey = 'process_sort_direction';
  static const String _appearanceModeKey = 'appearance_mode';
  static const String _rowHeatmapKey = 'row_heatmap';
  static const String _rowDensityKey = 'row_density';
  static const String _languageCodeKey = 'language_code';
  static const String _releaseChannelKey = 'release_channel';
  static const String _remoteHostsKey = 'remote_hosts_v1';

  SharedPreferences? _preferences;

  @override
  Future<AppSettings> getSettings() async {
    return AppSettings(
      pollingIntervalMs: await getPollingIntervalMs(),
      rememberTreeExpansion: await getRememberTreeExpansion(),
      savedFilters: await getSavedFilters(),
      visibleColumns: await getVisibleColumns(),
      columnWidths: await getColumnWidths(),
      inspectorWidth: await getInspectorWidth(),
      processSortColumn: await getProcessSortColumn(),
      processSortDirection: await getProcessSortDirection(),
      appearanceMode: await getAppearanceMode(),
      rowHeatmap: await getRowHeatmap(),
      rowDensity: await getRowDensity(),
      languageCode: await getLanguageCode(),
      releaseChannel: await getReleaseChannel(),
    );
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    await _ensureInitialized();
    await Future.wait([
      _preferences!.setInt(_pollingIntervalMsKey, settings.pollingIntervalMs),
      _preferences!.setBool(
        _rememberTreeExpansionKey,
        settings.rememberTreeExpansion,
      ),
      _preferences!.setStringList(_savedFiltersKey, settings.savedFilters),
      _preferences!.setStringList(_visibleColumnsKey, settings.visibleColumns),
      _preferences!.setString(
        _columnWidthsKey,
        jsonEncode(settings.columnWidths),
      ),
      _preferences!.setDouble(_inspectorWidthKey, settings.inspectorWidth),
      _preferences!.setString(
        _processSortColumnKey,
        settings.processSortColumn.name,
      ),
      _preferences!.setString(
        _processSortDirectionKey,
        settings.processSortDirection.name,
      ),
      _preferences!.setString(_appearanceModeKey, settings.appearanceMode.name),
      _preferences!.setBool(_rowHeatmapKey, settings.rowHeatmap),
      _preferences!.setString(_rowDensityKey, settings.rowDensity.name),
      _preferences!.setString(_languageCodeKey, settings.languageCode),
      _preferences!.setString(_releaseChannelKey, settings.releaseChannel.name),
    ]);
  }

  @override
  Future<RemoteHostsState> getRemoteHosts() async {
    await _ensureInitialized();
    final stored = _preferences!.getString(_remoteHostsKey);
    if (stored == null) {
      return const RemoteHostsState();
    }
    try {
      return RemoteHostsState.fromJson(jsonDecode(stored));
    } on FormatException {
      return const RemoteHostsState();
    }
  }

  @override
  Future<void> saveRemoteHosts(RemoteHostsState state) async {
    await _ensureInitialized();
    final saved = await _preferences!.setString(
      _remoteHostsKey,
      jsonEncode(state.toJson()),
    );
    if (!saved) {
      throw StateError('remote_hosts_not_saved');
    }
  }

  @override
  Future<int> getPollingIntervalMs() async {
    await _ensureInitialized();
    return _preferences!.getInt(_pollingIntervalMsKey) ??
        AppSettings.defaultPollingIntervalMs;
  }

  @override
  Future<void> setPollingIntervalMs(int value) async {
    await _ensureInitialized();
    await _preferences!.setInt(_pollingIntervalMsKey, value);
  }

  @override
  Future<bool> getRememberTreeExpansion() async {
    await _ensureInitialized();
    return _preferences!.getBool(_rememberTreeExpansionKey) ??
        AppSettings.defaultRememberTreeExpansion;
  }

  @override
  Future<void> setRememberTreeExpansion(bool value) async {
    await _ensureInitialized();
    await _preferences!.setBool(_rememberTreeExpansionKey, value);
  }

  @override
  Future<List<String>> getSavedFilters() async {
    await _ensureInitialized();
    return _preferences!.getStringList(_savedFiltersKey) ?? const <String>[];
  }

  @override
  Future<void> setSavedFilters(List<String> value) async {
    await _ensureInitialized();
    await _preferences!.setStringList(_savedFiltersKey, value);
  }

  @override
  Future<List<String>> getVisibleColumns() async {
    await _ensureInitialized();
    final stored = _preferences!.getStringList(_visibleColumnsKey);
    if (stored == null || _isLegacyCompactColumnSet(stored)) {
      return AppSettings.defaultVisibleColumns;
    }
    return stored;
  }

  @override
  Future<void> setVisibleColumns(List<String> value) async {
    await _ensureInitialized();
    await _preferences!.setStringList(_visibleColumnsKey, value);
  }

  Future<Map<String, double>> getColumnWidths() async {
    await _ensureInitialized();
    final encoded = _preferences!.getString(_columnWidthsKey);
    if (encoded == null || encoded.isEmpty) {
      return const <String, double>{};
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      return const <String, double>{};
    }
    if (decoded is! Map) {
      return const <String, double>{};
    }
    return <String, double>{
      for (final entry in decoded.entries)
        if (entry.key is String &&
            AppSettings.availableColumns.contains(entry.key) &&
            entry.value is num)
          entry.key as String: (entry.value as num).toDouble(),
    };
  }

  Future<double> getInspectorWidth() async {
    await _ensureInitialized();
    return _preferences!.getDouble(_inspectorWidthKey) ??
        AppSettings.defaultInspectorWidth;
  }

  @override
  Future<ProcessSortColumn> getProcessSortColumn() async {
    await _ensureInitialized();
    return _processSortColumnFromName(
      _preferences!.getString(_processSortColumnKey),
    );
  }

  @override
  Future<void> setProcessSortColumn(ProcessSortColumn value) async {
    await _ensureInitialized();
    await _preferences!.setString(_processSortColumnKey, value.name);
  }

  @override
  Future<ProcessSortDirection> getProcessSortDirection() async {
    await _ensureInitialized();
    return _processSortDirectionFromName(
      _preferences!.getString(_processSortDirectionKey),
    );
  }

  @override
  Future<void> setProcessSortDirection(ProcessSortDirection value) async {
    await _ensureInitialized();
    await _preferences!.setString(_processSortDirectionKey, value.name);
  }

  @override
  Future<AppAppearanceMode> getAppearanceMode() async {
    await _ensureInitialized();
    return AppAppearanceMode.fromJson(
      _preferences!.getString(_appearanceModeKey),
    );
  }

  @override
  Future<void> setAppearanceMode(AppAppearanceMode value) async {
    await _ensureInitialized();
    await _preferences!.setString(_appearanceModeKey, value.name);
  }

  @override
  Future<bool> getRowHeatmap() async {
    await _ensureInitialized();
    return _preferences!.getBool(_rowHeatmapKey) ??
        AppSettings.defaultRowHeatmap;
  }

  @override
  Future<void> setRowHeatmap(bool value) async {
    await _ensureInitialized();
    await _preferences!.setBool(_rowHeatmapKey, value);
  }

  @override
  Future<AppRowDensity> getRowDensity() async {
    await _ensureInitialized();
    return AppRowDensity.fromJson(_preferences!.getString(_rowDensityKey));
  }

  @override
  Future<void> setRowDensity(AppRowDensity value) async {
    await _ensureInitialized();
    await _preferences!.setString(_rowDensityKey, value.name);
  }

  @override
  Future<String> getLanguageCode() async {
    await _ensureInitialized();
    return _preferences!.getString(_languageCodeKey) ?? _defaultLanguageCode();
  }

  @override
  Future<void> setLanguageCode(String value) async {
    await _ensureInitialized();
    await _preferences!.setString(_languageCodeKey, value);
  }

  @override
  Future<AppReleaseChannel> getReleaseChannel() async {
    await _ensureInitialized();
    final stored = _preferences!.getString(_releaseChannelKey);
    if (stored != null) {
      return AppReleaseChannel.fromJson(stored);
    }
    return _defaultReleaseChannel();
  }

  @override
  Future<void> setReleaseChannel(AppReleaseChannel value) async {
    await _ensureInitialized();
    await _preferences!.setString(_releaseChannelKey, value.name);
  }

  Future<AppReleaseChannel> _defaultReleaseChannel() {
    const configuredChannel = String.fromEnvironment(
      'PROCESSLAMA_RELEASE_CHANNEL',
    );
    if (configuredChannel.isNotEmpty) {
      return Future.value(AppReleaseChannel.fromJson(configuredChannel));
    }
    return Future.value(AppSettings.defaultReleaseChannel);
  }

  String _defaultLanguageCode() {
    final systemCode = PlatformDispatcher.instance.locale.languageCode
        .toLowerCase();
    return AppSettings.supportedLanguageCodes.contains(systemCode)
        ? systemCode
        : AppSettings.defaultLanguageCode;
  }

  Future<void> _ensureInitialized() async {
    _preferences ??= await SharedPreferences.getInstance();
  }

  bool _isLegacyCompactColumnSet(List<String> columns) {
    const legacyDefault = <String>{'name', 'pid', 'memory', 'status'};
    return columns.length == legacyDefault.length &&
        columns.toSet().containsAll(legacyDefault);
  }

  ProcessSortColumn _processSortColumnFromName(String? value) {
    for (final column in ProcessSortColumn.values) {
      if (column.name == value) {
        return column;
      }
    }
    return AppSettings.defaultProcessSortColumn;
  }

  ProcessSortDirection _processSortDirectionFromName(String? value) {
    return switch (value) {
      'ascending' => ProcessSortDirection.ascending,
      'descending' => ProcessSortDirection.descending,
      _ => AppSettings.defaultProcessSortDirection,
    };
  }
}
