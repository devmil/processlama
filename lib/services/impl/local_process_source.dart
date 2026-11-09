import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../../models/models.dart';
import '../../repositories/repositories.dart';
import '../process_source.dart';
import '../repository_operation_tracker.dart';

/// Samples this computer through the native [ProcessRepository] on a timer.
///
/// One sample is in flight at a time; a request during a sample shares it.
class LocalProcessSource implements ProcessSource {
  LocalProcessSource({
    required this.processRepository,
    required this.repositoryOperationTracker,
    TargetPlatform? platform,
  }) : _capabilities = ValueNotifier(
         HostCapabilities.local(platform ?? defaultTargetPlatform),
       );

  static final _log = Logger('LocalProcessSource');

  final ProcessRepository processRepository;
  final RepositoryOperationTracker repositoryOperationTracker;
  final ValueNotifier<HostCapabilities> _capabilities;
  final ValueNotifier<ProcessSourceState> _state = ValueNotifier(
    ProcessSourceState.live,
  );
  final StreamController<ProcessSnapshot> _updates =
      StreamController<ProcessSnapshot>.broadcast(sync: true);

  ProcessCadence _cadence = ProcessCadence.paused;
  Timer? _timer;
  Future<void>? _inFlight;
  var _disposed = false;

  /// The polling interval the native engine samples at; its rates span it.
  int _pollingIntervalMs = const AppSettings().pollingIntervalMs;

  @override
  ProcessSourceDescriptor get descriptor => ProcessSourceDescriptor.local;

  @override
  ValueListenable<ProcessSourceState> get state => _state;

  @override
  ValueListenable<HostCapabilities> get capabilities => _capabilities;

  @override
  Stream<ProcessSnapshot> get updates => _updates.stream;

  ProcessCadence get cadence => _cadence;

  @override
  Future<void> setCadence(ProcessCadence cadence) async {
    if (_disposed || cadence == _cadence) {
      return;
    }
    _cadence = cadence;
    _timer?.cancel();
    _timer = null;
    final interval = cadence.interval;
    if (interval == null) {
      return;
    }
    if (cadence is LiveCadence) {
      _pollingIntervalMs = interval.inMilliseconds;
    }
    _timer = Timer.periodic(
      Duration(milliseconds: interval.inMilliseconds.clamp(250, 10000)),
      (_) => unawaited(sampleNow()),
    );
  }

  @override
  Future<void> sampleNow() {
    if (_disposed) {
      return Future<void>.value();
    }
    return _inFlight ??= _sample().whenComplete(() => _inFlight = null);
  }

  Future<void> _sample() async {
    ProcessSnapshot next;
    try {
      repositoryOperationTracker.recordOperation(
        'ProcessRepository.fetchSnapshot',
        'ProcessService.refresh',
      );
      next = await processRepository.fetchSnapshot(
        pollingIntervalMs: _pollingIntervalMs,
      );
    } on Object catch (error, stackTrace) {
      _log.warning('Failed to refresh process snapshot.', error, stackTrace);
      next = ProcessSnapshot.empty(error: error.toString());
    }
    if (_disposed) {
      return;
    }
    _state.value = ProcessSourceState(
      phase: ProcessSourcePhase.live,
      lastSampleAt: DateTime.now(),
    );
    _updates.add(next);
  }

  /// Sets the native polling interval without changing the cadence.
  void setPollingInterval(int intervalMs) => _pollingIntervalMs = intervalMs;

  @override
  Future<ProcessDetail?> fetchDetail(ProcessIdentity identity) {
    repositoryOperationTracker.recordOperation(
      'ProcessRepository.fetchProcessDetail',
      'ProcessService.refreshInspectorDetail',
    );
    return processRepository.fetchProcessDetail(identity);
  }

  @override
  Future<void> sendSignal(ProcessIdentity identity, ProcessSignal signal) {
    repositoryOperationTracker.recordOperation(
      'ProcessRepository.sendSignal',
      'ProcessService.${signal.name}Process',
    );
    return processRepository.sendSignal(identity, signal);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _updates.close();
    _state.dispose();
    _capabilities.dispose();
  }
}
