import 'package:flutter/foundation.dart';

/// One tab of the main window: the permanent local tab or a remote host.
@immutable
sealed class WorkspaceTab {
  const WorkspaceTab();

  static const local = LocalWorkspaceTab();

  /// A stable key for persistence and widget identity.
  String get key;
}

final class LocalWorkspaceTab extends WorkspaceTab {
  const LocalWorkspaceTab();

  @override
  String get key => 'local';

  @override
  bool operator ==(Object other) => other is LocalWorkspaceTab;

  @override
  int get hashCode => 0;
}

final class RemoteWorkspaceTab extends WorkspaceTab {
  const RemoteWorkspaceTab(this.profileId);

  /// The `RemoteHostProfile.id` this tab shows.
  final String profileId;

  @override
  String get key => 'remote:$profileId';

  @override
  bool operator ==(Object other) =>
      other is RemoteWorkspaceTab && other.profileId == profileId;

  @override
  int get hashCode => profileId.hashCode;
}
