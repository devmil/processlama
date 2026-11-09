// The --helper lane of scripts/verify_remote_hosts.py: the real helper over a
// local pipe, started through the real launch script, without SSH.
//
//   PROCESSLAMA_REMOTE_HELPER=<path> flutter test test_remote/helper_pipe_test.dart
import 'dart:io';

import 'package:devmil_remote/devmil_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/impl/remote/remote_scripts.dart';
import 'package:processlama/repositories/impl/remote/wire/contract.g.dart';
import 'package:processlama/repositories/impl/remote/wire/messages.dart';

const _config = RemoteChannelConfig(
  magic: remoteHelperMagic,
  buildId: remoteHelperBuildId,
  bootstrapPrefix: remoteBootstrapPrefix,
);

void main() {
  final helperPath = Platform.environment['PROCESSLAMA_REMOTE_HELPER'];
  late Directory home;

  setUp(() async {
    if (helperPath == null || !File(helperPath).existsSync()) {
      fail('PROCESSLAMA_REMOTE_HELPER must name a built helper');
    }
    home = await Directory.systemTemp.createTemp('processlama-helper-lane-');
  });

  tearDown(() => home.delete(recursive: true));

  Future<Process> launch() => Process.start(
    'sh',
    ['-c', bootstrapScript(remoteHelperBuildId)],
    environment: {'HOME': home.path, 'PATH': '/usr/bin:/bin'},
  );

  Future<void> install() async {
    final directory = Directory(
      '${home.path}/$remoteInstallRoot/$remoteHelperBuildId',
    );
    await directory.create(recursive: true);
    await File(helperPath!).copy('${directory.path}/$remoteHelperExecutable');
    await Process.run('chmod', [
      '755',
      '${directory.path}/$remoteHelperExecutable',
    ]);
  }

  test('a missing helper reports the host platform', () async {
    final process = await launch();
    final channel = RemoteChannel.connect(
      process: IoRemoteProcess(process),
      config: _config,
    );
    await expectLater(
      channel,
      throwsA(
        isA<RemoteChannelException>()
            .having(
              (e) => e.kind,
              'kind',
              RemoteChannelFailureKind.bootstrapMarker,
            )
            .having((e) => e.marker!.words.first, 'word', 'missing')
            .having(
              (e) => helperTargetFromMarker(e.marker!.words[1]),
              'target',
              isNotNull,
            ),
      ),
    );
  });

  test('the installed helper says hello and shuts down on request', () async {
    await install();
    final process = await launch();
    final channel = await RemoteChannel.connect(
      process: IoRemoteProcess(process),
      config: _config,
    );
    final hello = parseHelloBody(
      channel.hello.body,
      buildId: channel.hello.buildId,
    );
    expect(hello.facts.helperBuildId, remoteHelperBuildId);
    expect(
      hello.capabilities.operatingSystem,
      isNot(HostOperatingSystem.unknown),
    );
    await expectLater(
      channel.call('process.nothing', const {}),
      throwsA(
        isA<RemoteCallException>().having(
          (e) => e.code,
          'code',
          'unsupportedCommand',
        ),
      ),
    );
    await channel.close();
    expect(await channel.closed, isNull);
    expect(await process.exitCode, 0);
  });
}
