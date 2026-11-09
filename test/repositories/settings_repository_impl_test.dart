import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/impl/settings_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('returns default settings when preferences are empty', () async {
    final repository = SettingsRepositoryImpl();

    final settings = await repository.getSettings();

    expect(settings.pollingIntervalMs, AppSettings.defaultPollingIntervalMs);
    expect(
      settings.rememberTreeExpansion,
      AppSettings.defaultRememberTreeExpansion,
    );
    expect(settings.savedFilters, isEmpty);
    expect(settings.visibleColumns, AppSettings.defaultVisibleColumns);
    expect(settings.columnWidths, isEmpty);
    expect(settings.inspectorWidth, AppSettings.defaultInspectorWidth);
    expect(settings.processSortColumn, AppSettings.defaultProcessSortColumn);
    expect(
      settings.processSortDirection,
      AppSettings.defaultProcessSortDirection,
    );
    expect(settings.appearanceMode, AppAppearanceMode.system);
    expect(settings.rowHeatmap, AppSettings.defaultRowHeatmap);
    expect(settings.rowDensity, AppRowDensity.compact);
    expect(settings.releaseChannel, AppReleaseChannel.stable);
  });

  test('persists settings', () async {
    final repository = SettingsRepositoryImpl();

    await repository.saveSettings(
      const AppSettings(
        pollingIntervalMs: 1500,
        rememberTreeExpansion: false,
        savedFilters: ['Dock'],
        visibleColumns: ['pid', 'name'],
        columnWidths: {'name': 320, 'pid': 92},
        inspectorWidth: 420,
        processSortColumn: ProcessSortColumn.memory,
        processSortDirection: ProcessSortDirection.ascending,
        appearanceMode: AppAppearanceMode.dark,
        rowHeatmap: false,
        rowDensity: AppRowDensity.regular,
        releaseChannel: AppReleaseChannel.beta,
      ),
    );

    final settings = await repository.getSettings();

    expect(settings.pollingIntervalMs, 1500);
    expect(settings.rememberTreeExpansion, isFalse);
    expect(settings.savedFilters, ['Dock']);
    expect(settings.visibleColumns, ['pid', 'name']);
    expect(settings.columnWidths, {'name': 320.0, 'pid': 92.0});
    expect(settings.inspectorWidth, 420);
    expect(settings.processSortColumn, ProcessSortColumn.memory);
    expect(settings.processSortDirection, ProcessSortDirection.ascending);
    expect(settings.appearanceMode, AppAppearanceMode.dark);
    expect(settings.rowHeatmap, isFalse);
    expect(settings.rowDensity, AppRowDensity.regular);
    expect(settings.releaseChannel, AppReleaseChannel.beta);
  });

  test('expands legacy compact process columns', () async {
    SharedPreferences.setMockInitialValues({
      'visible_columns': ['name', 'pid', 'memory', 'status'],
    });
    final repository = SettingsRepositoryImpl();

    final settings = await repository.getSettings();

    expect(settings.visibleColumns, AppSettings.defaultVisibleColumns);
  });
}
