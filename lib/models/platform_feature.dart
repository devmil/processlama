enum PlatformFeatureStatus { available, planned, unsupported }

class PlatformFeature {
  const PlatformFeature({
    required this.name,
    required this.macOS,
    required this.linux,
    required this.windows,
  });

  final String name;
  final PlatformFeatureStatus macOS;
  final PlatformFeatureStatus linux;
  final PlatformFeatureStatus windows;
}
