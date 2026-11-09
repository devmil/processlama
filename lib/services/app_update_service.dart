import '../models/models.dart';

enum AppUpdateCheckStatus {
  nativeCheckerOpened,
  upToDate,
  updateAvailable,
  noPublishedRelease,
}

final class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.status,
    required this.installedVersion,
    required this.installedBuild,
    this.availableVersion,
    this.availableBuild,
  });

  final AppUpdateCheckStatus status;
  final String installedVersion;
  final int installedBuild;
  final String? availableVersion;
  final int? availableBuild;
}

abstract interface class AppUpdateService {
  bool get isSupported;

  String get feedUrl;

  String get releaseManifestUrl;

  AppReleaseChannel get releaseChannel;

  Future<InstalledAppVersion> loadInstalledVersion();

  Future<void> initialize();

  Future<AppUpdateCheckResult> checkForUpdates();
}

final class InstalledAppVersion {
  const InstalledAppVersion({required this.version, required this.build});

  final String version;
  final int build;
}
