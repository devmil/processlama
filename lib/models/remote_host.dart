import 'package:flutter/foundation.dart';

import 'host_capabilities.dart';
import 'remote_contract.g.dart';

/// How a hidden remote tab refreshes.
enum BackgroundRefreshMode {
  /// Every 5 seconds.
  slow,

  /// At the live polling interval.
  live,

  /// Heartbeats only.
  paused,
}

/// What a helper reported about its host. Display only; never an authority.
@immutable
class RemoteHostFacts {
  const RemoteHostFacts({
    required this.target,
    required this.kernel,
    required this.hostInstanceId,
    required this.hostnameHash,
    required this.helperBuildId,
    required this.compatibility,
    required this.processtreeRevision,
    required this.uid,
  });

  final RemoteHelperTarget target;
  final String kernel;
  final String hostInstanceId;
  final String hostnameHash;
  final String helperBuildId;
  final int compatibility;
  final String processtreeRevision;
  final int uid;

  HostOperatingSystem get operatingSystem => switch (target.os) {
    'linux' => HostOperatingSystem.linux,
    'macos' => HostOperatingSystem.macos,
    _ => HostOperatingSystem.unknown,
  };

  Map<String, Object?> toJson() => {
    'target': target.wireName,
    'kernel': kernel,
    'hostInstanceId': hostInstanceId,
    'hostnameHash': hostnameHash,
    'helperBuildId': helperBuildId,
    'compatibility': compatibility,
    'processtreeRevision': processtreeRevision,
    'uid': uid,
  };

