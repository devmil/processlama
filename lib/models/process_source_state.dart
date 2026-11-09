import 'package:flutter/foundation.dart';

/// How often a process source samples.
@immutable
sealed class ProcessCadence {
  const ProcessCadence();

  const factory ProcessCadence.live(Duration interval) = LiveCadence;
  const factory ProcessCadence.background(Duration interval) =
      BackgroundCadence;
  static const paused = PausedCadence();

  /// The sampling interval, or null while paused.
  Duration? get interval;
}

final class LiveCadence extends ProcessCadence {
  const LiveCadence(this.interval);

  @override
  final Duration interval;

  @override
  bool operator ==(Object other) =>
      other is LiveCadence && other.interval == interval;

  @override
  int get hashCode => Object.hash(LiveCadence, interval);
}

final class BackgroundCadence extends ProcessCadence {
  const BackgroundCadence(this.interval);

  @override
  final Duration interval;

  @override
  bool operator ==(Object other) =>
      other is BackgroundCadence && other.interval == interval;

  @override
  int get hashCode => Object.hash(BackgroundCadence, interval);
}

final class PausedCadence extends ProcessCadence {
  const PausedCadence();

  @override
  Duration? get interval => null;

  @override
  bool operator ==(Object other) => other is PausedCadence;

  @override
  int get hashCode => (PausedCadence).hashCode;
}

/// Background tabs refresh this often unless a profile overrides it.
const defaultBackgroundRefreshInterval = Duration(seconds: 5);

/// Whether a source delivers current data.
enum ProcessSourcePhase {
  /// No sample has arrived yet.
  connecting,

  /// Samples arrive at the requested cadence.
  live,

  /// The connection dropped; the last sample stays visible.
  stale,

  /// The source cannot deliver data until the user acts.
  failed,
}

@immutable
class ProcessSourceState {
  const ProcessSourceState({
    required this.phase,
    this.lastSampleAt,
    this.failureCode,
  });

  static const live = ProcessSourceState(phase: ProcessSourcePhase.live);

  final ProcessSourcePhase phase;

  /// When the newest sample arrived.
  final DateTime? lastSampleAt;

  /// A typed, non-sensitive failure code (for example a `RemoteFailureCode`
  /// name) while stale or failed.
  final String? failureCode;

  @override
  bool operator ==(Object other) =>
      other is ProcessSourceState &&
      other.phase == phase &&
      other.lastSampleAt == lastSampleAt &&
      other.failureCode == failureCode;

  @override
  int get hashCode => Object.hash(phase, lastSampleAt, failureCode);
}

/// The typed result of a signal request. An [unknown] signal is never resent.
enum SignalOutcome { sent, denied, notFound, unknown }

/// A signal that did not reach its process.
final class ProcessSignalException implements Exception {
  const ProcessSignalException(this.outcome);

  final SignalOutcome outcome;

  @override
  String toString() => 'ProcessSignalException(${outcome.name})';
}
