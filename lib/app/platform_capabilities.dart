import 'package:flutter/foundation.dart';

import '../models/models.dart';

final class PlatformCapabilities {
  const PlatformCapabilities._();

  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows);

  static bool get isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool get isLinux =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static List<PlatformFeature> get matrix {
    return const <PlatformFeature>[
      PlatformFeature(
        name: 'Process enumeration',
        macOS: PlatformFeatureStatus.available,
        linux: PlatformFeatureStatus.available,
        windows: PlatformFeatureStatus.available,
      ),
      PlatformFeature(
        name: 'Process tree synthesis',
        macOS: PlatformFeatureStatus.available,
        linux: PlatformFeatureStatus.available,
        windows: PlatformFeatureStatus.available,
      ),
      PlatformFeature(
        name: 'Files and sockets',
        macOS: PlatformFeatureStatus.available,
        linux: PlatformFeatureStatus.planned,
        windows: PlatformFeatureStatus.planned,
      ),
      PlatformFeature(
        name: 'Network throughput',
        macOS: PlatformFeatureStatus.available,
        linux: PlatformFeatureStatus.planned,
        windows: PlatformFeatureStatus.planned,
      ),
      PlatformFeature(
        name: 'Security metadata',
        macOS: PlatformFeatureStatus.available,
        linux: PlatformFeatureStatus.unsupported,
        windows: PlatformFeatureStatus.planned,
      ),
      PlatformFeature(
        name: 'Restricted process hints',
        macOS: PlatformFeatureStatus.available,
        linux: PlatformFeatureStatus.available,
        windows: PlatformFeatureStatus.unsupported,
      ),
      PlatformFeature(
        name: 'Snapshot documents',
        macOS: PlatformFeatureStatus.available,
        linux: PlatformFeatureStatus.available,
        windows: PlatformFeatureStatus.available,
      ),
    ];
  }
}
