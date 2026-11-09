import 'dart:typed_data';

import '../models/models.dart';

/// A helper this application bundles, verified against its descriptor.
final class RemoteHelperArtifact {
  const RemoteHelperArtifact({
    required this.target,
    required this.buildId,
    required this.size,
    required this.sha256,
    required this.read,
  });

  final RemoteHelperTarget target;
  final String buildId;
  final int size;

  /// Lowercase hexadecimal SHA-256 of the helper bytes.
  final String sha256;

  /// Reads the bytes again and checks them against [size] and [sha256].
  final Future<Uint8List> Function() read;
}

/// Finds the helpers bundled with this application. Owned by the remote host
/// service.
abstract interface class RemoteHelperArtifactRepository {
  /// The verified helper for [target], or null when this build carries none
  /// or its descriptor does not match.
  Future<RemoteHelperArtifact?> bundledHelper(RemoteHelperTarget target);
}
