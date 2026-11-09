import 'dart:async';
import 'dart:math';

import 'package:devmil_remote/devmil_remote.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../remote_host_service.dart';
import '../process_icon_service.dart';
import '../process_session.dart';
import '../process_source.dart';
import '../remote_hosts_settings.dart';
import 'remote_process_source.dart';
import '../settings_service.dart';

/// Icon bytes one snapshot embeds; the bound of one `icons.fetch` (§7.6).
const _snapshotIconBytes = 4 * 1024 * 1024;

/// Builds the reconnect schedule of one connection loss.
typedef RemoteReconnectorFactory =
    RemoteReconnector Function({
      required Future<ReconnectResult> Function() attempt,
      required void Function() onExhausted,
    });

class RemoteHostServiceImpl implements RemoteHostService {
  RemoteHostServiceImpl({
    required this.connections,
    required this.artifacts,
    required this.remoteHostsSettings,
    this.settingsService,
    this.icons,
    RemoteReconnectorFactory? reconnectorFactory,
    DateTime Function()? clock,
    Random? random,
  }) : _reconnectorFactory = reconnectorFactory ?? _defaultReconnector,
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  static final _log = Logger('RemoteHostService');

  final RemoteConnectionRepository connections;
  final RemoteHelperArtifactRepository artifacts;
  final RemoteHostsSettings remoteHostsSettings;
  final SettingsService? settingsService;
  final ProcessIconService? icons;
  final RemoteReconnectorFactory _reconnectorFactory;
  final DateTime Function() _clock;
  final Random _random;
  final _hosts = <String, _Host>{};
  var _disposed = false;

  static RemoteReconnector _defaultReconnector({
    required Future<ReconnectResult> Function() attempt,
    required void Function() onExhausted,
  }) => RemoteReconnector(attempt: attempt, onExhausted: onExhausted);

  @override
  ValueListenable<RemoteHostsState> get hosts =>
      remoteHostsSettings.remoteHosts;

  RemoteHostProfile? _profile(String id) => hosts.value.profile(id);

  _Host _host(String id) => _hosts.putIfAbsent(id, () => _Host(id));

  @override
  ValueListenable<RemoteHostConnectionState> connectionState(
    String profileId,
  ) => _host(profileId).state;

  @override
  Future<void> initialize() async {}

  // Profiles

