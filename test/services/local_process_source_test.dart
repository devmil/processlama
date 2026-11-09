import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/repositories.dart';
import 'package:processlama/services/impl/local_process_source.dart';
import 'package:processlama/services/impl/repository_operation_tracker_impl.dart';

void main() {
  test('concurrent sample requests share one repository fetch', () async {
    final repository = _GatedRepository();
    final source = _source(repository);
    final delivered = <ProcessSnapshot>[];
    source.updates.listen(delivered.add);

    final first = source.sampleNow();
    final second = source.sampleNow();
    repository.release();
    await Future.wait([first, second]);

    expect(repository.fetches, 1);
    expect(delivered, hasLength(1));
  });

  test('samples on the cadence timer and stops when paused', () {
    fakeAsync((async) {
      final repository = _GatedRepository(open: true);
      final source = _source(repository);
      source.setCadence(const ProcessCadence.live(Duration(seconds: 1)));
      async.elapse(const Duration(milliseconds: 3100));
      expect(repository.fetches, 3);
      expect(repository.pollingIntervals.toSet(), {1000});

      source.setCadence(const ProcessCadence.background(Duration(seconds: 5)));
      async.elapse(const Duration(seconds: 10));
      expect(repository.fetches, 5);
      // The native engine keeps the live polling interval in the background.
      expect(repository.pollingIntervals.toSet(), {1000});

      source.setCadence(ProcessCadence.paused);
      async.elapse(const Duration(seconds: 30));
      expect(repository.fetches, 5);
      source.dispose();
    });
  });

  test('a failed fetch delivers an empty snapshot with the error', () async {
    final source = _source(_GatedRepository(open: true, fail: true));
    final delivered = <ProcessSnapshot>[];
    source.updates.listen(delivered.add);

    await source.sampleNow();

    expect(delivered.single.processes, isEmpty);
    expect(delivered.single.error, isNotNull);
  });

  test('reports capabilities of the running platform', () {
    final source = LocalProcessSource(
      processRepository: _GatedRepository(open: true),
      repositoryOperationTracker: RepositoryOperationTrackerImpl(),
      platform: TargetPlatform.linux,
    );
    expect(
      source.capabilities.value.operatingSystem,
      HostOperatingSystem.linux,
    );
    expect(source.capabilities.value.networkSource, NetworkRateSource.ebpf);
  });

  test('dispose stops sampling', () {
    fakeAsync((async) {
      final repository = _GatedRepository(open: true);
      final source = _source(repository);
      source.setCadence(const ProcessCadence.live(Duration(seconds: 1)));
      source.dispose();
      async.elapse(const Duration(seconds: 5));
      expect(repository.fetches, 0);
    });
  });
}

LocalProcessSource _source(ProcessRepository repository) => LocalProcessSource(
  processRepository: repository,
  repositoryOperationTracker: RepositoryOperationTrackerImpl(),
);

class _GatedRepository implements ProcessRepository {
  _GatedRepository({bool open = false, this.fail = false}) {
    if (open) _gate.complete();
  }

  final bool fail;
  final _gate = Completer<void>();
  final pollingIntervals = <int>[];
  var fetches = 0;

  void release() => _gate.complete();

  @override
  Future<ProcessSnapshot> fetchSnapshot({
    required int pollingIntervalMs,
  }) async {
    fetches++;
    pollingIntervals.add(pollingIntervalMs);
    await _gate.future;
    if (fail) throw StateError('native core unavailable');
    return ProcessSnapshot.empty();
  }

  @override
  Future<ProcessDetail> fetchProcessDetail(ProcessIdentity identity) =>
      throw UnimplementedError();

  @override
  Future<void> sendSignal(ProcessIdentity identity, ProcessSignal signal) =>
      throw UnimplementedError();
}