  /// Reads stored facts; returns null for anything malformed.
  static RemoteHostFacts? fromJson(Object? value) {
    if (value is! Map) return null;
    final target = RemoteHelperTarget.fromWire('${value['target']}');
    final kernel = value['kernel'];
    final instance = value['hostInstanceId'];
    final hostname = value['hostnameHash'];
    final build = value['helperBuildId'];
    final compatibility = value['compatibility'];
    final revision = value['processtreeRevision'];
    final uid = value['uid'];
    if (target == null ||
        kernel is! String ||
        instance is! String ||
        hostname is! String ||
        build is! String ||
        compatibility is! int ||
        revision is! String ||
        uid is! int) {
      return null;
    }
    return RemoteHostFacts(
      target: target,
      kernel: kernel,
      hostInstanceId: instance,
      hostnameHash: hostname,
      helperBuildId: build,
      compatibility: compatibility,
      processtreeRevision: revision,
      uid: uid,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RemoteHostFacts &&
      other.target == target &&
      other.kernel == kernel &&
      other.hostInstanceId == hostInstanceId &&
      other.hostnameHash == hostnameHash &&
      other.helperBuildId == helperBuildId &&
      other.compatibility == compatibility &&
      other.processtreeRevision == processtreeRevision &&
      other.uid == uid;

  @override
  int get hashCode => Object.hash(
    target,
    kernel,
    hostInstanceId,
    hostnameHash,
    helperBuildId,
    compatibility,
    processtreeRevision,
    uid,
  );
}

/// A helper's validated hello: what it is and what it can show.
@immutable
class RemoteHelperHello {
  const RemoteHelperHello({required this.facts, required this.capabilities});

  final RemoteHostFacts facts;
  final HostCapabilities capabilities;
}

/// The connection lifecycle of one remote host.
enum RemoteConnectionPhase {
  idle,
  probing,
  installing,
  handshaking,
  live,
  reconnecting,
  disconnected,
  failed,
}

/// Thrown by remote host operations with a typed code; carries no received
/// text.
final class RemoteHostException implements Exception {
  const RemoteHostException(this.code, {this.hostTarget});

  final RemoteFailureCode code;

  /// The host's platform when the helper is missing there.
  final RemoteHelperTarget? hostTarget;

  @override
  String toString() => 'RemoteHostException(${code.name})';
}

/// `^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`: a plain `~/.ssh/config` host alias.
final remoteHostAliasPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');

/// The longest alias [remoteHostAliasPattern] accepts.
const remoteHostAliasMaxLength = 128;

/// Profile display names are 1–64 characters.
const remoteHostDisplayNameMaxLength = 64;

/// The most profiles a client keeps.
const maximumRemoteHostProfiles = 64;

/// The default remote icon cache size.
const defaultRemoteIconCacheBytes = 64 * 1024 * 1024;

/// A configured remote host. Stores no user names, ports, keys or commands:
/// those belong in `~/.ssh/config`.
@immutable
class RemoteHostProfile {
  const RemoteHostProfile({
    required this.id,
    required this.displayName,
    required this.sshAlias,
    this.autoInstallHelper = false,
    this.autoReconnect = true,
    this.openOnStartup,
    this.backgroundRefresh,
    this.lastKnown,
    this.unknownFields = const {},
  });

  /// A UUID.
  final String id;
  final String displayName;
  final String sshAlias;
  final bool autoInstallHelper;
  final bool autoReconnect;

  /// Null follows whether the tab was open when the app quit.
  final bool? openOnStartup;

  /// Null uses the global default.
  final BackgroundRefreshMode? backgroundRefresh;

  /// What the helper last reported, for display only.
  final RemoteHostFacts? lastKnown;

  /// Fields a newer version stored; kept on save.
  final Map<String, Object?> unknownFields;

  static bool isValidAlias(String alias) =>
      remoteHostAliasPattern.hasMatch(alias);

  static bool isValidDisplayName(String name) {
    final trimmed = name.trim();
    return trimmed.isNotEmpty &&
        trimmed.length <= remoteHostDisplayNameMaxLength &&
        !trimmed.codeUnits.any((unit) => unit < 0x20);
  }

  RemoteHostProfile copyWith({
    String? displayName,
    String? sshAlias,
    bool? autoInstallHelper,
    bool? autoReconnect,
    bool? Function()? openOnStartup,
    BackgroundRefreshMode? Function()? backgroundRefresh,
    RemoteHostFacts? Function()? lastKnown,
  }) {
    return RemoteHostProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      sshAlias: sshAlias ?? this.sshAlias,
      autoInstallHelper: autoInstallHelper ?? this.autoInstallHelper,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      openOnStartup: openOnStartup == null
          ? this.openOnStartup
          : openOnStartup(),
      backgroundRefresh: backgroundRefresh == null
          ? this.backgroundRefresh
          : backgroundRefresh(),
      lastKnown: lastKnown == null ? this.lastKnown : lastKnown(),
      unknownFields: unknownFields,
    );
  }

  static const _knownKeys = {
    'id',
    'displayName',
    'sshAlias',
    'autoInstallHelper',
    'autoReconnect',
    'openOnStartup',
    'backgroundRefresh',
    'lastKnown',
  };

  Map<String, Object?> toJson() => {
    ...unknownFields,
    'id': id,
    'displayName': displayName,
    'sshAlias': sshAlias,
    'autoInstallHelper': autoInstallHelper,
    'autoReconnect': autoReconnect,
    'openOnStartup': openOnStartup,
    'backgroundRefresh': backgroundRefresh?.name,
    'lastKnown': lastKnown?.toJson(),
  };

  /// Reads a stored profile. Missing fields fall back to defaults; a profile
  /// without a valid id, alias or name is dropped (null).
  static RemoteHostProfile? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final alias = value['sshAlias'];
    if (id is! String || id.isEmpty || alias is! String) return null;
    if (!isValidAlias(alias)) return null;
    final name = value['displayName'];
    final displayName = name is String && isValidDisplayName(name)
        ? name.trim()
        : alias;
    final refresh = value['backgroundRefresh'];
    final openOnStartup = value['openOnStartup'];
    return RemoteHostProfile(
      id: id,
      displayName: displayName,
      sshAlias: alias,
      autoInstallHelper: value['autoInstallHelper'] == true,
      autoReconnect: value['autoReconnect'] != false,
      openOnStartup: openOnStartup is bool ? openOnStartup : null,
      backgroundRefresh: BackgroundRefreshMode.values
          .where((mode) => mode.name == refresh)
          .firstOrNull,
      lastKnown: RemoteHostFacts.fromJson(value['lastKnown']),
      unknownFields: {
        for (final MapEntry(:key, :value) in value.entries)
          if (key is String && !_knownKeys.contains(key)) key: value,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RemoteHostProfile &&
      other.id == id &&
      other.displayName == displayName &&
      other.sshAlias == sshAlias &&
      other.autoInstallHelper == autoInstallHelper &&
      other.autoReconnect == autoReconnect &&
      other.openOnStartup == openOnStartup &&
      other.backgroundRefresh == backgroundRefresh &&
      other.lastKnown == lastKnown &&
      mapEquals(other.unknownFields, unknownFields);

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    sshAlias,
    autoInstallHelper,
    autoReconnect,
    openOnStartup,
    backgroundRefresh,
    lastKnown,
  );
}

/// The stored remote hosts value (`remoteHosts.v1`): profiles, open tabs and
/// global options.
@immutable
class RemoteHostsState {
  const RemoteHostsState({
    this.profiles = const [],
    this.openTabs = const [],
    this.activeTab,
    this.iconCacheBytes = defaultRemoteIconCacheBytes,
    this.defaultBackgroundRefresh = BackgroundRefreshMode.slow,
    this.unknownFields = const {},
  });

  static const version = 1;

  final List<RemoteHostProfile> profiles;

  /// Profile ids of the open remote tabs, in display order.
  final List<String> openTabs;

  /// The active tab's key (`local` or `remote:<id>`), if any.
  final String? activeTab;
  final int iconCacheBytes;
  final BackgroundRefreshMode defaultBackgroundRefresh;
  final Map<String, Object?> unknownFields;

  RemoteHostProfile? profile(String id) =>
      profiles.where((profile) => profile.id == id).firstOrNull;

  RemoteHostsState copyWith({
    List<RemoteHostProfile>? profiles,
    List<String>? openTabs,
    String? Function()? activeTab,
    int? iconCacheBytes,
    BackgroundRefreshMode? defaultBackgroundRefresh,
  }) {
    return RemoteHostsState(
      profiles: profiles ?? this.profiles,
      openTabs: openTabs ?? this.openTabs,
      activeTab: activeTab == null ? this.activeTab : activeTab(),
      iconCacheBytes: iconCacheBytes ?? this.iconCacheBytes,
      defaultBackgroundRefresh:
          defaultBackgroundRefresh ?? this.defaultBackgroundRefresh,
      unknownFields: unknownFields,
    );
  }

  static const _knownKeys = {
    'version',
    'profiles',
    'openTabs',
    'activeTab',
    'iconCacheBytes',
    'defaultBackgroundRefresh',
  };

  Map<String, Object?> toJson() => {
    ...unknownFields,
    'version': version,
    'profiles': [for (final profile in profiles) profile.toJson()],
    'openTabs': openTabs,
    'activeTab': activeTab,
    'iconCacheBytes': iconCacheBytes,
    'defaultBackgroundRefresh': defaultBackgroundRefresh.name,
  };

  /// Reads the stored value, tolerating missing fields and dropping invalid
  /// profiles, duplicate ids and tabs of unknown profiles.
  static RemoteHostsState fromJson(Object? value) {
    if (value is! Map) return const RemoteHostsState();
    final profiles = <RemoteHostProfile>[];
    final ids = <String>{};
    final storedProfiles = value['profiles'];
    if (storedProfiles is List) {
      for (final stored in storedProfiles) {
        final profile = RemoteHostProfile.fromJson(stored);
        if (profile != null &&
            ids.add(profile.id) &&
            profiles.length < maximumRemoteHostProfiles) {
          profiles.add(profile);
        }
      }
    }
    final tabs = <String>[];
    final storedTabs = value['openTabs'];
    if (storedTabs is List) {
      for (final id in storedTabs) {
        if (id is String && ids.contains(id) && !tabs.contains(id)) {
          tabs.add(id);
        }
      }
    }
    final cache = value['iconCacheBytes'];
    final refresh = value['defaultBackgroundRefresh'];
    final active = value['activeTab'];
    return RemoteHostsState(
      profiles: List.unmodifiable(profiles),
      openTabs: List.unmodifiable(tabs),
      activeTab: active is String ? active : null,
      iconCacheBytes: cache is int && cache >= 1024 * 1024
          ? cache
          : defaultRemoteIconCacheBytes,
      defaultBackgroundRefresh:
          BackgroundRefreshMode.values
              .where((mode) => mode.name == refresh)
              .firstOrNull ??
          BackgroundRefreshMode.slow,
      unknownFields: {
        for (final MapEntry(:key, :value) in value.entries)
          if (key is String && !_knownKeys.contains(key)) key: value,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RemoteHostsState &&
      listEquals(other.profiles, profiles) &&
      listEquals(other.openTabs, openTabs) &&
      other.activeTab == activeTab &&
      other.iconCacheBytes == iconCacheBytes &&
      other.defaultBackgroundRefresh == defaultBackgroundRefresh &&
      mapEquals(other.unknownFields, unknownFields);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(profiles),
    Object.hashAll(openTabs),
    activeTab,
    iconCacheBytes,
    defaultBackgroundRefresh,
  );
}
