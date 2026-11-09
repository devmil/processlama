import 'package:flutter/foundation.dart';

/// Where a process icon comes from. Local icons are files the native core
/// rendered; remote icons are content hashes a remote helper serves once and
/// the client caches.
@immutable
sealed class ProcessIconRef {
  const ProcessIconRef();

  const factory ProcessIconRef.file(String uri) = ProcessFileIcon;
  const factory ProcessIconRef.remote(String sha256) = ProcessRemoteIcon;
}

final class ProcessFileIcon extends ProcessIconRef {
  const ProcessFileIcon(this.uri);

  /// A `file://` URI or a plain path.
  final String uri;

  @override
  bool operator ==(Object other) =>
      other is ProcessFileIcon && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}

final class ProcessRemoteIcon extends ProcessIconRef {
  const ProcessRemoteIcon(this.sha256);

  /// Lowercase hexadecimal SHA-256 of the normalized PNG.
  final String sha256;

  @override
  bool operator ==(Object other) =>
      other is ProcessRemoteIcon && other.sha256 == sha256;

  @override
  int get hashCode => sha256.hashCode;
}
