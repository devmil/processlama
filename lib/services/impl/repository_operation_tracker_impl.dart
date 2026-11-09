import '../repository_operation_tracker.dart';

class RepositoryOperationTrackerImpl implements RepositoryOperationTracker {
  final Map<String, int> _operationCounts = {};
  final Map<String, List<String>> _operationContexts = {};
  final Map<String, Map<String, Object?>> _bulkOperationStats = {};
  final Map<String, DateTime> _bulkOperationStartTimes = {};

  @override
  void recordOperation(String operation, String? context) {
    _operationCounts[operation] = (_operationCounts[operation] ?? 0) + 1;

    if (context != null) {
      _operationContexts.putIfAbsent(operation, () => <String>[]).add(context);
    }
  }

  @override
  Map<String, int> getOperationStats() {
    return Map<String, int>.from(_operationCounts);
  }

  @override
  List<String> getOptimizationReport() {
    final report = <String>[];

    _operationCounts.forEach((operation, count) {
      if (count > 10) {
        report.add(
          'High frequency repository operation: $operation ($count calls)',
        );
      }

      if (operation.contains('fetchSnapshot') && count > 5) {
        report.add(
          'Review process snapshot polling cadence - called $count times.',
        );
      }
    });

    _bulkOperationStats.forEach((operation, stats) {
      final totalOperations = stats['totalOperations'] as int? ?? 0;
      final batchCount = stats['batchCount'] as int? ?? 0;
      if (batchCount == 0) {
        return;
      }

      final averageBatchSize = totalOperations / batchCount;
      if (averageBatchSize < 3) {
        report.add(
          'Small batch sizes for $operation '
          '(avg: ${averageBatchSize.toStringAsFixed(1)}).',
        );
      }
    });

    return report;
  }

  @override
  void clearStats() {
    _operationCounts.clear();
    _operationContexts.clear();
    _bulkOperationStats.clear();
    _bulkOperationStartTimes.clear();
  }

  @override
  void startBulkOperation(String operationType) {
    _bulkOperationStartTimes[operationType] = DateTime.now();
  }

  @override
  void endBulkOperation(String operationType, int operationCount) {
    final startTime = _bulkOperationStartTimes.remove(operationType);
    if (startTime == null) {
      return;
    }

    final duration = DateTime.now().difference(startTime);
    final stats = _bulkOperationStats.putIfAbsent(
      operationType,
      () => <String, Object?>{
        'totalOperations': 0,
        'batchCount': 0,
        'totalDuration': Duration.zero,
      },
    );

    stats['totalOperations'] =
        (stats['totalOperations'] as int) + operationCount;
    stats['batchCount'] = (stats['batchCount'] as int) + 1;
    stats['totalDuration'] = (stats['totalDuration'] as Duration) + duration;
  }

  @override
  Map<String, Map<String, Object?>> getBulkOperationStats() {
    return Map<String, Map<String, Object?>>.from(_bulkOperationStats);
  }
}
