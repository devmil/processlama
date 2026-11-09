import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/impl/remote/file_remote_icon_cache_repository.dart';
import 'package:processlama/services/impl/process_icon_service_impl.dart';

/// A PNG header with the given dimensions; the cache validates the header
/// only (the image codec decodes with `cacheWidth` later).
Uint8List png(int width, int height, {int seed = 0, int padding = 0}) {
  final bytes = BytesBuilder()
    ..add([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    ..add([0, 0, 0, 13])
    ..add('IHDR'.codeUnits);
  final dimensions = ByteData(8)
    ..setUint32(0, width)
    ..setUint32(4, height);
  bytes
    ..add(dimensions.buffer.asUint8List())
    ..add([8, 6, 0, 0, 0, seed & 0xff, 0, 0, 0])
    ..add(List.filled(padding, 0));
  return bytes.toBytes();
}

String hash(Uint8List bytes) => sha256.convert(bytes).toString();

void main() {
  late Directory root;
  late FileRemoteIconCacheRepository cache;
  var now = DateTime(2026, 10, 15);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('processlama-icons-');
    now = DateTime(2026, 10, 15);
    cache = FileRemoteIconCacheRepository(
      root: () async => root,
      clock: () => now,
    );
    await cache.initialize();
  });

  tearDown(() => root.delete(recursive: true));

  group('cache', () {
    test('stores only valid icons, by hash, atomically', () async {
      final icon = png(128, 128);
      final path = await cache.store(hash(icon), icon);
      expect(
        path,
        '${root.path}/${hash(icon).substring(0, 2)}/${hash(icon)}.png',
      );
      expect(File(path!).readAsBytesSync(), icon);
      expect(
        root.listSync(recursive: true).where((e) => e.path.endsWith('.tmp')),
        isEmpty,
      );

      expect(await cache.store('0' * 64, icon), isNull, reason: 'wrong hash');
      final text = Uint8List.fromList(
        'not a png at all, really not one'.codeUnits,
      );
      expect(await cache.store(hash(text), text), isNull, reason: 'not a PNG');
      final huge = png(513, 16);
      expect(
        await cache.store(hash(huge), huge),
        isNull,
        reason: 'over 512 px',
      );
      final heavy = png(16, 16, padding: 256 * 1024);
      expect(
        await cache.store(hash(heavy), heavy),
        isNull,
        reason: 'over 256 KiB',
      );
      expect(cache.totalBytes, icon.length);
    });

    test(
      'evicts least recently used icons but never referenced ones',
      () async {
        final icons = [
          for (var i = 0; i < 4; i++) png(16, 16, seed: i, padding: 1000),
        ];
        for (final icon in icons) {
          now = now.add(const Duration(minutes: 1));
          await cache.store(hash(icon), icon);
        }
        now = now.add(const Duration(minutes: 1));
        cache.touch([hash(icons[0])]);
        await cache.evict(
          limitBytes: icons[0].length * 2,
          keep: {hash(icons[1])},
        );
        expect(
          cache.pathFor(hash(icons[0])),
          isNotNull,
          reason: 'recently used',
        );
        expect(cache.pathFor(hash(icons[1])), isNotNull, reason: 'referenced');
        expect(cache.pathFor(hash(icons[2])), isNull);
        expect(cache.pathFor(hash(icons[3])), isNull);
      },
    );

    test('survives a restart and can be cleared', () async {
      final icon = png(64, 64);
      await cache.store(hash(icon), icon);
      await cache.flush();
      final reopened = FileRemoteIconCacheRepository(root: () async => root);
      await reopened.initialize();
      expect(reopened.pathFor(hash(icon)), isNotNull);
      await reopened.clear();
      expect(reopened.pathFor(hash(icon)), isNull);
      expect(reopened.totalBytes, 0);
    });
  });

  group('service', () {
    late ProcessIconServiceImpl service;
    late List<List<String>> fetches;
    late Map<String, Uint8List> remote;

    Future<Map<String, Uint8List>> fetch(List<String> hashes) async {
      fetches.add(List.of(hashes));
      return {
        for (final h in hashes)
          if (remote[h] != null) h: remote[h]!,
      };
    }

    setUp(() async {
      service = ProcessIconServiceImpl(cache: cache);
      await service.initialize();
      fetches = [];
      remote = {};
    });

    test('tabs and samples share one fetch per unknown icon', () async {
      final a = png(32, 32, seed: 1);
      final b = png(32, 32, seed: 2);
      remote = {hash(a): a, hash(b): b};
      final updates = service.updatesFor(ProcessRemoteIcon(hash(a)))!;
      final seen = <String?>[];
      updates.addListener(() => seen.add(updates.value));

      service.ensure('remote:1', {hash(a), hash(b)}, fetch);
      service.ensure('remote:2', {hash(a)}, fetch);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await service.idle;

      expect(fetches, hasLength(1));
      expect(fetches.single.toSet(), {hash(a), hash(b)});
      expect(seen, [cache.pathFor(hash(a))]);
      expect(service.pathFor(ProcessRemoteIcon(hash(b))), isNotNull);

      // Equal samples ask for nothing and notify nobody.
      service.ensure('remote:1', {hash(a), hash(b)}, fetch);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(fetches, hasLength(1));
      expect(seen, hasLength(1));
      expect(
        service.updatesFor(ProcessRemoteIcon(hash(a))),
        isNull,
        reason: 'cached icons cannot change any more',
      );
    });

    test('a changed icon causes exactly one new fetch', () async {
      final before = png(32, 32, seed: 3);
      final after = png(32, 32, seed: 4);
      remote = {hash(before): before, hash(after): after};
      service.ensure('remote:1', {hash(before)}, fetch);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await service.idle;
      service.ensure('remote:1', {hash(after)}, fetch);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await service.idle;
      service.ensure('remote:1', {hash(after)}, fetch);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(fetches, [
        [hash(before)],
        [hash(after)],
      ]);
    });

    test('rejected icons are retried only after a reconnect', () async {
      final bad = png(1024, 1024);
      remote = {hash(bad): bad};
      service.ensure('remote:1', {hash(bad)}, fetch);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await service.idle;
      service.ensure('remote:1', {hash(bad)}, fetch);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(fetches, hasLength(1));
      expect(service.pathFor(ProcessRemoteIcon(hash(bad))), isNull);

      service.resetFailures('remote:1');
      service.ensure('remote:1', {hash(bad)}, fetch);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await service.idle;
      expect(fetches, hasLength(2));
    });

    test('local icons resolve to their files without notifiers', () {
      const ref = ProcessFileIcon('file:///usr/share/icons/app.png');
      expect(service.pathFor(ref), 'file:///usr/share/icons/app.png');
      expect(service.updatesFor(ref), isNull);
      expect(service.pathFor(null), isNull);
    });
  });
}
