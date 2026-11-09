import 'dart:io';

import 'package:devmil_remote/devmil_remote.dart';
import 'package:test/test.dart';

void main() {
  group('posixShellCommand', () {
    test('runs the script under sh with its quotes intact', () async {
      const script =
          "printf '%s|%s\\n' \"it's\" \"\$0\"; "
          'for f in /nonexistent/.running.*; do echo "\$f"; done';
      final result = await Process.run('sh', ['-c', posixShellCommand(script)]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, "it's|/bin/sh\n/nonexistent/.running.*\n");
    });

    test('is one exec of /bin/sh with a single-quoted script', () {
      final command = posixShellCommand("echo 'a'");
      expect(command, "exec /bin/sh -c 'echo '\\''a'\\'''");
    });
  });

  group('sshArguments', () {
    test('passes the alias and command as single arguments after --', () {
      final arguments = sshArguments(
        alias: 'build-box',
        remoteCommand: 'exec "\$HOME/helper" --stdio',
      );
      final separator = arguments.indexOf('--');
      expect(arguments.sublist(separator), [
        '--',
        'build-box',
        'exec "\$HOME/helper" --stdio',
      ]);
      expect(arguments.sublist(0, separator), sshFixedArguments);
    });

    test('keeps the fixed security options', () {
      String option(String name) => sshFixedArguments
          .where((argument) => argument.startsWith('$name='))
          .single;
      expect(option('BatchMode'), 'BatchMode=yes');
      expect(option('StrictHostKeyChecking'), 'StrictHostKeyChecking=yes');
      expect(option('ForwardAgent'), 'ForwardAgent=no');
      expect(option('ForwardX11'), 'ForwardX11=no');
      expect(option('ClearAllForwardings'), 'ClearAllForwardings=yes');
      expect(option('ControlMaster'), 'ControlMaster=no');
      expect(option('ControlPath'), 'ControlPath=none');
      expect(option('ConnectTimeout'), 'ConnectTimeout=10');
      expect(option('ServerAliveInterval'), 'ServerAliveInterval=15');
      expect(option('PermitLocalCommand'), 'PermitLocalCommand=no');
    });

    test('puts a config file first and only when given', () {
      expect(
        sshArguments(
          alias: 'a',
          remoteCommand: 'true',
          configFile: '/x/c',
        ).take(3),
        ['-F', '/x/c', '-T'],
      );
      expect(
        sshArguments(alias: 'a', remoteCommand: 'true'),
        isNot(contains('-F')),
      );
    });

    test('accepts plain host aliases only', () {
      for (final alias in [
        'a',
        'build-box',
        'mac.mini_2',
        '10.0.0.1',
        'A${'b' * 127}',
      ]) {
        expect(isValidSshAlias(alias), isTrue, reason: alias);
      }
      for (final alias in [
        '',
        '-oProxyCommand=x',
        'user@host',
        'host:22',
        'host name',
        '.hidden',
        'a;b',
        r'$(id)',
        'host\n',
        'A${'b' * 128}',
      ]) {
        expect(isValidSshAlias(alias), isFalse, reason: alias);
        expect(
          () => sshArguments(alias: alias, remoteCommand: 'true'),
          throwsA(isA<InvalidSshAlias>()),
        );
      }
    });
  });

  group('OpenSSH version', () {
    test('parses and gates the minimum version', () {
      expect(
        isSupportedOpenSsh('OpenSSH_8.9p1 Ubuntu-3, OpenSSL 3.0.2'),
        isTrue,
      );
      expect(isSupportedOpenSsh('OpenSSH_10.2p1, OpenSSL 3.5.8'), isTrue);
      expect(isSupportedOpenSsh('OpenSSH_for_Windows_9.5p1'), isTrue);
      expect(isSupportedOpenSsh('OpenSSH_8.8p1'), isFalse);
      expect(isSupportedOpenSsh('Dropbear'), isFalse);
    });
  });

  group('resolveSshExecutable', () {
    test('never uses the current or relative PATH entries', () {
      final resolved = resolveSshExecutable(
        windows: false,
        environment: {'PATH': '.:bin:/work:/opt/ssh/bin'},
        currentDirectory: '/work',
        isFile: (path) => path != '/usr/bin/ssh',
      );
      expect(resolved, '/opt/ssh/bin/ssh');
    });

    test('prefers /usr/bin/ssh', () {
      final resolved = resolveSshExecutable(
        windows: false,
        environment: {'PATH': '/opt/ssh/bin'},
        currentDirectory: '/',
        isFile: (_) => true,
      );
      expect(resolved, '/usr/bin/ssh');
    });

    test('uses the Windows system copy first', () {
      final resolved = resolveSshExecutable(
        windows: true,
        environment: {'SystemRoot': r'C:\Windows', 'Path': r'C:\tools'},
        currentDirectory: r'C:\tools',
        isFile: (_) => true,
      );
      expect(resolved, r'C:\Windows\System32\OpenSSH\ssh.exe');
    });
  });
}
