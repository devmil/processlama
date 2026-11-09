import 'process_snapshot.dart';

/// The remote host a snapshot was taken on.
class SnapshotHost {
  const SnapshotHost({
    required this.displayName,
    required this.alias,
    required this.operatingSystem,
    required this.architecture,
  });

  final String displayName;
  final String alias;
  final String operatingSystem;
  final String architecture;

  Map<String, Object?> toJson() => {
    'display_name': displayName,
    'alias': alias,
    'os': operatingSystem,
    'arch': architecture,
  };

  static SnapshotHost? fromJson(Object? value) {
    if (value is! Map) return null;
    String text(String key) => value[key] is String ? value[key] as String : '';
    return SnapshotHost(
      displayName: text('display_name'),
      alias: text('alias'),
      operatingSystem: text('os'),
      architecture: text('arch'),
    );
  }
}

class SnapshotDocument {
  const SnapshotDocument({
    required this.schemaVersion,
    required this.exportedAtUnixMs,
    required this.source,
    required this.snapshot,
    this.displayName,
    this.host,
    this.icons = const {},
  });

  /// Version 2 adds the remote [host] and embedded [icons]; both are optional
  /// and older readers ignore them.
  static const currentSchemaVersion = 2;

  factory SnapshotDocument.fromJson(Map<String, Object?> json) {
    return SnapshotDocument(
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      exportedAtUnixMs:
          (json['exported_at_unix_ms'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      source: json['source'] as String? ?? 'ProcessLama',
      displayName: json['display_name'] as String?,
      host: SnapshotHost.fromJson(json['host']),
      icons: switch (json['icons']) {
        final Map<String, Object?> icons => {
          for (final MapEntry(:key, :value) in icons.entries)
            if (value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(key))
              key: value,
        },
        _ => const {},
      },
      snapshot: ProcessSnapshot.fromJson(
        json['snapshot'] as Map<String, Object?>? ?? const <String, Object?>{},
      ),
    );
  }

  final int schemaVersion;
  final int exportedAtUnixMs;
  final String source;
  final ProcessSnapshot snapshot;
  final String? displayName;
  final SnapshotHost? host;

  /// Base64 PNG icons by SHA-256, for remote snapshots.
  final Map<String, String> icons;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema_version': schemaVersion,
      'exported_at_unix_ms': exportedAtUnixMs,
      'source': source,
      'display_name': ?displayName,
      if (host != null) 'host': host!.toJson(),
      if (icons.isNotEmpty) 'icons': icons,
      'snapshot': snapshot.toJson(),
    };
  }

  SnapshotDocument copyWith({String? displayName}) {
    return SnapshotDocument(
      schemaVersion: schemaVersion,
      exportedAtUnixMs: exportedAtUnixMs,
      source: source,
      displayName: displayName,
      host: host,
      icons: icons,
      snapshot: snapshot,
    );
  }
}
