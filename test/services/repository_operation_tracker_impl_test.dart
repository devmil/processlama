import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/services/impl/repository_operation_tracker_impl.dart';

void main() {
  test('tracks operation counts', () {
    final tracker = RepositoryOperationTrackerImpl();

    tracker.recordOperation('ProcessRepository.fetchSnapshot', 'refresh');
    tracker.recordOperation('ProcessRepository.fetchSnapshot', 'refresh');

    expect(tracker.getOperationStats(), {'ProcessRepository.fetchSnapshot': 2});
  });

  test('reports high-frequency snapshot polling', () {
    final tracker = RepositoryOperationTrackerImpl();

    for (var i = 0; i < 6; i++) {
      tracker.recordOperation('ProcessRepository.fetchSnapshot', 'refresh');
    }

    expect(
      tracker.getOptimizationReport(),
      contains(contains('Review process snapshot polling cadence')),
    );
  });
}
