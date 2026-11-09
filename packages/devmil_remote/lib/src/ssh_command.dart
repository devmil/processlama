// Adapted from GitLama's remote workspaces
// (gitlama/lib/repositories/impl/remote/ssh_command.dart).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The oldest supported OpenSSH client (8.9 adds `SessionType` and
/// `ForkAfterAuthentication` handling the fixed options rely on).
const minimumOpenSshMajor = 8;
const minimumOpenSshMinor = 9;

/// Bound for the `ssh -V` probe.
const sshVersionProbeTimeout = Duration(seconds: 5);

/// Bytes of `ssh -V` stderr considered; the rest is discarded.
const sshVersionProbeBytes = 4096;

/// The fixed SSH options of every remote command, in order. Authentication,
/// host keys, users, ports and jump hosts come from the user's
/// `~/.ssh/config` and agent; nothing here prompts.
const sshFixedArguments = <String>[
  '-T',
  '-o',
  'RequestTTY=no',
  '-o',
  'StdinNull=no',
  '-o',
  'BatchMode=yes',
  '-o',
  'StrictHostKeyChecking=yes',
  '-o',
  'ForwardAgent=no',
  '-o',
  'ForwardX11=no',
  '-o',
  'ClearAllForwardings=yes',
  '-o',
  'GSSAPIDelegateCredentials=no',
  '-o',
  'ControlMaster=no',
  '-o',
  'ControlPath=none',
  '-o',
  'ForkAfterAuthentication=no',
  '-o',
  'RemoteCommand=none',
  '-o',
  'SessionType=default',
  '-o',
  'PermitLocalCommand=no',
  '-o',
  'ConnectTimeout=10',
  '-o',
  'ConnectionAttempts=1',
  '-o',
  'ServerAliveInterval=15',
  '-o',
  'ServerAliveCountMax=3',
];

/// An OpenSSH `Host` alias: a letter or digit followed by up to 127 letters,
/// digits, dots, underscores or hyphens. Anything else (options, user@host,
/// ports, spaces) is rejected before it reaches `ssh`.
final _aliasPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');

bool isValidSshAlias(String alias) => _aliasPattern.hasMatch(alias);

/// An alias was not a plain OpenSSH `Host` alias.
final class InvalidSshAlias implements Exception {
  const InvalidSshAlias();

  @override
  String toString() => 'InvalidSshAlias';
}

/// [script] as a remote command that POSIX `sh` runs, whatever the account's
/// login shell is.
///
/// sshd hands a remote command to the account's login shell. zsh (the macOS
/// default) aborts a command on a glob without matches, and fish or csh parse
/// differently again, so a script written for `sh` must not depend on the
/// login shell. The wrapper is plain words and one single-quoted argument,
/// which sh, bash and zsh read alike.
String posixShellCommand(String script) =>
    "exec /bin/sh -c '${script.replaceAll("'", r"'\''")}'";

/// The complete `ssh` argument array that runs [remoteCommand] on [alias].
///
/// [remoteCommand] must be a fixed script built by the caller from
/// validated parts only. [configFile] replaces the user's SSH configuration
/// with an isolated one; only test harnesses pass it.
List<String> sshArguments({
  required String alias,
  required String remoteCommand,
  String? configFile,
}) {
  if (!isValidSshAlias(alias)) {
    throw const InvalidSshAlias();
  }
  return [
    if (configFile != null) ...['-F', configFile],
    ...sshFixedArguments,
    '--',
    alias,
    remoteCommand,
  ];
}

final _openSshVersion = RegExp(
  r'OpenSSH_(?:for_Windows_)?(\d{1,4})\.(\d{1,4})',
);

/// Parses `OpenSSH_<major>.<minor>` from `ssh -V` output.
({int major, int minor})? parseOpenSshVersion(String text) {
  final match = _openSshVersion.firstMatch(text);
  if (match == null) return null;
  return (major: int.parse(match.group(1)!), minor: int.parse(match.group(2)!));
}

/// Whether `ssh -V` output names a supported OpenSSH client.
bool isSupportedOpenSsh(String text) {
  final version = parseOpenSshVersion(text);
  if (version == null) return false;
  return version.major > minimumOpenSshMajor ||
      (version.major == minimumOpenSshMajor &&
          version.minor >= minimumOpenSshMinor);
}

/// Finds the installed OpenSSH client. Never searches the current directory
/// or relative `PATH` entries.
String? resolveSshExecutable({
  required bool windows,
  required Map<String, String> environment,
  required String currentDirectory,
  required bool Function(String path) isFile,
}) {
  final candidates = <String>[];
  if (windows) {
    final systemRoot = environment['SystemRoot'] ?? environment['SYSTEMROOT'];
    if (systemRoot != null && _isWindowsAbsolute(systemRoot)) {
      candidates.add('${_trimWindows(systemRoot)}\\System32\\OpenSSH\\ssh.exe');
    }
    final current = _trimWindows(currentDirectory).toLowerCase();
    for (final entry
        in (environment['Path'] ?? environment['PATH'] ?? '').split(';')) {
      if (!_isWindowsAbsolute(entry) || entry.contains('"')) continue;
      final directory = _trimWindows(entry);
      if (directory.toLowerCase() == current) continue;
      candidates.add('$directory\\ssh.exe');
    }
  } else {
    candidates.add('/usr/bin/ssh');
    final current = _trimPosix(currentDirectory);
    for (final entry in (environment['PATH'] ?? '').split(':')) {
      if (!entry.startsWith('/')) continue;
      final directory = _trimPosix(entry);
      if (directory == current) continue;
      candidates.add(directory == '/' ? '/ssh' : '$directory/ssh');
    }
  }
  for (final candidate in candidates) {
    if (isFile(candidate)) return candidate;
  }
  return null;
}

bool _isWindowsAbsolute(String path) => RegExp(r'^[A-Za-z]:\\').hasMatch(path);

String _trimWindows(String path) {
  var result = path;
  while (result.endsWith('\\')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

String _trimPosix(String path) {
  var result = path;
  while (result.length > 1 && result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

/// Reads `ssh -V` output (bounded) or null when the probe failed.
typedef SshVersionReader = Future<String?> Function(String executable);

/// Runs `<executable> -V` without a shell, keeps the first
/// [sshVersionProbeBytes] bytes of stderr and kills the probe after
/// [sshVersionProbeTimeout]. The text is only parsed for a version.
Future<String?> readSshVersion(String executable) async {
  final Process process;
  try {
    process = await Process.start(executable, const ['-V'], runInShell: false);
  } on ProcessException {
    return null;
  }
  unawaited(process.stdin.close().catchError((Object _) {}));
  final bytes = <int>[];
  final stdoutDone = process.stdout.drain<void>().catchError((Object _) {});
  final stderrDone = process.stderr
      .listen((chunk) {
        final room = sshVersionProbeBytes - bytes.length;
        if (room > 0) bytes.addAll(chunk.take(room));
      })
      .asFuture<void>()
      .catchError((Object _) {});
  try {
    await Future.wait([
      process.exitCode,
      stdoutDone,
      stderrDone,
    ]).timeout(sshVersionProbeTimeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    return null;
  }
  return latin1.decode(bytes);
}
