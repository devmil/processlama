import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/app/app_licenses.dart';

class _FileBundle extends CachingAssetBundle {
  final loaded = <String>[];

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(bytes);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    loaded.add(key);
    return utf8.decode(await File(key).readAsBytes());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every license document is declared as an asset', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('    - LICENSE\n'));
    expect(pubspec, contains('    - LICENSES/\n'));
    final shipped = Directory(
      'LICENSES',
    ).listSync().whereType<File>().map((f) => f.path).toSet();
    final registered = processLamaLicenseAssets.map((d) => d.path).toSet();
    // Every notice that ships beside the app is also shown in it.
    expect(registered, containsAll(shipped));
    for (final path in registered) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });

  test('registers ProcessLama, the GPL program and the inventories', () async {
    final bundle = _FileBundle();
    registerProcessLamaLicenses(bundle: bundle);
    final entries = await LicenseRegistry.licenses.toList();
    final packages = {for (final entry in entries) ...entry.packages};
    expect(
      packages,
      containsAll([
        'ProcessLama',
        'ProcessLama network eBPF program',
        'libbpf',
        'Geist',
        'Rust production dependencies',
        'Flutter production dependencies',
      ]),
    );
    final gpl = entries.firstWhere(
      (e) => e.packages.contains('ProcessLama network eBPF program'),
    );
    expect(gpl.paragraphs.first.text, contains('GNU GENERAL PUBLIC LICENSE'));
    expect(bundle.loaded, containsAll(['LICENSE', 'LICENSES/NOTICE.txt']));
  });
}
