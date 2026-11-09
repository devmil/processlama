import '../models/models.dart';
import 'process_session.dart';
import 'process_source.dart';

/// A tab's session together with the source it consumes.
final class ProcessSessionHandle {
  const ProcessSessionHandle({required this.session, required this.source});

  final ProcessSession session;
  final ProcessSource source;

  /// Disposes the session first, then its source. A remote source releases
  /// its connection lease when it is disposed.
  Future<void> dispose() async {
    await session.dispose();
    await source.dispose();
  }
}

/// Thrown when a tab cannot get a session, for example for a removed profile.
final class ProcessSessionUnavailable implements Exception {
  const ProcessSessionUnavailable(this.tab);

  final WorkspaceTab tab;

  @override
  String toString() => 'ProcessSessionUnavailable(${tab.key})';
}

/// Creates one session per tab.
abstract interface class ProcessSessionFactory {
  /// Creates an uninitialized session for [tab]. Throws
  /// [ProcessSessionUnavailable] when the tab cannot be shown.
  ProcessSessionHandle create(WorkspaceTab tab);
}

/// Supplies remote sources; the remote host service implements it.
abstract interface class RemoteProcessSourceProvider {
  /// A new source for [profileId], or null when the profile is unknown.
  ProcessSource? createSource(String profileId);

  /// The cadence a hidden tab of [profileId] samples at.
  ProcessCadence backgroundCadenceFor(String profileId);

  /// The host and embedded icons of a snapshot taken in [profileId]'s tab.
  Future<RemoteSnapshotContext?> snapshotContext(
    String profileId,
    ProcessSnapshot snapshot,
  );
}
