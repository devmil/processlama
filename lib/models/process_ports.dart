import 'process_identity.dart';
import 'process_record.dart';

/// The local ports of a process or a subtree, split into the ports it serves
/// on and the other local ports, mostly outgoing connections.
class ProcessPorts {
  const ProcessPorts({required this.listening, required this.other});

  /// Null when the host did not report port ownership for [record].
  static ProcessPorts? ofRecord(ProcessRecord record) {
    final local = record.localPorts;
    if (local == null) return null;
    return ProcessPorts.merge([(local, record.listeningPorts)]);
  }

  /// Combines `(localPorts, listeningPorts)` pairs. A port that listens in
  /// one process is listed as listening even when another uses it otherwise.
  factory ProcessPorts.merge(
    Iterable<(List<int> local, List<int>? listening)> sources,
  ) {
    final listening = <int>{};
    final local = <int>{};
    for (final (localPorts, listeningPorts) in sources) {
      local.addAll(localPorts);
      listening.addAll(listeningPorts ?? const []);
    }
    return ProcessPorts(
      listening: List<int>.unmodifiable(listening.toList()..sort()),
      other: List<int>.unmodifiable(
        local.difference(listening).toList()..sort(),
      ),
    );
  }

  /// Sorted distinct ports this process serves on: TCP listeners and UDP
  /// sockets bound to a well-known port.
  final List<int> listening;

  /// Sorted distinct local ports that are not [listening].
  final List<int> other;

  bool get isEmpty => listening.isEmpty && other.isEmpty;
  int get count => listening.length + other.length;
}

/// A process that listens on a port, for linking a socket to its peer.
class ProcessPortOwner {
  const ProcessPortOwner({
    required this.identity,
    required this.pid,
    required this.name,
  });

  final ProcessIdentity identity;
  final int pid;
  final String name;
}

/// Whether [address] names this host from its own point of view.
bool isLoopbackAddress(String address) {
  final value = address.toLowerCase();
  return value.startsWith('127.') ||
      value == '::1' ||
      value == 'localhost' ||
      value.startsWith('::ffff:127.');
}
