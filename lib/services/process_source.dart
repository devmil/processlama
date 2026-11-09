import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../repositories/repositories.dart';

/// Identifies what a [ProcessSource] shows.
@immutable
sealed class ProcessSourceDescriptor {
  const ProcessSourceDescriptor();

  static const local = LocalProcessSourceDescriptor();
}

final class LocalProcessSourceDescriptor extends ProcessSourceDescriptor {
  const LocalProcessSourceDescriptor();
}

final class RemoteProcessSourceDescriptor extends ProcessSourceDescriptor {
  const RemoteProcessSourceDescriptor(this.profileId);

  final String profileId;
}

/// The data source of one tab: this computer or one remote host.
///
/// A source samples on its own at the [setCadence] it was given and delivers
/// every sample on [updates], newest first: a source never queues samples
/// behind a slow consumer.
abstract interface class ProcessSource {
  ProcessSourceDescriptor get descriptor;

  ValueListenable<ProcessSourceState> get state;

  ValueListenable<HostCapabilities> get capabilities;

  /// Samples. Listeners run synchronously when a sample is delivered.
  Stream<ProcessSnapshot> get updates;

  Future<void> setCadence(ProcessCadence cadence);

  /// Requests a sample now. Completes after that sample was delivered on
  /// [updates], or immediately when this source cannot sample on demand.
  Future<void> sampleNow();

  Future<ProcessDetail?> fetchDetail(ProcessIdentity identity);

  /// Sends [signal] once. Throws [ProcessSignalException] when the signal did
  /// not reach the process; an `unknown` outcome is never retried.
  Future<void> sendSignal(ProcessIdentity identity, ProcessSignal signal);

  Future<void> dispose();
}
