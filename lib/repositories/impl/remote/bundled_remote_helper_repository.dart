import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../../models/models.dart';
import '../../remote_helper_artifact_repository.dart';
import 'wire/contract.g.dart';

const _descriptorKeys = {
  'schema',
  'target',
  'buildId',
  'compatibility',
  'size',
  'sha256',
  'glibcFloor',
  'minimumSystem',
};

/// Finds the helpers bundled with the application (§8.2):
///
/// - macOS: `Contents/Resources/remote-helper/<target>/`
/// - Linux: `lib/remote-helper/<target>/` next to the executable
/// - Windows: `remote-helper/<target>/` next to the executable
///
/// Debug and profile builds also look in `PROCESSLAMA_REMOTE_HELPER_DIR` and
/// the checkout's `build/remote-helper-dev/` and `build/remote-helper/`.
class BundledRemoteHelperRepository implements RemoteHelperArtifactRepository {
  BundledRemoteHelperRepository({
    String? resolvedExecutable,
    String? operatingSystem,
    Map<String, String>? environment,
    String? currentDirectory,
    this._releaseBuild = kReleaseMode,
  }) : _resolvedExecutable = resolvedExecutable ?? Platform.resolvedExecutable,
       _operatingSystem = operatingSystem ?? Platform.operatingSystem,
       _environment = environment ?? Platform.environment,
       _currentDirectory = currentDirectory ?? Directory.current.path;

  final String _resolvedExecutable;
  final String _operatingSystem;
  final Map<String, String> _environment;
  final String _currentDirectory;
  final bool _releaseBuild;

  /// Directories holding `<target>/` helper folders, in lookup order.
  List<String> get searchRoots {
    final executableDirectory = File(_resolvedExecutable).parent.path;
    final bundled = switch (_operatingSystem) {
      'macos' =>
        '${Directory(executableDirectory).parent.path}/Resources/remote-helper',
      'windows' => '$executableDirectory${Platform.pathSeparator}remote-helper',
      _ => '$executableDirectory/lib/remote-helper',
    };
    return [
      bundled,
      if (!_releaseBuild) ...[
        if (_environment['PROCESSLAMA_REMOTE_HELPER_DIR'] case final String dir
            when dir.isNotEmpty)
          dir,
        '$_currentDirectory/build/remote-helper-dev',
        '$_currentDirectory/build/remote-helper',
      ],
    ];
  }

  @override
  Future<RemoteHelperArtifact?> bundledHelper(RemoteHelperTarget target) async {
    for (final root in searchRoots) {
      final artifact = await _artifactIn('$root/${target.wireName}', target);
      if (artifact != null) {
        return artifact;
      }
    }
    return null;
  }

  Future<RemoteHelperArtifact?> _artifactIn(
    String directory,
    RemoteHelperTarget target,
  ) async {
    final binary = File('$directory/$remoteHelperExecutable');
    final descriptorFile = File('$directory/$remoteHelperExecutable.json');
    if (!await binary.exists() || !await descriptorFile.exists()) {
      return null;
    }
    final Object? descriptor;
    try {
      descriptor = jsonDecode(await descriptorFile.readAsString());
    } on FormatException {
      return null;
    }
    if (descriptor is! Map<String, Object?> ||
        descriptor.length != _descriptorKeys.length ||
        !_descriptorKeys.every(descriptor.containsKey) ||
        descriptor['schema'] != 1 ||
        descriptor['target'] != target.wireName ||
        descriptor['buildId'] != remoteHelperBuildId) {
      return null;
    }
    final size = descriptor['size'];
    final digest = descriptor['sha256'];
    if (size is! int ||
        size <= 0 ||
        size > RemoteWireLimits.helperBytes ||
        digest is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        await binary.length() != size) {
      return null;
    }
    Future<Uint8List> read() async {
      final bytes = await binary.readAsBytes();
      if (bytes.length != size || sha256.convert(bytes).toString() != digest) {
        throw const RemoteHostException(RemoteFailureCode.helperDamaged);
      }
      return bytes;
    }

    // Validate now so a damaged bundle is reported before any install.
    try {
      await read();
    } on RemoteHostException {
      return null;
    }
    return RemoteHelperArtifact(
      target: target,
      buildId: remoteHelperBuildId,
      size: size,
      sha256: digest,
      read: read,
    );
  }
}
