@TestOn('linux || mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:devmil_remote/devmil_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/repositories/impl/remote/remote_scripts.dart';
import 'package:processlama/repositories/impl/remote/wire/contract.g.dart';

const _build = '0000000000000000000000000000000000000001';
const _otherBuild = '0000000000000000000000000000000000000002';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('processlama-scripts-');
  });

  tearDown(() => home.delete(recursive: true));

  Future<ProcessResult> run(String script, {List<int>? stdin}) async {
    final process = await Process.start(
      'sh',
      ['-c', script],
      environment: {'HOME': home.path, 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin'},
    );
    if (stdin != null) process.stdin.add(stdin);
    try {
      await process.stdin.close();
    } on SocketException {
      // A script that refuses exits before reading its input; like the real
      // connection, treat the closed pipe as the end of the exchange.
    }
    final stdout = await process.stdout.transform(utf8.decoder).join();
    await process.stderr.drain<void>();
    return ProcessResult(process.pid, await process.exitCode, stdout, '');
  }

  String? marker(ProcessResult result) => StatusMarker.parse(
    lastNonEmptyLine(utf8.encode(result.stdout as String)),
    remoteInstallPrefix,
  )?.words.single;

  List<int> fakeHelper(String buildId) => utf8.encode(
    '#!/bin/sh\n'
    'case "\$1" in\n'
    '  --version) printf \'{"buildId":"$buildId"}\\n\';;\n'
    '  --remove-state) rm -rf "\$HOME/$remoteCacheRoot";;\n'
    '  --stdio) echo stdio;;\n'
    'esac\n',
  );

  String installed(String build) =>
      '${home.path}/$remoteInstallRoot/$build/$remoteHelperExecutable';

  Future<ProcessResult> install(
    List<int> bytes, {
    String? digest,
    int? size,
    String build = _build,
  }) => run(
    installScript(
      buildId: build,
      sha256: digest ?? sha256.convert(bytes).toString(),
      size: size ?? bytes.length,
    ),
    stdin: bytes,
  );

  test('the launch script reports a missing helper, then starts it', () async {
    final missing = await run(bootstrapScript(_build));
    final words = StatusMarker.parse(
      lastNonEmptyLine(utf8.encode(missing.stdout as String)),
      remoteBootstrapPrefix,
    )!.words;
    expect(words.first, 'missing');
    expect(helperTargetFromMarker(words[1]), isNotNull);

    expect(marker(await install(fakeHelper(_build))), 'ok');
    final started = await run(bootstrapScript(_build));
    expect(started.stdout, '$remoteBootstrapPrefix 1 start\nstdio\n');
  });

  test(
    'install verifies size, digest and build before moving into place',
    () async {
      final bytes = fakeHelper(_build);
      expect(marker(await install(bytes, digest: 'a' * 64)), 'damaged');
      expect(File(installed(_build)).existsSync(), isFalse);
      expect(marker(await install(bytes, size: bytes.length + 5)), 'damaged');
      expect(marker(await install(fakeHelper(_otherBuild))), 'damaged');
      expect(File(installed(_build)).existsSync(), isFalse);

      expect(marker(await install(bytes)), 'ok');
      final mode = (await File(installed(_build)).stat()).mode & 0x1ff;
      expect(mode, 0x1ed, reason: '0755');
      final directoryMode =
          (await Directory(File(installed(_build)).parent.path).stat()).mode &
          0x1ff;
      expect(directoryMode, 0x1c0, reason: '0700');
      final leftovers = File(installed(_build)).parent.listSync().where(
        (entry) => entry.path.contains('.processlama-remote-helper.'),
      );
      expect(leftovers, isEmpty);
    },
  );

  test('install refuses symbolic links on the path', () async {
    final elsewhere = await Directory('${home.path}/elsewhere').create();
    await Directory('${home.path}/.local/lib').create(recursive: true);
    await Link('${home.path}/.local/lib/processlama').create(elsewhere.path);
    expect(marker(await install(fakeHelper(_build))), 'refused');
    expect(elsewhere.listSync(), isEmpty);
  });

  test('prune removes only old, idle, other builds', () async {
    expect(marker(await install(fakeHelper(_build))), 'ok');
    final root = '${home.path}/$remoteInstallRoot';
    Future<void> build(
      String name, {
      bool old = true,
      bool running = false,
    }) async {
      final directory = await Directory('$root/$name').create(recursive: true);
      if (running) {
        await File('${directory.path}/.running.$pid').create();
      }
      if (old) {
        await Process.run('touch', ['-t', '202001010000', directory.path]);
      }
    }

    await build('0000000000000000000000000000000000000003');
    await build('0000000000000000000000000000000000000004', running: true);
    await build('0000000000000000000000000000000000000005', old: false);
    await build('not-a-build');
    await Process.run('touch', ['-t', '202001010000', '$root/$_build']);

    expect(marker(await run(pruneScript(keepBuildId: _build))), 'ok');
    final left = Directory(
      root,
    ).listSync().map((entry) => entry.path.split('/').last).toSet();
    expect(left, {
      _build,
      '0000000000000000000000000000000000000004',
      '0000000000000000000000000000000000000005',
      'not-a-build',
    });
  });

  test('uninstall removes helpers and caches and keeps other files', () async {
    expect(marker(await install(fakeHelper(_build))), 'ok');
    final cache = await Directory(
      '${home.path}/$remoteCacheRoot/icons/v1',
    ).create(recursive: true);
    final unrelated = await File(
      '${home.path}/.cache/processlama/other',
    ).create(recursive: true);
    expect(marker(await run(uninstallScript(buildId: _build))), 'ok');
    expect(
      Directory('${home.path}/.local/lib/processlama').existsSync(),
      isFalse,
    );
    expect(cache.existsSync(), isFalse);
    expect(unrelated.existsSync(), isTrue);
  });

  test('scripts take only validated build IDs and digests', () {
    expect(() => bootstrapScript('1; rm -rf /'), throwsArgumentError);
    expect(
      () => installScript(buildId: _build, sha256: 'x', size: 1),
      throwsArgumentError,
    );
    expect(
      () => installScript(buildId: _build, sha256: 'a' * 64, size: 0),
      throwsArgumentError,
    );
    expect(() => pruneScript(keepBuildId: 'ABC'), throwsArgumentError);
  });
}
