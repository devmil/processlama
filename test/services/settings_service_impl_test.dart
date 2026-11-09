import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/repositories.dart';
import 'package:processlama/services/impl/settings_service_impl.dart';

void main() {
  test('loads settings through repository abstraction', () async {
    final service = SettingsServiceImpl(
      settingsRepository: _FakeSettingsRepository(
        initialSettings: const AppSettings(pollingIntervalMs: 750),
      ),
    );

    await service.initialize();

    expect(service.settings.value.pollingIntervalMs, 750);
  });

  test('normalizes polling interval before saving', () async {
    final repository = _FakeSettingsRepository();
    final service = SettingsServiceImpl(settingsRepository: repository);

    await service.initialize();
    await service.updatePollingIntervalMs(50);

    expect(service.settings.value.pollingIntervalMs, 250);
    expect(repository.savedSettings.single.pollingIntervalMs, 250);
  });

  test('normalizes saved filters before saving', () async {
    final repository = _FakeSettingsRepository();
    final service = SettingsServiceImpl(settingsRepository: repository);

    await service.initialize();
    await service.updateSavedFilters([' dock ', 'Dock', '', 'Safari']);

    expect(service.settings.value.savedFilters, ['dock', 'Safari']);
  });

  test('removes a saved filter and persists the rest', () async {
    final repository = _FakeSettingsRepository();
    final service = SettingsServiceImpl(settingsRepository: repository);

    await service.initialize();
    await service.updateSavedFilters(['dock', 'Safari', 'kernel']);
    await service.removeSavedFilter('Safari');

    expect(service.settings.value.savedFilters, ['dock', 'kernel']);
    expect(repository.savedSettings.last.savedFilters, ['dock', 'kernel']);
  });

  test('updates appearance, visual, and release preferences', () async {
    final repository = _FakeSettingsRepository();
    final service = SettingsServiceImpl(settingsRepository: repository);

    await service.initialize();
    await service.updateAppearanceMode(AppAppearanceMode.dark);
    await service.updateRowHeatmap(false);
    await service.updateRowDensity(AppRowDensity.comfortable);
    await service.updateReleaseChannel(AppReleaseChannel.beta);

    expect(service.settings.value.appearanceMode, AppAppearanceMode.dark);
    expect(service.settings.value.rowHeatmap, isFalse);
    expect(service.settings.value.rowDensity, AppRowDensity.comfortable);
    expect(repository.savedSettings.last.rowDensity, AppRowDensity.comfortable);
    expect(service.settings.value.releaseChannel, AppReleaseChannel.beta);
  });

  test('preserves process column order while keeping name available', () async {
    final repository = _FakeSettingsRepository();
    final service = SettingsServiceImpl(settingsRepository: repository);

    await service.initialize();
    await service.updateVisibleColumns(['pid', 'cpu', 'name', 'uid']);

    expect(service.settings.value.visibleColumns, [
      'pid',
      'cpu',
      'name',
      'uid',
    ]);

    await service.updateVisibleColumns(['pid', 'uid']);

    expect(service.settings.value.visibleColumns, ['name', 'pid', 'uid']);
  });

  test('persists process sort settings', () async {
    final repository = _FakeSettingsRepository();
    final service = SettingsServiceImpl(settingsRepository: repository);

    await service.initialize();
    await service.updateProcessSort(
      ProcessSortColumn.memory,
      ProcessSortDirection.ascending,
    );

    expect(service.settings.value.processSortColumn, ProcessSortColumn.memory);
    expect(
      service.settings.value.processSortDirection,
      ProcessSortDirection.ascending,
    );
    expect(
      repository.savedSettings.single.processSortColumn,
      ProcessSortColumn.memory,
    );
  });

  test(
    'inspector width clamps, reflects in memory immediately, and persists on flush',
    () async {
      const min = 240.0;
      const max = 720.0;
      final repository = _FakeSettingsRepository();
      final service = SettingsServiceImpl(settingsRepository: repository);

      await service.initialize();

      // In-memory state reflects synchronously; persistence is debounced, so the
      // repo has not been written yet.
      await service.updateInspectorWidth(480);
      expect(service.settings.value.inspectorWidth, 480);
      expect(repository.savedSettings, isEmpty);

      await service.updateInspectorWidth(50);
      expect(service.settings.value.inspectorWidth, min);

      await service.updateInspectorWidth(9999);
      expect(service.settings.value.inspectorWidth, max);

      // Flushing (as the exit hook does) writes the latest value once.
      await service.flush();
      expect(repository.savedSettings, hasLength(1));
      expect(repository.savedSettings.single.inspectorWidth, max);
    },
  );

  test('drag-driven updates coalesce into a single persisted write', () async {
    final repository = _FakeSettingsRepository();
    final service = SettingsServiceImpl(settingsRepository: repository);

    await service.initialize();
    // Simulate a drag: many rapid updates, each reflecting in memory.
    for (var width = 300.0; width <= 600; width += 10) {
      await service.updateInspectorWidth(width);
      expect(service.settings.value.inspectorWidth, width);
    }
    // No write happened during the gesture.
    expect(repository.savedSettings, isEmpty);
    await service.flush();
    expect(repository.savedSettings, hasLength(1));
    expect(repository.savedSettings.single.inspectorWidth, 600);
  });
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository({AppSettings initialSettings = const AppSettings()})
    : _settings = initialSettings;

  AppSettings _settings;
  final savedSettings = <AppSettings>[];

  @override
  Future<AppSettings> getSettings() async => _settings;

  @override
  Future<bool> getRememberTreeExpansion() async =>
      _settings.rememberTreeExpansion;

  @override
  Future<int> getPollingIntervalMs() async => _settings.pollingIntervalMs;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
    savedSettings.add(settings);
  }

  @override
  Future<void> setPollingIntervalMs(int value) async {
    _settings = _settings.copyWith(pollingIntervalMs: value);
  }

  @override
  Future<void> setRememberTreeExpansion(bool value) async {
    _settings = _settings.copyWith(rememberTreeExpansion: value);
  }

  @override
  Future<AppAppearanceMode> getAppearanceMode() async =>
      _settings.appearanceMode;

  @override
  Future<ProcessSortColumn> getProcessSortColumn() async =>
      _settings.processSortColumn;

  @override
  Future<ProcessSortDirection> getProcessSortDirection() async =>
      _settings.processSortDirection;

  @override
  Future<bool> getRowHeatmap() async => _settings.rowHeatmap;

  @override
  Future<AppRowDensity> getRowDensity() async => _settings.rowDensity;

  @override
  Future<List<String>> getSavedFilters() async => _settings.savedFilters;

  @override
  Future<List<String>> getVisibleColumns() async => _settings.visibleColumns;

  @override
  Future<void> setAppearanceMode(AppAppearanceMode value) async {
    _settings = _settings.copyWith(appearanceMode: value);
  }

  @override
  Future<void> setProcessSortColumn(ProcessSortColumn value) async {
    _settings = _settings.copyWith(processSortColumn: value);
  }

  @override
  Future<void> setProcessSortDirection(ProcessSortDirection value) async {
    _settings = _settings.copyWith(processSortDirection: value);
  }

  @override
  Future<void> setRowHeatmap(bool value) async {
    _settings = _settings.copyWith(rowHeatmap: value);
  }

  @override
  Future<void> setRowDensity(AppRowDensity value) async {
    _settings = _settings.copyWith(rowDensity: value);
  }

  @override
  Future<void> setSavedFilters(List<String> value) async {
    _settings = _settings.copyWith(savedFilters: value);
  }

  @override
  Future<void> setVisibleColumns(List<String> value) async {
    _settings = _settings.copyWith(visibleColumns: value);
  }

  @override
  Future<String> getLanguageCode() async => _settings.languageCode;

  @override
  Future<void> setLanguageCode(String value) async {
    _settings = _settings.copyWith(languageCode: value);
  }

  @override
  Future<AppReleaseChannel> getReleaseChannel() async =>
      _settings.releaseChannel;

  @override
  Future<void> setReleaseChannel(AppReleaseChannel value) async {
    _settings = _settings.copyWith(releaseChannel: value);
  }
}
