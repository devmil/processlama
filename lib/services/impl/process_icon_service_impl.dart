import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../process_icon_service.dart';
import '../remote_hosts_settings.dart';

/// Unknown hashes are collected this long, so tabs and samples share a fetch.
const remoteIconBatchDelay = Duration(milliseconds: 100);

final class _Pending {
  _Pending(this.fetch);

  final RemoteIconFetcher fetch;
  final keys = <String>{};
}

class ProcessIconServiceImpl implements ProcessIconService {
  ProcessIconServiceImpl({
    required this.cache,
    this.remoteHostsSettings,
    this.batchSize = 64,
  });

  static final _log = Logger('ProcessIconService');

  final RemoteIconCacheRepository cache;
  final RemoteHostsSettings? remoteHostsSettings;
  final int batchSize;

  final _notifiers = <String, ValueNotifier<String?>>{};
  final _referenced = <String, Set<String>>{};
  final _failed = <String, Set<String>>{};
  final _inFlight = <String>{};
  final _pending = <String, _Pending>{};
  Timer? _batch;
  Future<void>? _initialization;

  /// Completes when every fetch started so far has finished (tests).
  Future<void> get idle => _idle?.future ?? Future<void>.value();
  Completer<void>? _idle;
  var _running = 0;

  int get _limit =>
      remoteHostsSettings?.remoteHosts.value.iconCacheBytes ??
      defaultRemoteIconCacheBytes;

  @override
  int get cacheBytes => cache.totalBytes;

  /// A missing icon cache only means remote rows keep their letters; it never
  /// blocks startup.
  @override
  Future<void> initialize() =>
      _initialization ??= cache.initialize().catchError((Object error) {
        _log.warning('remote_icon_cache_unavailable', error);
      });

  ValueNotifier<String?> _notifier(String hash) =>
      _notifiers.putIfAbsent(hash, () => ValueNotifier(cache.pathFor(hash)));

  @override
  String? pathFor(ProcessIconRef? ref) => switch (ref) {
    ProcessFileIcon(:final uri) => uri,
    ProcessRemoteIcon(:final sha256) =>
      cache.pathFor(sha256) ?? _notifiers[sha256]?.value,
    null => null,
  };

  @override
  ValueListenable<String?>? updatesFor(ProcessIconRef? ref) => switch (ref) {
    ProcessRemoteIcon(:final sha256) when cache.pathFor(sha256) == null =>
      _notifier(sha256),
    _ => null,
  };

  @override
  void ensure(String sourceKey, Set<String> hashes, RemoteIconFetcher fetch) {
    _referenced[sourceKey] = Set.of(hashes);
    cache.touch(hashes);
    final failed = _failed[sourceKey] ?? const <String>{};
    for (final hash in hashes) {
      if (cache.pathFor(hash) != null ||
          _inFlight.contains(hash) ||
          failed.contains(hash)) {
        continue;
      }
      _pending.putIfAbsent(hash, () => _Pending(fetch)).keys.add(sourceKey);
    }
    if (_pending.isNotEmpty) {
      _batch ??= Timer(remoteIconBatchDelay, _flush);
    }
  }

  void _flush() {
    _batch = null;
    final pending = Map.of(_pending);
    _pending.clear();
    final byFetcher = <RemoteIconFetcher, List<String>>{};
    for (final MapEntry(:key, :value) in pending.entries) {
      byFetcher.putIfAbsent(value.fetch, () => []).add(key);
    }
    for (final MapEntry(key: fetch, value: hashes) in byFetcher.entries) {
      for (var start = 0; start < hashes.length; start += batchSize) {
        final chunk = hashes.sublist(
          start,
          min(start + batchSize, hashes.length),
        );
        unawaited(_fetch(fetch, chunk, pending));
      }
    }
  }

  Future<void> _fetch(
    RemoteIconFetcher fetch,
    List<String> hashes,
    Map<String, _Pending> pending,
  ) async {
    _running++;
    _idle ??= Completer<void>();
    _inFlight.addAll(hashes);
    try {
      Map<String, Uint8List> fetched;
      try {
        fetched = await fetch(hashes);
      } on Object {
        fetched = const {};
      }
      for (final hash in hashes) {
        final bytes = fetched[hash];
        final path = bytes == null ? null : await cache.store(hash, bytes);
        if (path == null) {
          // Remembered for this connection; the row keeps its letter.
          for (final key in pending[hash]?.keys ?? const <String>{}) {
            _failed.putIfAbsent(key, () => <String>{}).add(hash);
          }
          continue;
        }
        _notifier(hash).value = path;
      }
      await cache.evict(
        limitBytes: _limit,
        keep: {for (final hashes in _referenced.values) ...hashes},
      );
    } on Object catch (error) {
      _log.warning('remote_icons_not_stored', error);
    } finally {
      _inFlight.removeAll(hashes);
      _running--;
      if (_running == 0) {
        _idle?.complete();
        _idle = null;
      }
    }
  }

  @override
  Future<Uint8List?> bytesFor(String sha256) async {
    final path = cache.pathFor(sha256);
    if (path == null) return null;
    try {
      return await File(path).readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> importIcons(Map<String, Uint8List> icons) async {
    await initialize();
    for (final MapEntry(:key, :value) in icons.entries) {
      if (cache.pathFor(key) != null) continue;
      final path = await cache.store(key, value);
      if (path != null) _notifier(key).value = path;
    }
  }

  @override
  void resetFailures(String sourceKey) => _failed.remove(sourceKey);

  @override
  void release(String sourceKey) {
    _referenced.remove(sourceKey);
    _failed.remove(sourceKey);
  }

  @override
  Future<void> clearCache() async {
    await cache.clear();
    for (final notifier in _notifiers.values) {
      notifier.value = null;
    }
  }
}
