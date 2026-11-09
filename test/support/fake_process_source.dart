import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/repositories.dart';
import 'package:processlama/services/services.dart';

/// A [ProcessSource] driven by the test: [emit] delivers a sample, cadence
/// changes and disposal are recorded.
class FakeProcessSource implements ProcessSource {
  FakeProcessSource({
    this.descriptor = ProcessSourceDescriptor.local,
    HostCapabilities capabilities = HostCapabilities.unknown,
    this.onSampleNow,
  }) : _capabilities = ValueNotifier(capabilities);

  @override
  final ProcessSourceDescriptor descriptor;
  final ValueNotifier<HostCapabilities> _capabilities;
  final ValueNotifier<ProcessSourceState> _state = ValueNotifier(
    const ProcessSourceState(phase: ProcessSourcePhase.connecting),
  );
  final _updates = StreamController<ProcessSnapshot>.broadcast(sync: true);
  final cadences = <ProcessCadence>[];
  final signals = <(ProcessIdentity, ProcessSignal)>[];

  /// Called by [sampleNow]; return a snapshot to deliver it.
  ProcessSnapshot? Function()? onSampleNow;
  SignalOutcome signalOutcome = SignalOutcome.sent;
  var disposed = false;

  /// Called first in [dispose].
  void Function()? onDispose;
  var sampleRequests = 0;

  @override
  ValueListenable<ProcessSourceState> get state => _state;

  @override
  ValueListenable<HostCapabilities> get capabilities => _capabilities;

  @override
  Stream<ProcessSnapshot> get updates => _updates.stream;

  ProcessCadence? get cadence => cadences.isEmpty ? null : cadences.last;

  void emit(ProcessSnapshot snapshot) {
    _state.value = const ProcessSourceState(phase: ProcessSourcePhase.live);
    _updates.add(snapshot);
  }

  void setState(ProcessSourceState state) => _state.value = state;

  @override
  Future<void> setCadence(ProcessCadence cadence) async =>
      cadences.add(cadence);

  @override
  Future<void> sampleNow() async {
    sampleRequests++;
    final next = onSampleNow?.call();
    if (next != null) {
      emit(next);
    }
  }

  @override
  Future<ProcessDetail?> fetchDetail(ProcessIdentity identity) async => null;

  @override
  Future<void> sendSignal(
    ProcessIdentity identity,
    ProcessSignal signal,
  ) async {
    signals.add((identity, signal));
    if (signalOutcome != SignalOutcome.sent) {
      throw ProcessSignalException(signalOutcome);
    }
  }

  @override
  Future<void> dispose() async {
    onDispose?.call();
    disposed = true;
    await _updates.close();
  }
}