  String _newId() {
    String hex(int bytes) => List.generate(
      bytes,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    // An RFC 4122 version 4 UUID.
    final variant = (8 + _random.nextInt(4)).toRadixString(16);
    return '${hex(4)}-${hex(2)}-4${hex(2).substring(1)}-'
        '$variant${hex(2).substring(1)}-${hex(6)}';
  }

  @override
  Future<RemoteHostProfile> addProfile(RemoteHostProfileDraft draft) async {
    final name = draft.displayName?.trim();
    final profile = RemoteHostProfile(
      id: _newId(),
      displayName: name == null || name.isEmpty ? draft.sshAlias : name,
      sshAlias: draft.sshAlias,
      autoInstallHelper: draft.autoInstallHelper,
      autoReconnect: draft.autoReconnect,
      openOnStartup: draft.openOnStartup,
      backgroundRefresh: draft.backgroundRefresh,
    );
    await remoteHostsSettings.addRemoteHostProfile(profile);
    return profile;
  }

  @override
  Future<void> updateProfile(RemoteHostProfile profile) async {
    final previous = _profile(profile.id);
    await remoteHostsSettings.updateRemoteHostProfile(profile);
    if (previous != null && previous.sshAlias != profile.sshAlias) {
      // Another host now: never keep talking to the old one.
      await disconnect(profile.id);
    }
  }

  @override
  Future<RemoteHostProfile> duplicateProfile(String profileId) async {
    final source = _profile(profileId);
    if (source == null) {
      throw const RemoteHostProfileRejected(
        RemoteHostProfileRejection.unknownProfile,
      );
    }
    final suffix = ' 2';
    final base =
        source.displayName.length + suffix.length >
            remoteHostDisplayNameMaxLength
        ? source.displayName.substring(
            0,
            remoteHostDisplayNameMaxLength - suffix.length,
          )
        : source.displayName;
    final copy = RemoteHostProfile(
      id: _newId(),
      displayName: '$base$suffix',
      sshAlias: source.sshAlias,
      autoInstallHelper: source.autoInstallHelper,
      autoReconnect: source.autoReconnect,
      openOnStartup: false,
      backgroundRefresh: source.backgroundRefresh,
    );
    await remoteHostsSettings.addRemoteHostProfile(copy);
    return copy;
  }

  @override
  Future<void> removeProfile(String profileId) async {
    await disconnect(profileId);
    await remoteHostsSettings.removeRemoteHostProfile(profileId);
  }

  // Probe

  @override
  Future<RemoteProbeResult> testConnection(String alias) async {
    final RemoteHelperConnection connection;
    try {
      connection = await connections.connect(alias);
    } on RemoteHostException catch (error) {
      return _probeFailure(error);
    }
    final facts = connection.hello.facts;
    await connection.close();
    return RemoteProbeResult(
      RemoteProbeOutcome.ready,
      target: facts.target,
      facts: facts,
    );
  }

  RemoteProbeResult _probeFailure(RemoteHostException error) {
    final outcome = switch (error.code) {
      RemoteFailureCode.hostKeyUntrusted => RemoteProbeOutcome.hostKeyUntrusted,
      RemoteFailureCode.authenticationInteractive =>
        RemoteProbeOutcome.authenticationInteractive,
      RemoteFailureCode.unsupportedPlatform =>
        RemoteProbeOutcome.unsupportedPlatform,
      RemoteFailureCode.helperNotInstalled => RemoteProbeOutcome.helperMissing,
      RemoteFailureCode.helperOutdated ||
      RemoteFailureCode.helperDamaged ||
      RemoteFailureCode.helperStartFailed ||
      RemoteFailureCode.protocolMismatch => RemoteProbeOutcome.helperOutdated,
      _ => RemoteProbeOutcome.sshUnreachable,
    };
    return RemoteProbeResult(
      outcome,
      failure: error.code,
      target: error.hostTarget,
    );
  }

  // Connections

  @override
  RemoteConnectionLease acquire(String profileId) {
    final host = _host(profileId);
    host.leases++;
    final state = host.state.value.phase;
    if (host.connection.value == null &&
        host.attempt == null &&
        state != RemoteConnectionPhase.reconnecting) {
      unawaited(connect(profileId));
    }
    return _Lease(this, host);
  }

  Future<void> _release(_Host host) async {
    host.leases = max(0, host.leases - 1);
    if (host.leases == 0) {
      await disconnect(host.profileId);
    }
  }

  @override
  Future<RemoteHostConnectionState> connect(String profileId) {
    final host = _host(profileId);
    if (host.connection.value?.isOpen ?? false) {
      return Future.value(host.state.value);
    }
    host.reconnector?.stop();
    host.reconnector = null;
    return host.attempt ??= _attempt(
      host,
      reconnecting: false,
    ).whenComplete(() => host.attempt = null);
  }

  Future<RemoteHostConnectionState> _attempt(
    _Host host, {
    required bool reconnecting,
  }) async {
    final profile = _profile(host.profileId);
    if (profile == null || _disposed) {
      return host.state.value = const RemoteHostConnectionState(
        phase: RemoteConnectionPhase.failed,
        failure: RemoteFailureCode.internal,
      );
    }
    final generation = host.generation;
    final cancel = host.cancel = Completer<void>();
    host.state.value = host.state.value.copyWith(
      phase: reconnecting
          ? RemoteConnectionPhase.reconnecting
          : RemoteConnectionPhase.probing,
    );
    var installed = false;
    while (true) {
      try {
        final connection = await connections.connect(
          profile.sshAlias,
          cancel: cancel.future,
        );
        if (generation != host.generation || _disposed) {
          await connection.close();
          return host.state.value;
        }
        _adopt(host, connection);
        return host.state.value;
      } on RemoteHostException catch (error) {
        if (generation != host.generation || _disposed) {
          return host.state.value;
        }
        final target = error.hostTarget;
        if (error.code == RemoteFailureCode.helperNotInstalled &&
            target != null &&
            profile.autoInstallHelper &&
            !installed) {
          installed = true;
          final RemoteInstallResult result;
          try {
            result = await _install(host, profile, target, cancel.future);
          } on RemoteHostException catch (installError) {
            return host.state.value = RemoteHostConnectionState(
              phase: RemoteConnectionPhase.failed,
              failure: installError.code,
              missingTarget: target,
              hello: host.state.value.hello,
            );
          }
          if (generation != host.generation) {
            return host.state.value;
          }
          if (result == RemoteInstallResult.ok) {
            host.state.value = host.state.value.copyWith(
              phase: RemoteConnectionPhase.handshaking,
            );
            continue;
          }
          return host.state.value = RemoteHostConnectionState(
            phase: RemoteConnectionPhase.failed,
            failure: _installFailure(result),
            missingTarget: target,
            hello: host.state.value.hello,
          );
        }
        _log.info(
          'remote_connect_failed profile=${host.profileId} '
          'code=${error.code.name}',
        );
        return host.state.value = RemoteHostConnectionState(
          phase: reconnecting
              ? RemoteConnectionPhase.reconnecting
              : error.code.retryable
              ? RemoteConnectionPhase.disconnected
              : RemoteConnectionPhase.failed,
          failure: error.code,
          missingTarget: target,
          hello: host.state.value.hello,
          connectedSince: null,
        );
      }
    }
  }

  void _adopt(_Host host, RemoteHelperConnection connection) {
    host.connection.value = connection;
    host.state.value = RemoteHostConnectionState(
      phase: RemoteConnectionPhase.live,
      hello: connection.hello,
      connectedSince: _clock(),
    );
    unawaited(
      remoteHostsSettings
          .updateRemoteHostFacts(host.profileId, connection.hello.facts)
          .catchError((Object _) {
            _log.warning('remote_facts_not_saved profile=${host.profileId}');
          }),
    );
    if (!host.pruned) {
      host.pruned = true;
      final profile = _profile(host.profileId);
      if (profile != null) {
        unawaited(
          connections
              .pruneHelpers(
                profile.sshAlias,
                keepBuildId: connection.hello.facts.helperBuildId,
              )
              .catchError((Object _) {
                _log.info('remote_prune_failed profile=${host.profileId}');
              }),
        );
      }
    }
    unawaited(
      connection.closed.then((code) => _onLost(host, connection, code)),
    );
  }

  void _onLost(
    _Host host,
    RemoteHelperConnection connection,
    RemoteFailureCode? code,
  ) {
    if (!identical(host.connection.value, connection) || _disposed) {
      return;
    }
    host.connection.value = null;
    final profile = _profile(host.profileId);
    if (code == null) {
      host.state.value = host.state.value.copyWith(
        phase: RemoteConnectionPhase.disconnected,
        failure: () => null,
        connectedSince: () => null,
      );
      return;
    }
    _log.info(
      'remote_connection_lost profile=${host.profileId} code=${code.name}',
    );
    final canRetry =
        code.retryable && (profile?.autoReconnect ?? false) && host.leases > 0;
    host.state.value = host.state.value.copyWith(
      phase: canRetry
          ? RemoteConnectionPhase.reconnecting
          : RemoteConnectionPhase.disconnected,
      failure: () => code,
      connectedSince: () => null,
    );
    if (!canRetry) {
      return;
    }
    final generation = host.generation;
    late final RemoteReconnector reconnector;
    reconnector = _reconnectorFactory(
      attempt: () async {
        if (generation != host.generation) {
          return ReconnectResult.giveUp;
        }
        final state = await (host.attempt ??= _attempt(
          host,
          reconnecting: true,
        ).whenComplete(() => host.attempt = null));
        if (state.phase == RemoteConnectionPhase.live) {
          return ReconnectResult.connected;
        }
        if (state.failure?.retryable ?? false) {
          return ReconnectResult.retry;
        }
        host.state.value = state.copyWith(phase: RemoteConnectionPhase.failed);
        return ReconnectResult.giveUp;
      },
      onExhausted: () {
        if (generation == host.generation &&
            identical(host.reconnector, reconnector)) {
          host.state.value = host.state.value.copyWith(
            phase: RemoteConnectionPhase.disconnected,
          );
        }
      },
    );
    host.reconnector = reconnector;
    reconnector.start();
  }

  @override
  Future<void> disconnect(String profileId) async {
    final host = _hosts[profileId];
    if (host == null) {
      return;
    }
    host.generation++;
    host.reconnector?.stop();
    host.reconnector = null;
    final cancel = host.cancel;
    if (cancel != null && !cancel.isCompleted) {
      cancel.complete();
    }
    final connection = host.connection.value;
    host.connection.value = null;
    host.state.value = host.state.value.copyWith(
      phase: RemoteConnectionPhase.disconnected,
      failure: () => null,
      connectedSince: () => null,
    );
    await connection?.close();
  }

  // Helpers

  @override
  Future<RemoteHelperArtifact?> bundledHelper(RemoteHelperTarget target) =>
      artifacts.bundledHelper(target);

  RemoteFailureCode _installFailure(RemoteInstallResult result) =>
      switch (result) {
        RemoteInstallResult.ok => RemoteFailureCode.internal,
        RemoteInstallResult.damaged => RemoteFailureCode.helperDamaged,
        RemoteInstallResult.noSpace => RemoteFailureCode.installNoSpace,
        RemoteInstallResult.noexec => RemoteFailureCode.installNoexec,
        RemoteInstallResult.refused => RemoteFailureCode.installRefused,
      };

  Future<RemoteInstallResult> _install(
    _Host host,
    RemoteHostProfile profile,
    RemoteHelperTarget target,
    Future<void>? cancel,
  ) async {
    final artifact = await artifacts.bundledHelper(target);
    if (artifact == null) {
      throw const RemoteHostException(RemoteFailureCode.unsupportedPlatform);
    }
    host.state.value = host.state.value.copyWith(
      phase: RemoteConnectionPhase.installing,
    );
    try {
      return await connections.installHelper(
        profile.sshAlias,
        artifact,
        cancel: cancel,
      );
    } on RemoteHostException catch (error) {
      host.state.value = host.state.value.copyWith(
        phase: RemoteConnectionPhase.failed,
        failure: () => error.code,
      );
      rethrow;
    }
  }

  @override
  Future<RemoteInstallResult> installHelper(
    String profileId,
    RemoteHelperTarget target, {
    Future<void>? cancel,
  }) async {
    final profile = _profile(profileId);
    if (profile == null) {
      throw const RemoteHostException(RemoteFailureCode.internal);
    }
    final host = _host(profileId);
    final result = await _install(host, profile, target, cancel);
    host.state.value = result == RemoteInstallResult.ok
        ? host.state.value.copyWith(
            phase: RemoteConnectionPhase.disconnected,
            failure: () => null,
            missingTarget: () => null,
          )
        : host.state.value.copyWith(
            phase: RemoteConnectionPhase.failed,
            failure: () => _installFailure(result),
          );
    return result;
  }

  @override
  Future<RemoteInstallResult> removeHelper(String profileId) async {
    final profile = _profile(profileId);
    if (profile == null) {
      throw const RemoteHostException(RemoteFailureCode.internal);
    }
    await disconnect(profileId);
    final result = await connections.removeHelpers(profile.sshAlias);
    _host(profileId).pruned = false;
    return result;
  }

  @override
  ProcessSource? createSource(String profileId) {
    if (_profile(profileId) == null) {
      return null;
    }
    return RemoteProcessSource(
      profileId: profileId,
      lease: acquire(profileId),
      pollingIntervalMs: () =>
          settingsService?.settings.value.pollingIntervalMs ??
          const AppSettings().pollingIntervalMs,
      icons: icons,
    );
  }

  @override
  Future<RemoteSnapshotContext?> snapshotContext(
    String profileId,
    ProcessSnapshot snapshot,
  ) async {
    final profile = _profile(profileId);
    if (profile == null) return null;
    final facts =
        _hosts[profileId]?.state.value.hello?.facts ?? profile.lastKnown;
    final icons = <String, Uint8List>{};
    var total = 0;
    for (final record in snapshot.processes) {
      if (record.iconRef case ProcessRemoteIcon(
        :final sha256,
      ) when !icons.containsKey(sha256)) {
        final bytes = await this.icons?.bytesFor(sha256);
        if (bytes == null || total + bytes.length > _snapshotIconBytes) {
          continue;
        }
        total += bytes.length;
        icons[sha256] = bytes;
      }
    }
    return RemoteSnapshotContext(
      host: SnapshotHost(
        displayName: profile.displayName,
        alias: profile.sshAlias,
        operatingSystem: facts?.target.os ?? '',
        architecture: facts?.target.arch ?? '',
      ),
      icons: icons,
    );
  }

  @override
  ProcessCadence backgroundCadenceFor(String profileId) {
    final mode =
        _profile(profileId)?.backgroundRefresh ??
        hosts.value.defaultBackgroundRefresh;
    return switch (mode) {
      BackgroundRefreshMode.slow => const ProcessCadence.background(
        defaultBackgroundRefreshInterval,
      ),
      BackgroundRefreshMode.live => ProcessCadence.background(
        Duration(
          milliseconds:
              settingsService?.settings.value.pollingIntervalMs ??
              const AppSettings().pollingIntervalMs,
        ),
      ),
      BackgroundRefreshMode.paused => ProcessCadence.paused,
    };
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final host in [..._hosts.values]) {
      await disconnect(host.profileId);
    }
  }
}

final class _Host {
  _Host(this.profileId);

  final String profileId;
  final state = ValueNotifier<RemoteHostConnectionState>(
    RemoteHostConnectionState.idle,
  );
  final connection = ValueNotifier<RemoteHelperConnection?>(null);
  var leases = 0;
  var generation = 0;
  var pruned = false;
  Future<RemoteHostConnectionState>? attempt;
  Completer<void>? cancel;
  RemoteReconnector? reconnector;
}

final class _Lease implements RemoteConnectionLease {
  _Lease(this._service, this._host);

  final RemoteHostServiceImpl _service;
  final _Host _host;
  var _released = false;

  @override
  String get profileId => _host.profileId;

  @override
  ValueListenable<RemoteHelperConnection?> get connection => _host.connection;

  @override
  ValueListenable<RemoteHostConnectionState> get state => _host.state;

  @override
  void markSample() {}

  @override
  Future<void> release() async {
    if (_released) {
      return;
    }
    _released = true;
    await _service._release(_host);
  }
}
