import 'dart:typed_data';

/// Remote process icons on disk, addressed by the SHA-256 of their PNG bytes
/// and shared by every host. Owned by the process icon service.
abstract interface class RemoteIconCacheRepository {
  /// Loads the index. Safe to call more than once.
  Future<void> initialize();

  /// The cached file's path, or null.
  String? pathFor(String sha256);

  /// Validates [bytes] (PNG signature, at most 512×512, at most 256 KiB,
  /// digest equal to [sha256]) and stores them atomically. Returns the path,
  /// or null when the bytes were rejected.
  Future<String?> store(String sha256, Uint8List bytes);

  /// Marks [hashes] as used now.
  void touch(Iterable<String> hashes);

  /// Evicts least recently used icons until at most [limitBytes] are kept;
  /// [keep] is never evicted.
  Future<void> evict({required int limitBytes, required Set<String> keep});

  Future<void> clear();

  int get totalBytes;
}
