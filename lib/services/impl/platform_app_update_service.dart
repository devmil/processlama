import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../models/models.dart';
import '../app_update_service.dart';
import '../settings_service.dart';

class PlatformAppUpdateService implements AppUpdateService {
  PlatformAppUpdateService({
    required this.settingsService,
    String? feedUrl,
    String? releaseManifestUrl,
    MethodChannel? methodChannel,
    Future<String> Function(Uri uri)? fetchManifest,
    Future<InstalledAppVersion> Function()? loadInstalledVersion,
    bool? usesNativeUpdater,
    bool? isSupported,
    this.scheduledCheckIntervalSeconds = 86400,
  }) : feedUrl = feedUrl ?? _defaultFeedUrl,
       releaseManifestUrl = releaseManifestUrl ?? _defaultReleaseManifestUrl,
       _methodChannel = methodChannel ?? _defaultMethodChannel,
       _fetchManifest = fetchManifest ?? _fetchManifestDocument,
       _loadInstalledVersion =
           loadInstalledVersion ?? _loadPlatformInstalledVersion,
       _usesNativeUpdater = usesNativeUpdater ?? Platform.isMacOS,
       _isSupported =
           isSupported ??
           (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  static const _configuredFeedUrl = String.fromEnvironment(
    'PROCESSLAMA_APPCAST_URL',
  );
  static const _macOSFeedUrl =
      'https://devmil.de/processlama/download/appcast.xml';
  static const _configuredReleaseManifestUrl = String.fromEnvironment(
    'PROCESSLAMA_RELEASE_MANIFEST_URL',
  );
  static const _releaseManifestUrl =
      'https://devmil.de/processlama/_data/releases.json';
  static const _defaultFeedUrl = _configuredFeedUrl == ''
      ? _macOSFeedUrl
      : _configuredFeedUrl;
  static const _defaultReleaseManifestUrl = _configuredReleaseManifestUrl == ''
      ? _releaseManifestUrl
      : _configuredReleaseManifestUrl;
  static const _defaultMethodChannel = MethodChannel(
    'de.devmil.processlama/app_update',
  );

  final SettingsService settingsService;
  final MethodChannel _methodChannel;
  final Future<String> Function(Uri uri) _fetchManifest;
  final Future<InstalledAppVersion> Function() _loadInstalledVersion;
  final bool _usesNativeUpdater;
  final bool _isSupported;

  @override
  final String feedUrl;

  @override
  final String releaseManifestUrl;

  final int scheduledCheckIntervalSeconds;

  bool _initialized = false;
  AppReleaseChannel? _configuredReleaseChannel;

  @override
  bool get isSupported => _isSupported;

  @override
  AppReleaseChannel get releaseChannel =>
      settingsService.settings.value.releaseChannel;

  @override
  Future<InstalledAppVersion> loadInstalledVersion() => _loadInstalledVersion();

  @override
  Future<void> initialize() async {
    if (!_usesNativeUpdater) {
      return;
    }

    if (!_initialized) {
      settingsService.settings.addListener(_settingsDidChange);
      _initialized = true;
    }

    await _configureNativeUpdater();
  }

  @override
  Future<AppUpdateCheckResult> checkForUpdates() async {
    if (!isSupported) {
      throw UnsupportedError('Update checks are not supported here.');
    }

    if (_usesNativeUpdater) {
      await initialize();
      await _methodChannel.invokeMethod<void>('checkForUpdates');
      final installed = await _loadInstalledVersion();
      return AppUpdateCheckResult(
        status: AppUpdateCheckStatus.nativeCheckerOpened,
        installedVersion: installed.version,
        installedBuild: installed.build,
      );
    }

    final installed = await _loadInstalledVersion();
    final document = await _fetchManifest(Uri.parse(releaseManifestUrl));
    final decoded = jsonDecode(document);
    if (decoded is! Map<String, Object?> || decoded['schemaVersion'] != 2) {
      throw const FormatException(
        'The release list has an unsupported format.',
      );
    }

    final track = releaseChannel == AppReleaseChannel.beta
        ? decoded['beta']
        : decoded;
    if (track is! Map<String, Object?>) {
      throw const FormatException('The selected release channel is missing.');
    }
    final latest = track['latest'];
    if (latest == null) {
      return AppUpdateCheckResult(
        status: AppUpdateCheckStatus.noPublishedRelease,
        installedVersion: installed.version,
        installedBuild: installed.build,
      );
    }
    if (latest is! Map<String, Object?> ||
        latest['version'] is! String ||
        latest['build'] is! num) {
      throw const FormatException('The latest release entry is invalid.');
    }

    final availableBuild = (latest['build'] as num).toInt();
    return AppUpdateCheckResult(
      status: availableBuild > installed.build
          ? AppUpdateCheckStatus.updateAvailable
          : AppUpdateCheckStatus.upToDate,
      installedVersion: installed.version,
      installedBuild: installed.build,
      availableVersion: latest['version'] as String,
      availableBuild: availableBuild,
    );
  }

  void _settingsDidChange() {
    unawaited(_configureNativeUpdater());
  }

  Future<void> _configureNativeUpdater() async {
    if (!_usesNativeUpdater) {
      return;
    }
    final channel = releaseChannel;
    if (_configuredReleaseChannel == channel) {
      return;
    }

    await _methodChannel.invokeMethod<void>('configure', <String, Object?>{
      'feedUrl': feedUrl,
      'releaseChannel': channel.name,
      'scheduledCheckIntervalSeconds': scheduledCheckIntervalSeconds,
    });
    _configuredReleaseChannel = channel;
  }

  static Future<InstalledAppVersion> _loadPlatformInstalledVersion() async {
    final package = await PackageInfo.fromPlatform();
    final build = int.tryParse(package.buildNumber);
    if (build == null) {
      throw FormatException(
        'The installed build number is invalid: ${package.buildNumber}',
      );
    }
    return InstalledAppVersion(version: package.version, build: build);
  }

  static Future<String> _fetchManifestDocument(Uri uri) async {
    if (uri.scheme != 'https') {
      throw ArgumentError.value(uri, 'uri', 'The release list must use HTTPS.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'The release server returned HTTP ${response.statusCode}.',
          uri: uri,
        );
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }
}
