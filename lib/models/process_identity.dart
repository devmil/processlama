import 'package:flutter/foundation.dart';

@immutable
class ProcessIdentity {
  const ProcessIdentity({required this.pid, required this.startTimeUnixMs});

  final int pid;
  final int startTimeUnixMs;

  @override
  bool operator ==(Object other) {
    return other is ProcessIdentity &&
        other.pid == pid &&
        other.startTimeUnixMs == startTimeUnixMs;
  }

  @override
  int get hashCode => Object.hash(pid, startTimeUnixMs);

  @override
  String toString() => '$pid@$startTimeUnixMs';
}
