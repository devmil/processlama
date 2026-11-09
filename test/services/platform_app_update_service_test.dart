import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/services/impl/platform_app_update_service.dart';
import 'package:processlama/services/services.dart';

void main() {
  group('PlatformAppUpdateService portable checks', () {
    test('reports a newer beta build', () async {
      final service = _service(
        channel: AppReleaseChannel.beta,
        installedBuild: 15,
        stable: _release('1.0.0', 14),
        beta: _release('1.0.0-beta.14', 16),
      );

      final result = await service.checkForUpdates();

      expect(result.status, AppUpdateCheckStatus.updateAvailable);
      expect(result.availableVersion, '1.0.0-beta.14');
      expect(result.availableBuild, 16);
    });

    test('uses the stable track when stable is selected', () async {
      final service = _service(
        channel: AppReleaseChannel.stable,
        installedBuild: 15,
        stable: _release('1.0.0', 15),
        beta: _release('1.1.0-beta.1', 16),
      );

      final result = await service.checkForUpdates();

      expect(result.status, AppUpdateCheckStatus.upToDate);
      expect(result.availableVersion, '1.0.0');
    });

    test('reports an empty selected channel', () async {
      final service = _service(
        channel: AppReleaseChannel.stable,
        installedBuild: 15,
        stable: null,
        beta: _release('1.1.0-beta.1', 16),
      );

      final result = await service.checkForUpdates();

      expect(result.status, AppUpdateCheckStatus.noPublishedRelease);
    });

    test('rejects an unsupported manifest schema', () async {
      final settings = _SettingsService(AppReleaseChannel.stable);
      final service = PlatformAppUpdateService(
        settingsService: settings,
        usesNativeUpdater: false,
        isSupported: true,
        fetchManifest: (_) async => '{"schemaVersion":1}',
        loadInstalledVersion: () async =>
            const InstalledAppVersion(version: '1.0.0', build: 15),
      );

      expect(service.checkForUpdates(), throwsFormatException);
    });
  });
}

PlatformAppUpdateService _service({
  required AppReleaseChannel channel,
  required int installedBuild,
  required Map<String, Object?>? stable,
  required Map<String, Object?>? beta,
}) {
  final document = jsonEncode({
    'schemaVersion': 2,
    'latest': stable,
    'beta': {'latest': beta, 'history': <Object>[]},
    'history': <Object>[],
  });
  return PlatformAppUpdateService(
    settingsService: _SettingsService(channel),
    usesNativeUpdater: false,
    isSupported: true,
    fetchManifest: (_) async => document,
    loadInstalledVersion: () async =>
        InstalledAppVersion(version: '1.0.0-beta.13', build: installedBuild),
  );
}

Map<String, Object?> _release(String version, int build) => {
  'version': version,
  'build': build,
};

final class _SettingsService implements SettingsService {
  _SettingsService(AppReleaseChannel channel)
    : settings = ValueNotifier(AppSettings(releaseChannel: channel));

  @override
  final ValueNotifier<AppSettings> settings;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> flush() async {}

  @override
  void dispose() => settings.dispose();

  @override
  Future<void> updateAppearanceMode(AppAppearanceMode value) async {}

  @override
  Future<void> updatePollingIntervalMs(int value) async {}

  @override
  Future<void> updateReleaseChannel(AppReleaseChannel value) async {}

  @override
  Future<void> updateRememberTreeExpansion(bool value) async {}

  @override
  Future<void> updateRowHeatmap(bool value) async {}

  @override
  Future<void> updateRowDensity(AppRowDensity value) async {}

  @override
  Future<void> updateSavedFilters(List<String> value) async {}

  @override
  Future<void> addSavedFilter(String value) async {}

  @override
  Future<void> removeSavedFilter(String value) async {}

  @override
  Future<void> updateVisibleColumns(List<String> value) async {}

  @override
  Future<void> updateColumnWidths(Map<String, double> value) async {}

  @override
  Future<void> updateInspectorWidth(double value) async {}

  @override
  Future<void> updateProcessSort(
    ProcessSortColumn column,
    ProcessSortDirection direction,
  ) async {}

  @override
  Future<void> updateLanguageCode(String value) async {}
}
