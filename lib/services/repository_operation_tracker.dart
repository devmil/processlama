abstract interface class RepositoryOperationTracker {
  void recordOperation(String operation, String? context);

  Map<String, int> getOperationStats();

  List<String> getOptimizationReport();

  void clearStats();

  void startBulkOperation(String operationType);

  void endBulkOperation(String operationType, int operationCount);

  Map<String, Map<String, Object?>> getBulkOperationStats();
}
