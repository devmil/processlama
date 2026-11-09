import '../../../models/models.dart';
import 'wire/contract.g.dart';

/// Fixed POSIX scripts run on a remote host through `ssh`. Their only
/// variable parts are validated build IDs and digests; no alias, path or
/// other user input is ever part of a script.

final _buildIdPattern = RegExp(r'^[0-9a-f]{40}$');
final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

bool isValidHelperBuildId(String value) => _buildIdPattern.hasMatch(value);

String _checkedBuildId(String buildId) {
  if (!isValidHelperBuildId(buildId)) {
    throw ArgumentError.value('<redacted>', 'buildId', 'not a build ID');
  }
  return buildId;
}

/// `case` arms mapping `uname -s`/`uname -m` to a helper target; anything
/// else, including a 32-bit userland, is unsupported.
String _targetCase(String unsupported) {
  final arms = StringBuffer();
  for (final target in RemoteHelperTarget.values) {
    final unames = {
      target.uname,
      if (target == RemoteHelperTarget.linuxArm64) 'Linux/arm64',
    };
    arms.write('${unames.join('|')}) t=${target.os}/${target.arch};; ');
  }
  return 'case "\$(uname -s)/\$(uname -m)" in $arms*) $unsupported;; esac; '
      '[ "\$(getconf LONG_BIT 2>/dev/null)" = 64 ] || { $unsupported; }';
}

/// The launch script (§6.2). It prints `PROCESSLAMA-BOOTSTRAP 1 start` and
/// `exec`s the installed helper of [buildId], or prints
/// `PROCESSLAMA-BOOTSTRAP 1 missing <os>/<arch>` or `... 1 unsupported`.
/// Text a login script printed before is discarded by the client.
String bootstrapScript(String buildId) {
  final build = _checkedBuildId(buildId);
  const prefix = remoteBootstrapPrefix;
  const unsupported = "printf '$prefix 1 unsupported\\n'; exit 0";
  return [
    _targetCase(unsupported),
    'case "\$t" in macos/*) PATH="/usr/bin:/bin:/usr/sbin:/sbin:\$PATH"; export PATH;; esac',
    'h="\$HOME/$remoteInstallRoot/$build/$remoteHelperExecutable"',
    'if [ -f "\$h" ] && [ -x "\$h" ] && [ ! -L "\$h" ]; then '
        "printf '$prefix 1 start\\n'; exec \"\$h\" --stdio; fi",
    "printf '$prefix 1 missing %s\\n' \"\$t\"",
    'exit 0',
  ].join('; ');
}

/// The helper target named by a `missing <os>/<arch>` marker word.
RemoteHelperTarget? helperTargetFromMarker(String word) {
  for (final target in RemoteHelperTarget.values) {
    if ('${target.os}/${target.arch}' == word) return target;
  }
  return null;
}

bool isValidSha256(String value) => _sha256Pattern.hasMatch(value);

const _installRoot = '\$HOME/.local/lib/processlama';

