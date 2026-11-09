import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:devmil_remote/devmil_remote.dart';
import 'package:devmil_remote/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/repositories.dart';
import 'package:processlama/repositories/impl/remote/ssh_remote_connection_repository.dart';
import 'package:processlama/repositories/impl/remote/wire/contract.g.dart';

Map<String, Object?> _linuxHello() {
  final document =
      jsonDecode(
            File('fixtures/remote_contract_vectors.json').readAsStringSync(),
          )
          as Map<String, Object?>;
  return ((document['vectors']! as List)
              .cast<Map<String, Object?>>()
              .firstWhere((vector) => vector['name'] == 'linux hello')['value']!
          as Map)
      .cast<String, Object?>();
}

void main() {
  late List<(String, List<String>)> started;
  late FakeRemoteProcess process;

  SshRemoteConnectionRepository repository({
    String? version = 'OpenSSH_9.6p1',
    bool sshInstalled = true,
    Map<String, String> environment = const {'PATH': '/usr/bin'},
    String? configFile,
  }) {
    started = [];
    process = FakeRemoteProcess();
    return SshRemoteConnectionRepository(
      startProcess: (executable, arguments, {environment}) async {
        started.add((executable, arguments));
        return process;
      },
      readVersion: (_) async => version,
      environment: environment,
      windows: false,
      currentDirectory: '/work',
      isFile: (path) => sshInstalled && path == '/usr/bin/ssh',
      configFile: configFile,
      offload: (work) async => work(),
    );
  }

  Future<RemoteHostException> failure(Future<Object?> future) async {
    try {
      await future;
    } on RemoteHostException catch (error) {
      return error;
    }
    fail('expected a RemoteHostException');
  }

  test('a missing or old ssh client is typed', () async {
    expect(
      (await failure(repository(sshInstalled: false).connect('box'))).code,
      RemoteFailureCode.sshMissing,
    );
    expect(
      (await failure(repository(version: 'OpenSSH_8.2p1').connect('box'))).code,
      RemoteFailureCode.sshTooOld,
    );
  });

  test('the debug config seam is honored only outside release builds', () {
    const environment = {'PROCESSLAMA_SSH_CONFIG': '/tmp/fixture/ssh_config'};
    expect(
      sshConfigOverride(environment, releaseBuild: false),
      '/tmp/fixture/ssh_config',
    );
    expect(sshConfigOverride(environment, releaseBuild: true), isNull);
    expect(
      sshConfigOverride({
        'PROCESSLAMA_SSH_CONFIG': 'relative',
      }, releaseBuild: false),
      isNull,
    );
  });

  test('connect runs the launch script and validates the hello', () async {
    final remote = repository(configFile: '/tmp/fixture/ssh_config');
    final connecting = remote.connect('build-box');
    await settle();
    final (executable, arguments) = started.single;
    expect(executable, '/usr/bin/ssh');
    expect(arguments.take(2), ['-F', '/tmp/fixture/ssh_config']);
    expect(arguments.contains('BatchMode=yes'), isTrue);
    final separator = arguments.indexOf('--');
    expect(arguments[separator + 1], 'build-box');
    expect(arguments[separator + 2], contains(remoteHelperBuildId));
    expect(arguments, hasLength(separator + 3));

    FakeRemoteHelper(
      process: process,
      magic: remoteHelperMagic,
      buildId: remoteHelperBuildId,
      bootstrapPrefix: remoteBootstrapPrefix,
      body: _linuxHello(),
      preamble: 'Welcome!\n',
    ).start();
    final connection = await connecting;
    expect(connection.hello.facts.target, RemoteHelperTarget.linuxX8664);
    expect(connection.hello.capabilities.storageIo, isTrue);
    await connection.close();
    expect(await connection.closed, isNull);
  });

  test('launch outcomes map to typed failures', () async {
    Future<RemoteFailureCode> outcome(
      void Function(FakeRemoteProcess process) script, {
      String? buildId,
      Map<String, Object?>? body,
    }) async {
      final remote = repository();
      final connecting = remote.connect('box');
      await settle();
      if (buildId != null || body != null) {
        FakeRemoteHelper(
          process: process,
          magic: remoteHelperMagic,
          buildId: buildId ?? remoteHelperBuildId,
          bootstrapPrefix: remoteBootstrapPrefix,
          body: body ?? _linuxHello(),
        ).start();
      } else {
        script(process);
      }
      return (await failure(connecting)).code;
    }

    final missing = repository();
    final connecting = missing.connect('box');
    await settle();
    process.emit(utf8.encode('$remoteBootstrapPrefix 1 missing linux/arm64\n'));
    await process.exit(0);
    final error = await failure(connecting);
    expect(error.code, RemoteFailureCode.helperNotInstalled);
    expect(error.hostTarget, RemoteHelperTarget.linuxArm64);

    expect(
      await outcome((process) async {
        process.emit(utf8.encode('$remoteBootstrapPrefix 1 unsupported\n'));
        await process.exit(0);
      }),
      RemoteFailureCode.unsupportedPlatform,
    );
    expect(
      await outcome((process) => process.exit(255)),
      RemoteFailureCode.sshConnectionFailed,
    );
    expect(
      await outcome((process) async {
        process.emit(utf8.encode('$remoteBootstrapPrefix 1 start\n'));
        await process.exit(126);
      }),
      RemoteFailureCode.helperStartFailed,
    );
    expect(
      await outcome(
        (_) {},
        buildId: '0000000000000000000000000000000000009999',
      ),
      RemoteFailureCode.helperOutdated,
    );
    expect(
      await outcome((_) {}, body: {..._linuxHello(), 'extra': true}),
      RemoteFailureCode.protocolMismatch,
    );
  });

  test('install streams the helper and reads the last status line', () async {
    final remote = repository();
    final bytes = Uint8List.fromList(List.generate(64, (index) => index));
    final artifact = RemoteHelperArtifact(
      target: RemoteHelperTarget.linuxX8664,
      buildId: remoteHelperBuildId,
      size: bytes.length,
      sha256: 'b' * 64,
      read: () async => bytes,
    );
    final installing = remote.installHelper('box', artifact);
    await settle();
    expect(process.written, bytes);
    expect(process.stdinClosed, isTrue);
    expect(started.single.$2.last, contains('b' * 64));
    process.emit(utf8.encode('motd line\n$remoteInstallPrefix 1 noexec\n'));
    await process.exit(0);
    expect(await installing, RemoteInstallResult.noexec);

    final unreachable = repository().removeHelpers('box');
    await settle();
    await process.exit(255);
    expect(
      (await failure(unreachable)).code,
      RemoteFailureCode.sshConnectionFailed,
    );
  });

  test('a channel failure after open maps to a retryable code', () {
    expect(
      remoteHostExceptionFor(
        const RemoteChannelException(RemoteChannelFailureKind.heartbeatLost),
      ).code,
      RemoteFailureCode.heartbeatLost,
    );
    expect(
      remoteHostExceptionFor(
        const RemoteChannelException(RemoteChannelFailureKind.disconnected),
      ).code.retryable,
      isTrue,
    );
  });
}
