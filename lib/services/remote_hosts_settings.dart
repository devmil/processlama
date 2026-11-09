import 'package:flutter/foundation.dart';

import '../models/models.dart';

/// A remote hosts change could not be saved; the change was undone.
final class RemoteHostsSaveFailure implements Exception {
  const RemoteHostsSaveFailure(this.section);

  /// The section that was restored: `profile`, `tabs` or `options`.
  final String section;

  @override
  String toString() => 'RemoteHostsSaveFailure($section)';
}

/// A profile change was rejected before it was saved.
enum RemoteHostProfileRejection {
  invalidAlias,
  invalidDisplayName,
  tooManyProfiles,
  unknownProfile,
  duplicateId,
}

final class RemoteHostProfileRejected implements Exception {
  const RemoteHostProfileRejected(this.reason);

  final RemoteHostProfileRejection reason;

  @override
  String toString() => 'RemoteHostProfileRejected(${reason.name})';
}

/// The settings service's remote hosts section: profiles, open tabs and
/// options, stored as one versioned value. Every write is a scoped intent; a
/// rejected save restores only the section it changed and throws
/// [RemoteHostsSaveFailure].
abstract interface class RemoteHostsSettings {
  ValueListenable<RemoteHostsState> get remoteHosts;

  Future<void> addRemoteHostProfile(RemoteHostProfile profile);

  /// Replaces the user-editable fields of an existing profile; the stored
  /// facts are kept.
  Future<void> updateRemoteHostProfile(RemoteHostProfile profile);

  /// Removes a profile and its tab.
  Future<void> removeRemoteHostProfile(String id);

  /// Records what a helper reported about a profile's host.
  Future<void> updateRemoteHostFacts(String id, RemoteHostFacts facts);

  /// Replaces the open remote tabs and the active tab.
  Future<void> updateRemoteTabs(List<String> openTabs, String? activeTab);

  Future<void> updateRemoteIconCacheBytes(int bytes);

  Future<void> updateDefaultBackgroundRefresh(BackgroundRefreshMode mode);
}
