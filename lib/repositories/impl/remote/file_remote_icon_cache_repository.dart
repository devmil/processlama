import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../remote_icon_cache_repository.dart';
import 'wire/contract.g.dart';

final _hashPattern = RegExp(r'^[0-9a-f]{64}$');
const _pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

/// Whether [bytes] are an acceptable icon: a PNG whose header declares at
/// most 512×512 pixels, at most 256 KiB, with the requested digest.
bool isAcceptableIcon(String sha256Hex, Uint8List bytes) {
  if (!_hashPattern.hasMatch(sha256Hex) ||
      bytes.length > RemoteWireLimits.iconBytes ||
      bytes.length < 33) {
    return false;
  }
  for (var index = 0; index < _pngSignature.length; index++) {
    if (bytes[index] != _pngSignature[index]) return false;
  }
  // The first chunk must be IHDR with the dimensions.
  final header = ByteData.sublistView(bytes);
  if (header.getUint32(8) != 13 ||
      String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') {
    return false;
  }
  final width = header.getUint32(16);
  final height = header.getUint32(20);
  if (width == 0 ||
      height == 0 ||
      width > RemoteWireLimits.iconSourcePixels ||
      height > RemoteWireLimits.iconSourcePixels) {
    return false;
  }
  return sha256.convert(bytes).toString() == sha256Hex;
}

/// `<root>/<aa>/<sha256>.png` plus `index.json` with size and last use.
class FileRemoteIconCacheRepository implements RemoteIconCacheRepository {
  FileRemoteIconCacheRepository({
    required this._root,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<Directory> Function() _root;
  final DateTime Function() _clock;
  Directory? _directory;
  Future<void>? _initialization;
  final _entries = <String, ({int bytes, int lastUsed})>{};
  Timer? _indexWrite;

  @override
  int get totalBytes =>
      _entries.values.fold(0, (total, entry) => total + entry.bytes);

  @override
  Future<void> initialize() => _initialization ??= _load();

  Future<void> _load() async {
    final directory = await _root();
    await directory.create(recursive: true);
    _directory = directory;
    final index = File('${directory.path}/index.json');
    if (!await index.exists()) return;
    try {
      final value = jsonDecode(await index.readAsString());
      if (value is! Map<String, Object?>) return;
      for (final MapEntry(:key, :value) in value.entries) {
        if (!_hashPattern.hasMatch(key) || value is! Map) continue;
        final bytes = value['bytes'];
        final lastUsed = value['lastUsed'];
        if (bytes is! int || lastUsed is! int) continue;
        if (await File(_path(key)).exists()) {
          _entries[key] = (bytes: bytes, lastUsed: lastUsed);
        }
      }
    } on FormatException {
      // A damaged index is rebuilt as icons arrive again.
    }
  }

  String _path(String hash) =>
      '${_directory!.path}/${hash.substring(0, 2)}/$hash.png';

  @override
  String? pathFor(String sha256) {
    if (_directory == null || !_entries.containsKey(sha256)) return null;
    return _path(sha256);
  }

  @override
  Future<String?> store(String sha256Hex, Uint8List bytes) async {
    await initialize();
    if (!isAcceptableIcon(sha256Hex, bytes)) return null;
    final path = _path(sha256Hex);
    final file = File(path);
    await file.parent.create(recursive: true);
    final temporary = File('$path.$pid.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(path);
    _entries[sha256Hex] = (
      bytes: bytes.length,
      lastUsed: _clock().millisecondsSinceEpoch,
    );
    _scheduleIndexWrite();
    return path;
  }

  @override
  void touch(Iterable<String> hashes) {
    final now = _clock().millisecondsSinceEpoch;
    var changed = false;
    for (final hash in hashes) {
      final entry = _entries[hash];
      if (entry != null) {
        _entries[hash] = (bytes: entry.bytes, lastUsed: now);
        changed = true;
      }
    }
    if (changed) _scheduleIndexWrite();
  }

  @override
  Future<void> evict({
    required int limitBytes,
    required Set<String> keep,
  }) async {
    await initialize();
    var total = totalBytes;
    if (total <= limitBytes) return;
    final candidates =
        _entries.entries.where((entry) => !keep.contains(entry.key)).toList()
          ..sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
    for (final candidate in candidates) {
      if (total <= limitBytes) break;
      _entries.remove(candidate.key);
      total -= candidate.value.bytes;
      try {
        await File(_path(candidate.key)).delete();
      } on FileSystemException {
        // Already gone.
      }
    }
    _scheduleIndexWrite();
  }

  @override
  Future<void> clear() async {
    await initialize();
    _entries.clear();
    _indexWrite?.cancel();
    final directory = _directory!;
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
    await directory.create(recursive: true);
  }

  void _scheduleIndexWrite() {
    _indexWrite?.cancel();
    _indexWrite = Timer(const Duration(seconds: 2), () => unawaited(flush()));
  }

  /// Writes the index now.
  Future<void> flush() async {
    _indexWrite?.cancel();
    final directory = _directory;
    if (directory == null) return;
    final index = File('${directory.path}/index.json');
    final temporary = File('${index.path}.$pid.tmp');
    await temporary.writeAsString(
      jsonEncode({
        for (final MapEntry(:key, :value) in _entries.entries)
          key: {'bytes': value.bytes, 'lastUsed': value.lastUsed},
      }),
    );
    await temporary.rename(index.path);
  }
}
