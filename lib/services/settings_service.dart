import 'package:flutter/foundation.dart';

import '../models/models.dart';

abstract interface class SettingsService {
  ValueListenable<AppSettings> get settings;

  Future<void> initialize();

  /// Flushes any pending debounced writes. Called on app shutdown so a value
  /// changed immediately before quit (e.g. finishing a resize drag) is not lost.
  /// Returns a Future that completes when the write is on disk.
  Future<void> flush();

  /// Synchronous teardown. Flushes pending writes without awaiting them; prefer
  /// [flush] from an exit hook that can await completion.
  void dispose();

  Future<void> updatePollingIntervalMs(int value);

  Future<void> updateRememberTreeExpansion(bool value);

  Future<void> updateSavedFilters(List<String> value);

  Future<void> addSavedFilter(String value);

  Future<void> removeSavedFilter(String value);

  Future<void> updateVisibleColumns(List<String> value);

  Future<void> updateColumnWidths(Map<String, double> value);

  Future<void> updateInspectorWidth(double value);

  Future<void> updateProcessSort(
    ProcessSortColumn column,
    ProcessSortDirection direction,
  );

  Future<void> updateAppearanceMode(AppAppearanceMode value);

  Future<void> updateRowHeatmap(bool value);

  Future<void> updateRowDensity(AppRowDensity value);

  Future<void> updateLanguageCode(String value);

  Future<void> updateReleaseChannel(AppReleaseChannel value);
}
