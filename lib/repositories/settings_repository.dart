import '../models/models.dart';

abstract interface class SettingsRepository {
  Future<AppSettings> getSettings();

  Future<void> saveSettings(AppSettings settings);

  Future<int> getPollingIntervalMs();

  Future<void> setPollingIntervalMs(int value);

  Future<bool> getRememberTreeExpansion();

  Future<void> setRememberTreeExpansion(bool value);

  Future<List<String>> getSavedFilters();

  Future<void> setSavedFilters(List<String> value);

  Future<List<String>> getVisibleColumns();

  Future<void> setVisibleColumns(List<String> value);

  Future<ProcessSortColumn> getProcessSortColumn();

  Future<void> setProcessSortColumn(ProcessSortColumn value);

  Future<ProcessSortDirection> getProcessSortDirection();

  Future<void> setProcessSortDirection(ProcessSortDirection value);

  Future<AppAppearanceMode> getAppearanceMode();

  Future<void> setAppearanceMode(AppAppearanceMode value);

  Future<bool> getRowHeatmap();

  Future<void> setRowHeatmap(bool value);

  Future<AppRowDensity> getRowDensity();

  Future<void> setRowDensity(AppRowDensity value);

  Future<String> getLanguageCode();

  Future<void> setLanguageCode(String value);

  Future<AppReleaseChannel> getReleaseChannel();

  Future<void> setReleaseChannel(AppReleaseChannel value);
}
