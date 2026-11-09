import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../process_icon_service.dart';
import '../process_source.dart';
import '../remote_host_service.dart';

/// Samples one remote host through its helper's telemetry subscription.
///
/// The source holds a lease on the host's shared connection and subscribes
/// whenever a connection is live; after a reconnect it subscribes again and
/// receives the full topology. While disconnected it delivers nothing, so the
/// last sample stays visible and the state is stale.
class RemoteProcessSource implements ProcessSource {
  RemoteProcessSource({
    required this.profileId,
    required this.lease,
    required this.pollingIntervalMs,
    this.icons,
  }) : descriptor = RemoteProcessSourceDescriptor(profileId) {
    lease.connection.addListener(_onConnection);
    lease.state.addListener(_onHostState);
    _onHostState();
    _onConnection();
  }

  static final _log = Logger('RemoteProcessSource');

  final String profileId;
  final RemoteConnectionLease lease;

  /// The live polling interval the helper's engine samples at.
  final int Function() pollingIntervalMs;

  /// Fetches and caches the icons a topology names.
  final ProcessIconService? icons;

  String get _iconKey => 'remote:$profileId';
  ProcessTopology? _iconTopology;

  @override
  final RemoteProcessSourceDescriptor descriptor;

  final _state = ValueNotifier<ProcessSourceState>(
    const ProcessSourceState(phase: ProcessSourcePhase.connecting),
  );
  final _capabilities = ValueNotifier<HostCapabilities>(
    HostCapabilities.unknown,
  );
  final _updates = StreamController<ProcessSnapshot>.broadcast(sync: true);

  ProcessCadence _cadence = ProcessCadence.paused;
  RemoteHelperConnection? _connection;
  RemoteTelemetryStream? _telemetry;
  StreamSubscription<ProcessSnapshot>? _samples;
  DateTime? _lastSampleAt;
  var _subscribing = 0;
  var _disposed = false;

  @override
  ValueListenable<ProcessSourceState> get state => _state;

  @override
  ValueListenable<HostCapabilities> get capabilities => _capabilities;

  @override
  Stream<ProcessSnapshot> get updates => _updates.stream;

  int? get _cadenceMs => _cadence.interval?.inMilliseconds;

  void _onHostState() {
    if (_disposed) return;
    final host = lease.state.value;
    if (host.hello case final hello?) {
      _capabilities.value = hello.capabilities;
    }
    final phase = switch (host.phase) {
      RemoteConnectionPhase.live =>
        _lastSampleAt == null
            ? ProcessSourcePhase.connecting
            : ProcessSourcePhase.live,
      // A tab that has shown a sample keeps it, marked stale.
      RemoteConnectionPhase.failed ||
      RemoteConnectionPhase.reconnecting ||
      RemoteConnectionPhase.disconnected =>
        _lastSampleAt == null
            ? ProcessSourcePhase.failed
            : ProcessSourcePhase.stale,
      _ =>
        _lastSampleAt == null
            ? ProcessSourcePhase.connecting
            : ProcessSourcePhase.stale,
    };
    _state.value = ProcessSourceState(
      phase: phase,
      lastSampleAt: _lastSampleAt,
      failureCode: host.failure?.name,
    );
  }

  void _onConnection() {
    if (_disposed) return;
    final connection = lease.connection.value;
    if (identical(connection, _connection)) return;
    _stopTelemetry();
    _connection = connection;
    _iconTopology = null;
    if (connection != null) {
      icons?.resetFailures(_iconKey);
      unawaited(_subscribe(connection));
    }
  }

  void _stopTelemetry() {
    unawaited(_samples?.cancel());
    _samples = null;
    _telemetry?.cancel();
    _telemetry = null;
  }

  Future<void> _subscribe(RemoteHelperConnection connection) async {
    final attempt = ++_subscribing;
    try {
      final requested = _cadenceMs;
      final telemetry = await connection.subscribeTelemetry(
        cadenceMs: requested,
        pollingMs: pollingIntervalMs(),
      );
      if (_disposed ||
          attempt != _subscribing ||
          !identical(_connection, connection)) {
        telemetry.cancel();
        return;
      }
      _telemetry = telemetry;
      if (_cadenceMs != requested) {
        // The cadence changed while subscribing.
        unawaited(
          telemetry
              .setCadence(cadenceMs: _cadenceMs, pollingMs: pollingIntervalMs())
              .catchError((Object _) {}),
        );
      }
      _samples = telemetry.snapshots.listen(
        (snapshot) => _deliver(telemetry, snapshot),
        onError: (Object error) {
          // A malformed sample: start over with a fresh topology.
          _log.warning('remote_sample_rejected profile=$profileId');
          if (identical(_telemetry, telemetry)) {
            _stopTelemetry();
            unawaited(_subscribe(connection));
          }
        },
      );
    } on RemoteCallFailure catch (failure) {
      _log.warning(
        'remote_telemetry_refused profile=$profileId code=${failure.code}',
      );
    }
  }

  void _deliver(RemoteTelemetryStream telemetry, ProcessSnapshot snapshot) {
    if (_disposed || !identical(_telemetry, telemetry)) return;
    _lastSampleAt = DateTime.now();
    lease.markSample();
    _requestIcons(snapshot);
    _onHostState();
    _updates.add(snapshot);
    // Credit after the sample was applied: a slow client lowers the rate.
    telemetry.grant(1);
  }

  /// Asks for the icons of a new topology; metric-only samples share it.
  void _requestIcons(ProcessSnapshot snapshot) {
    final service = icons;
    final connection = _connection;
    if (service == null ||
        connection == null ||
        identical(snapshot.topology, _iconTopology)) {
      return;
    }
    _iconTopology = snapshot.topology;
    service.ensure(_iconKey, {
      for (final record in snapshot.processes)
        if (record.iconRef case ProcessRemoteIcon(:final sha256)) sha256,
    }, connection.fetchIcons);
  }

  @override
  Future<void> setCadence(ProcessCadence cadence) async {
    if (_disposed || cadence == _cadence) return;
    _cadence = cadence;
    final telemetry = _telemetry;
    if (telemetry == null) return;
    try {
      await telemetry.setCadence(
        cadenceMs: _cadenceMs,
        pollingMs: pollingIntervalMs(),
      );
    } on RemoteCallFailure {
      // The next subscription carries the cadence.
    }
  }

  /// The helper pushes samples at its cadence; there is nothing to pull.
  @override
  Future<void> sampleNow() async {}

  @override
  Future<ProcessDetail?> fetchDetail(ProcessIdentity identity) async {
    final connection = _connection;
    if (connection == null) return null;
    try {
      return await connection.fetchDetail(identity);
    } on RemoteCallFailure {
      return null;
    }
  }

  @override
  Future<void> sendSignal(
    ProcessIdentity identity,
    ProcessSignal signal,
  ) async {
    final connection = _connection;
    if (connection == null) {
      throw const ProcessSignalException(SignalOutcome.unknown);
    }
    final SignalOutcome outcome;
    try {
      outcome = await connection.sendSignal(identity, signal);
    } on RemoteCallFailure {
      // The signal may or may not have been sent; never resend it.
      throw const ProcessSignalException(SignalOutcome.unknown);
    }
    if (outcome != SignalOutcome.sent) {
      throw ProcessSignalException(outcome);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    lease.connection.removeListener(_onConnection);
    lease.state.removeListener(_onHostState);
    _stopTelemetry();
    icons?.release(_iconKey);
    await _updates.close();
    await lease.release();
  }
}
