import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// Turns a row's icon reference into a local file path for display. Rows
/// never do I/O; a resolver answers from what it already has.
abstract interface class ProcessIconResolver {
  /// The local path or `file://` URI for [ref], or null when none is known.
  String? pathFor(ProcessIconRef? ref);

  /// Follows [ref] while its icon is still arriving; null when it cannot
  /// change.
  ValueListenable<String?>? updatesFor(ProcessIconRef? ref);
}

/// Local icons only: files the native core rendered.
final class FileIconResolver implements ProcessIconResolver {
  const FileIconResolver();

  @override
  String? pathFor(ProcessIconRef? ref) => switch (ref) {
    ProcessFileIcon(:final uri) => uri,
    _ => null,
  };

  @override
  ValueListenable<String?>? updatesFor(ProcessIconRef? ref) => null;
}
