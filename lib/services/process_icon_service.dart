import 'dart:typed_data';

import 'process_icon_resolver.dart';

/// Fetches icon bytes by hash from one remote connection.
typedef RemoteIconFetcher =
    Future<Map<String, Uint8List>> Function(List<String> hashes);

/// Resolves process icons to local files. Remote icons are fetched once,
/// cached by content hash across hosts and restarts, and announced through a
/// notifier per hash. Owns the remote icon cache repository.
abstract interface class ProcessIconService implements ProcessIconResolver {
  Future<void> initialize();

  /// A remote source's topology names [hashes]; unknown ones are fetched
  /// with [fetch]. Replaces what [sourceKey] referenced before.
  void ensure(String sourceKey, Set<String> hashes, RemoteIconFetcher fetch);

  /// [sourceKey] reconnected: its failed hashes may be fetched once more.
  void resetFailures(String sourceKey);

  /// [sourceKey] closed: its icons may be evicted again.
  void release(String sourceKey);

  /// The cached PNG bytes of [sha256], for embedding in snapshots.
  Future<Uint8List?> bytesFor(String sha256);

  /// Stores icons a loaded snapshot embeds; invalid ones are skipped.
  Future<void> importIcons(Map<String, Uint8List> icons);

  /// Bytes the remote icon cache uses.
  int get cacheBytes;

  Future<void> clearCache();
}
