class SnapshotEntry {
  const SnapshotEntry({
    required this.path,
    required this.generatedAtUnixMs,
    required this.processCount,
    required this.platform,
    this.name,
  });

  final String path;
  final int generatedAtUnixMs;
  final int processCount;
  final String platform;
  final String? name;
}
