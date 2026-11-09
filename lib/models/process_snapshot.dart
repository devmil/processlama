import 'process_record.dart';
import 'process_topology.dart';

class ProcessSnapshot {
  const ProcessSnapshot({
    required this.generatedAtUnixMs,
    required this.platform,
    required this.processes,
    this.error,
    this.topology,
  });

  factory ProcessSnapshot.empty({String? error}) {
    return ProcessSnapshot(
      generatedAtUnixMs: DateTime.now().millisecondsSinceEpoch,
      platform: 'unknown',
      processes: const <ProcessRecord>[],
      error: error,
    );
  }

  factory ProcessSnapshot.fromJson(Map<String, Object?> json) {
    if (json case {'error': final String error}) {
      return ProcessSnapshot.empty(error: error);
    }

    final rawProcesses = json['processes'];
    return ProcessSnapshot(
      generatedAtUnixMs: (json['generated_at_unix_ms'] as num?)?.toInt() ?? 0,
      platform: json['platform'] as String? ?? 'unknown',
      processes: rawProcesses is List<Object?>
          ? rawProcesses
                .whereType<Map<String, Object?>>()
                .map(ProcessRecord.fromJson)
                .toList()
          : const <ProcessRecord>[],
    );
  }

  final int generatedAtUnixMs;
  final String platform;
  final List<ProcessRecord> processes;
  final String? error;
  final ProcessTopology? topology;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'generated_at_unix_ms': generatedAtUnixMs,
      'platform': platform,
      'processes': processes.map((process) => process.toJson()).toList(),
      if (error != null) 'error': error,
    };
  }
}