/// The install script (§8.3). The helper bytes arrive on standard input; the
/// script checks them, makes sure they run and report [buildId], and moves
/// them into place. Prints `PROCESSLAMA-INSTALL 1 <result>` with a result of
/// `ok`, `damaged`, `noSpace`, `noexec` or `refused`.
String installScript({
  required String buildId,
  required String sha256,
  required int size,
}) {
  final build = _checkedBuildId(buildId);
  if (!isValidSha256(sha256)) {
    throw ArgumentError.value('<redacted>', 'sha256', 'not a digest');
  }
  if (size <= 0 || size > RemoteWireLimits.helperBytes) {
    throw ArgumentError.value(size, 'size', 'out of range');
  }
  String result(String word) =>
      "{ printf '$remoteInstallPrefix 1 $word\\n'; exit 0; }";
  return [
    'umask 077',
    'r="$_installRoot"',
    'd="\$r/remote/$build"',
    'h="\$d/$remoteHelperExecutable"',
    'for p in "\$HOME/.local" "\$HOME/.local/lib" "\$r" "\$r/remote" "\$d" "\$h"; do '
        '[ ! -L "\$p" ] || ${result('refused')}; done',
    'mkdir -p "\$d" 2>/dev/null || ${result('refused')}',
    'chmod 700 "\$r" "\$r/remote" "\$d" || ${result('refused')}',
    '{ command -v sha256sum || command -v shasum; } >/dev/null 2>&1 || '
        '${result('refused')}',
    't="\$d/.$remoteHelperExecutable.\$\$"',
    "trap 'rm -f \"\$t\"' EXIT",
    'head -c ${size + 1} > "\$t" 2>/dev/null || ${result('noSpace')}',
    '[ "\$(wc -c < "\$t" | tr -d " ")" = $size ] || ${result('damaged')}',
    'if command -v sha256sum >/dev/null 2>&1; then '
        'v="\$(sha256sum < "\$t" | cut -c1-64)"; '
        'else v="\$(shasum -a 256 < "\$t" | cut -c1-64)"; fi',
    '[ "\$v" = $sha256 ] || ${result('damaged')}',
    'chmod 755 "\$t" || ${result('refused')}',
    'o="\$("\$t" --version 2>/dev/null)"; c=\$?',
    '[ \$c -ne 126 ] || ${result('noexec')}',
    'case "\$o" in *\'"buildId":"$build"\'*) ;; *) ${result('damaged')};; esac',
    'mv -f "\$t" "\$h" 2>/dev/null || ${result('noSpace')}',
    "printf '$remoteInstallPrefix 1 ok\\n'",
  ].join('; ');
}

/// Removes helper builds unused for 30 days (§8.4): never [keepBuildId] and
/// never a build whose helper is still running (`.running.<pid>` of a live
/// process). Prints `PROCESSLAMA-INSTALL 1 ok`.
String pruneScript({required String keepBuildId}) {
  final keep = _checkedBuildId(keepBuildId);
  return [
    'r="$_installRoot/remote"',
    "{ [ -d \"\$r\" ] && [ ! -L \"\$r\" ]; } || { printf '$remoteInstallPrefix 1 ok\\n'; exit 0; }",
    'find "\$r" -mindepth 1 -maxdepth 1 -type d -mtime +30 | while IFS= read -r d; do '
        'b="\${d##*/}"; '
        'case "\$b" in $keep) continue;; *[!0-9a-f]*|"") continue;; esac; '
        '[ \${#b} -eq 40 ] || continue; '
        'busy=0; for f in "\$d"/.running.*; do [ -e "\$f" ] || continue; '
        'p="\${f##*.}"; case "\$p" in *[!0-9]*|"") continue;; esac; '
        'kill -0 "\$p" 2>/dev/null && busy=1; done; '
        '[ \$busy = 1 ] || rm -rf -- "\$d"; done',
    "printf '$remoteInstallPrefix 1 ok\\n'",
  ].join('; ');
}

/// Removes every installed helper and the helper's caches (§8.4). The helper
/// of [buildId] runs `--remove-state` first when it is installed. Prints
/// `PROCESSLAMA-INSTALL 1 ok`, or `refused` when a path is a symbolic link.
String uninstallScript({required String buildId}) {
  final build = _checkedBuildId(buildId);
  final cache = '\$HOME/$remoteCacheRoot';
  return [
    'r="$_installRoot"',
    'h="\$r/remote/$build/$remoteHelperExecutable"',
    "for p in \"\$r\" \"\$r/remote\" \"$cache\"; do [ ! -L \"\$p\" ] || { printf '$remoteInstallPrefix 1 refused\\n'; exit 0; }; done",
    '[ ! -x "\$h" ] || "\$h" --remove-state >/dev/null 2>&1 || true',
    'rm -rf -- "\$r/remote" "$cache"',
    'rmdir "\$r" 2>/dev/null || true',
    "printf '$remoteInstallPrefix 1 ok\\n'",
  ].join('; ');
}
