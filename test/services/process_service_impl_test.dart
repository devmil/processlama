import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/repositories.dart';
import 'package:processlama/services/impl/process_service_impl.dart';
import 'package:processlama/services/impl/repository_operation_tracker_impl.dart';
import 'package:processlama/services/services.dart';

import '../support/fake_process_source.dart';
import '../support/wire_loopback_source.dart';

/// Every test runs against the local source and against a remote source whose
/// samples, details and signals cross the helper's wire encoding.
enum _Source { local, remote }

var _source = _Source.local;

void main() {
  for (final source in _Source.values) {
    group('${source.name} source', () {
      setUp(() => _source = source);
      _sessionTests();
    });
  }

  test('an outage leaves a gap in the histories, never a line', () async {
    final source = FakeProcessSource();
    final session = ProcessSession(
      source: source,
      snapshotRepository: _FakeSnapshotRepository(),
      repositoryOperationTracker: RepositoryOperationTrackerImpl(),
    );
    addTearDown(session.dispose);
    List<double> history() => session.tree.value.visibleRows.single.cpuHistory;

    source.emit(_snapshot([_process(pid: 1, name: 'root', cpuUsage: 10)]));
    source.emit(_snapshot([_process(pid: 1, name: 'root', cpuUsage: 20)]));
    source.setState(const ProcessSourceState(phase: ProcessSourcePhase.stale));
    source.setState(
      const ProcessSourceState(phase: ProcessSourcePhase.connecting),
    );
    source.emit(_snapshot([_process(pid: 1, name: 'root', cpuUsage: 30)]));
    source.emit(_snapshot([_process(pid: 1, name: 'root', cpuUsage: 40)]));

    final samples = history();
    expect(samples, hasLength(5));
    expect(samples.take(2), [10, 20]);
    expect(samples[2].isNaN, isTrue);
    expect(samples.skip(3), [30, 40]);
    expect(
      session.tree.value.visibleRows.single.record.identity,
      _id(1),
      reason: 'the process outlives the outage',
    );
  });
}

void _sessionTests() {
  test(
    'inspector tree ports include hidden descendants and refresh without stale ports',
    () async {
      final service = _createService(
        _FakeProcessRepository([
          _snapshot([
            _process(
              pid: 1,
              name: 'root',
            ).copyWith(localPorts: [8080], listeningPorts: [8080]),
            _process(
              pid: 2,
              ppid: 1,
              name: 'child',
            ).copyWith(localPorts: [53, 8080]),
            _process(
              pid: 3,
              ppid: 2,
              name: 'grandchild',
            ).copyWith(localPorts: [443]),
            _process(pid: 4, name: 'unrelated').copyWith(localPorts: [9000]),
          ]),
          _snapshot([
            _process(
              pid: 1,
              name: 'root',
            ).copyWith(localPorts: [8080], listeningPorts: [8080]),
            _process(
              pid: 2,
              ppid: 1,
              name: 'child',
            ).copyWith(localPorts: [5353]),
            _process(pid: 4, name: 'unrelated').copyWith(localPorts: [9000]),
          ]),
        ]),
      );
      await service.refresh();
      service.selectProcess(_id(1));
      service.collapseSelectedSubtree();
      expect(
        service.tree.value.visibleRows.map((r) => r.record.pid),
        isNot(contains(3)),
      );
      final inspector = service.inspector.value;
      expect(inspector.treePorts!.listening, [8080]);
      expect(
        inspector.treePorts!.other,
        [53, 443],
        reason: 'a port that listens anywhere in the tree counts as listening',
      );
      expect(inspector.ports!.listening, [8080]);
      expect(inspector.ports!.other, isEmpty);
      service.setFilter('root');
      expect(service.inspector.value.treePorts!.other, [53, 443]);
      await service.refresh();
      expect(service.inspector.value.treePorts!.listening, [8080]);
      expect(service.inspector.value.treePorts!.other, [5353]);
      expect(
        () => service.inspector.value.treePorts!.listening.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'tree ports use known descendants even when the root has no report',
    () async {
      final service = _createService(
        _FakeProcessRepository([
          _snapshot([
            _process(pid: 1, name: 'root'),
            _process(pid: 2, ppid: 1, name: 'child').copyWith(localPorts: [80]),
            _process(pid: 3, name: 'unreported'),
          ]),
        ]),
      );
      await service.refresh();
      service.selectProcess(_id(1));
      expect(service.inspector.value.ports, isNull);
      expect(service.inspector.value.treePorts!.other, [80]);
      service.selectProcess(_id(3));
      expect(service.inspector.value.treePorts, isNull);
    },
  );

  test(
    'port filtering is exact and follows live local and remote samples',
    () async {
      final service = _createService(
        _FakeProcessRepository([
          _snapshot([
            _process(pid: 1, name: 'server').copyWith(localPorts: [8080]),
            _process(pid: 2, name: 'other').copyWith(localPorts: [80]),
            _process(pid: 3, name: '8080 in command'),
          ]),
          _snapshot([
            _process(pid: 1, name: 'server').copyWith(localPorts: [9090]),
            _process(pid: 2, name: 'other').copyWith(localPorts: [8080]),
            _process(pid: 3, name: '8080 in command'),
          ]),
        ]),
      );
      await service.refresh();
      service.setSearchAspect(ProcessSearchAspect.port);
      service.setFilter('8080');
      expect(service.tree.value.visibleRows.map((r) => r.record.pid), [1]);
      service.setFilter('80');
      expect(service.tree.value.visibleRows.map((r) => r.record.pid), [2]);
      service.setFilter('8080');
      await service.refresh();
      expect(service.tree.value.visibleRows.map((r) => r.record.pid), [2]);
      for (final invalid in ['0', '-1', '65536', '80x', '8.0']) {
        service.setFilter(invalid);
        expect(service.tree.value.visibleRows, isEmpty, reason: invalid);
      }
      service.setFilter('');
      expect(service.tree.value.visibleRows, hasLength(3));
    },
  );

  test('a typed port prefix or showPort applies only to its query', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'server').copyWith(localPorts: [8080]),
          _process(pid: 2, name: 'other').copyWith(localPorts: [80]),
        ]),
      ]),
    );
    await service.refresh();
    List<int> visible() =>
        service.tree.value.visibleRows.map((r) => r.record.pid).toList();

    service.setFilter(':8080');
    expect(service.searchOptions.value.aspect, ProcessSearchAspect.port);
    expect(service.filter.value, '8080');
    expect(visible(), [1]);
    service.setFilter('');
    expect(
      service.searchOptions.value.aspect,
      ProcessSearchAspect.all,
      reason: 'clearing the query ends the prefix-chosen aspect',
    );

    service.showPort(80);
    expect(service.searchOptions.value.aspect, ProcessSearchAspect.port);
    expect(service.filter.value, '80');
    expect(visible(), [2]);
    service.setFilter('server');
    expect(
      service.searchOptions.value.aspect,
      ProcessSearchAspect.all,
      reason: 'text that is no port ends a port search',
    );
    expect(visible(), [1]);

    service.setSearchAspect(ProcessSearchAspect.name);
    service.setFilter(':80');
    service.setFilter('');
    expect(
      service.searchOptions.value.aspect,
      ProcessSearchAspect.name,
      reason: 'the aspect chosen in the menu stays',
    );
  });

  test('a bare number in the default search also finds port users', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'server').copyWith(localPorts: [5432]),
          _process(pid: 5432, name: 'pid match'),
          _process(pid: 3, name: 'unrelated').copyWith(localPorts: [54321]),
        ]),
      ]),
    );
    await service.refresh();
    service.setFilter('5432');
    expect(
      service.tree.value.visibleRows.map((r) => r.record.pid),
      unorderedEquals([1, 5432]),
      reason: 'ports match exactly, so 54321 does not',
    );
  });

  test(
    'socket peers link loopback connections to the listening process',
    () async {
      NetworkEndpointInfo socket(String remote, int remotePort) =>
          NetworkEndpointInfo(
            protocol: 'TCP',
            localAddress: '127.0.0.1',
            localPort: 51000,
            localAddressApproximate: false,
            remoteAddress: remote,
            remotePort: remotePort,
            remoteAddressApproximate: false,
            state: 'Established',
          );
      final service = _createService(
        _FakeProcessRepository(
          [
            _snapshot([
              _process(
                pid: 1,
                name: 'client',
              ).copyWith(localPorts: [51000, 51001], listeningPorts: [9000]),
              _process(
                pid: 2,
                name: 'postgres',
              ).copyWith(localPorts: [5432], listeningPorts: [5432]),
              _process(
                pid: 3,
                name: 'web',
              ).copyWith(localPorts: [443], listeningPorts: [443]),
            ]),
          ],
          socketsByPid: {
            1: [
              socket('127.0.0.1', 5432),
              socket('93.184.216.34', 443),
              socket('::1', 9000),
            ],
          },
        ),
      );
      await service.refresh();
      service.selectProcess(_id(1));
      await Future<void>.delayed(Duration.zero);
      final owners = service.inspector.value.listenerOwnersByPort;
      expect(owners.keys, [
        5432,
      ], reason: 'remote hosts and the process itself are not peers');
      expect(owners[5432]!.single.name, 'postgres');
      expect(owners[5432]!.single.identity, _id(2));
    },
  );

  test('sorting by ports puts listeners first by port', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'none'),
          _process(
            pid: 2,
            name: 'browser',
          ).copyWith(localPorts: [50000, 50001]),
          _process(
            pid: 3,
            name: 'web',
          ).copyWith(localPorts: [80, 50002], listeningPorts: [80]),
          _process(
            pid: 4,
            name: 'db',
          ).copyWith(localPorts: [5432], listeningPorts: [5432]),
          _process(pid: 5, name: 'client').copyWith(localPorts: [50003]),
        ]),
      ]),
    );
    await service.refresh();
    service.sortBy(ProcessSortColumn.ports);
    expect(service.tree.value.sortDirection, ProcessSortDirection.ascending);
    expect(service.tree.value.visibleRows.map((r) => r.record.pid), [
      3,
      4,
      2,
      5,
      1,
    ]);
  });

  test(
    'saved aspect filters restore and port snapshots retain their data',
    () async {
      final service = _createService(
        _FakeProcessRepository([
          _snapshot([
            _process(
              pid: 1,
              uid: 42,
              name: 'server',
            ).copyWith(localPorts: [53, 8080]),
          ]),
        ]),
      );
      await service.refresh();
      service.setFilter('port:8080');
      expect(service.searchOptions.value.aspect, ProcessSearchAspect.port);
      expect(service.filter.value, '8080');
      expect(service.tree.value.visibleRows, hasLength(1));
      final saved = service.searchOptions.value.savedQuery(
        service.filter.value,
      );
      service.setSearchAspect(ProcessSearchAspect.name);
      expect(service.tree.value.visibleRows, isEmpty);
      service.setFilter(saved);
      expect(service.tree.value.visibleRows, hasLength(1));
      service.setFilter('user:42');
      expect(service.tree.value.visibleRows, hasLength(1));
      service.setFilter('user:server');
      expect(service.tree.value.visibleRows, isEmpty);
      final restored = ProcessSnapshot.fromJson(
        service.snapshot.value.toJson(),
      );
      expect(restored.processes.single.localPorts, [53, 8080]);
    },
  );

  test(
    'native structure stays frozen through reparenting and resumes on unlock',
    () async {
      final initial = ProcessTopology(
        version: 1,
        parents: {_id(1): null, _id(2): _id(1)},
      );
      final reparented = ProcessTopology(
        version: 2,
        parents: {_id(1): null, _id(2): null},
      );
      final service = _createService(
        _FakeProcessRepository([
          _snapshot([
            _process(pid: 1, name: 'root'),
            _process(pid: 2, ppid: 1, name: 'child', cpuUsage: 1),
          ], topology: initial),
          _snapshot([
            _process(pid: 1, name: 'root'),
            _process(pid: 2, name: 'child', cpuUsage: 9),
          ], topology: reparented),
        ]),
      );
      await service.refresh();
      expect(
        service.tree.value.visibleRows
            .firstWhere((r) => r.record.pid == 2)
            .depth,
        1,
      );
      service.setFrozen(true);
      await service.refresh();
      final frozen = service.tree.value.visibleRows.firstWhere(
        (r) => r.record.pid == 2,
      );
      expect(frozen.depth, 1);
      expect(frozen.record.cpuUsage, 9);
      final saved = ProcessSnapshot.fromJson(service.snapshot.value.toJson());
      expect(saved.processes.firstWhere((r) => r.pid == 2).ppid, 1);
      expect(service.tree.value.lock.hasQueuedStructuralMutations, isTrue);
      service.setFrozen(false);
      expect(
        service.tree.value.visibleRows
            .firstWhere((r) => r.record.pid == 2)
            .depth,
        0,
      );
    },
  );

  test('native topology returns after exited-row overlay expires', () async {
    final initial = ProcessTopology(
      version: 1,
      parents: {_id(1): null, _id(2): _id(1)},
    );
    final remaining = ProcessTopology(version: 2, parents: {_id(1): null});
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'root'),
          _process(pid: 2, ppid: 1, name: 'child'),
        ], topology: initial),
        _snapshot([_process(pid: 1, name: 'root')], topology: remaining),
      ]),
    );
    await service.refresh();
    await service.refresh();
    expect(
      service.tree.value.visibleRows
          .where((r) => r.isTerminated)
          .single
          .identity,
      _id(2),
    );
    await service.refresh();
    expect(service.tree.value.visibleRows.single.identity, _id(1));
    expect(service.tree.value.visibleRows.single.hasChildren, isFalse);
  });

  test(
    'metric refresh keeps sorting live and invalidates reparented topology',
    () async {
      final service = _createService(
        _FakeProcessRepository([
          _snapshot([
            _process(pid: 1, name: 'root'),
            _process(pid: 2, ppid: 1, name: 'child', cpuUsage: 10),
            _process(pid: 3, ppid: 1, name: 'sibling', cpuUsage: 20),
          ]),
          _snapshot([
            _process(pid: 3, ppid: 1, name: 'sibling', cpuUsage: 5),
            _process(pid: 2, ppid: 1, name: 'child', cpuUsage: 30),
            _process(pid: 1, name: 'root'),
          ]),
          _snapshot([
            _process(pid: 1, name: 'root'),
            _process(pid: 2, name: 'child', cpuUsage: 40),
            _process(pid: 3, ppid: 1, name: 'sibling', cpuUsage: 5),
          ]),
        ]),
      );
      await service.refresh();
      service.sortBy(ProcessSortColumn.cpu);
      expect(service.tree.value.visibleRows.map((r) => r.record.pid), [
        1,
        3,
        2,
      ]);
      await service.refresh();
      expect(service.tree.value.visibleRows.map((r) => r.record.pid), [
        1,
        2,
        3,
      ]);
      expect(service.tree.value.visibleRows.first.treeCpuUsage, 35);
      await service.refresh();
      final child = service.tree.value.visibleRows.firstWhere(
        (r) => r.record.pid == 2,
      );
      expect(child.depth, 0);
      expect(child.cpuHistory, [10, 30, 40]);
      expect(
        service.tree.value.visibleRows
            .firstWhere((r) => r.record.pid == 1)
            .treeCpuUsage,
        5,
      );
    },
  );

  test(
    'interaction publications reuse immutable history until the next sample',
    () async {
      final service = _createService(
        _FakeProcessRepository([
          _snapshot([_process(pid: 1, name: 'root', cpuUsage: 10)]),
          _snapshot([_process(pid: 1, name: 'root', cpuUsage: 20)]),
        ]),
      );
      await service.refresh();
      final history = service.tree.value.visibleRows.single.cpuHistory;
      service.togglePin(_id(1));
      expect(
        identical(service.tree.value.visibleRows.single.cpuHistory, history),
        isTrue,
      );
      expect(() => history.add(99), throwsUnsupportedError);
      await service.refresh();
      expect(history, [10]);
      expect(service.tree.value.visibleRows.single.cpuHistory, [10, 20]);
    },
  );

  test('refresh stores latest process snapshot', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([_process(pid: 1, name: 'launchd')]),
      ]),
    );

    await service.refresh();

    expect(service.snapshot.value.processes, hasLength(1));
    expect(service.snapshot.value.processes.single.name, 'launchd');
  });

  test('refresh records repository operation', () async {
    final tracker = RepositoryOperationTrackerImpl();
    final service = _service(
      processRepository: _FakeProcessRepository([
        _snapshot([_process(pid: 1, name: 'launchd')]),
      ]),
      snapshotRepository: _FakeSnapshotRepository(),
      repositoryOperationTracker: tracker,
    );

    await service.refresh();

    expect(tracker.getOperationStats()['ProcessRepository.fetchSnapshot'], 1);
  });

  test('does not refresh process data while the window is resizing', () async {
    final repository = _FakeProcessRepository([
      _snapshot([_process(pid: 1, name: 'systemd')]),
    ]);
    final service = _createService(repository);

    service.setWindowResizing(true);
    await service.refresh();

    expect(repository.fetchCount, 0);
    expect(service.snapshot.value.processes, isEmpty);

    service.setWindowResizing(false);
    await service.refresh();

    expect(repository.fetchCount, 1);
    expect(service.snapshot.value.processes, hasLength(1));
  });

  test('synthesizes a stable parent child process tree', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'WindowServer'),
          _process(pid: 3, ppid: 2, name: 'Dock'),
        ]),
      ]),
    );

    await service.refresh();
    service.toggleExpansion(_id(2));

    expect(service.tree.value.visibleRows.map((row) => row.record.name), [
      'launchd',
      'WindowServer',
      'Dock',
    ]);
    expect(service.tree.value.visibleRows.map((row) => row.depth), [0, 1, 2]);
  });

  test('expands the systemd user-manager branch by default on Linux', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'systemd'),
          _process(pid: 1000, ppid: 1, name: 'systemd'),
          _process(pid: 1001, ppid: 1000, name: 'plasmashell'),
        ]),
      ]),
      platform: TargetPlatform.linux,
    );

    await service.refresh();

    expect(service.tree.value.visibleRows.map((row) => row.record.name), [
      'systemd',
      'systemd',
      'plasmashell',
    ]);
    expect(
      service.tree.value.expandedIdentities,
      containsAll([_id(1), _id(1000)]),
    );
  });

  test('search preserves ancestor branches and matching descendants', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'WindowServer'),
          _process(pid: 3, ppid: 2, name: 'Dock'),
          _process(pid: 4, ppid: 1, name: 'Safari'),
        ]),
      ]),
    );

    await service.refresh();
    service.setFilter('dock');

    final rows = service.tree.value.visibleRows;
    expect(rows.map((row) => row.record.name), [
      'launchd',
      'WindowServer',
      'Dock',
    ]);
    expect(rows[0].preservesFilterBranch, isTrue);
    expect(rows[1].preservesFilterBranch, isTrue);
    expect(rows[2].matchesFilter, isTrue);
    expect(rows[0].isExpanded, isTrue);
    expect(rows[1].isExpanded, isTrue);
  });

  test('search can match case sensitively', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'Dock'),
          _process(pid: 2, name: 'dock-helper'),
        ]),
      ]),
    );

    await service.refresh();
    service.setFilter('dock');

    expect(
      service.tree.value.visibleRows.map((row) => row.record.name),
      containsAll(['Dock', 'dock-helper']),
    );

    service.setSearchMatchCase(true);

    expect(service.tree.value.visibleRows.map((row) => row.record.name), [
      'dock-helper',
    ]);
  });

  test('search can require whole word matches', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'Dock'),
          _process(pid: 2, name: 'DockHelper'),
          _process(pid: 3, name: 'Dock helper'),
        ]),
      ]),
    );

    await service.refresh();
    service.setFilter('Dock');
    service.setSearchWholeWord(true);

    expect(
      service.tree.value.visibleRows.map((row) => row.record.name),
      containsAll(['Dock', 'Dock helper']),
    );
    expect(
      service.tree.value.visibleRows.map((row) => row.record.name),
      isNot(contains('DockHelper')),
    );
  });

  test('tree search highlights matches without filtering rows', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'Dock'),
          _process(pid: 3, ppid: 1, name: 'Safari'),
        ]),
      ]),
    );

    await service.refresh();
    service.setTreeSearch('saf');

    final rows = service.tree.value.visibleRows;
    expect(rows.map((row) => row.record.name), ['launchd', 'Dock', 'Safari']);
    expect(
      rows.where((row) => row.matchesTreeSearch).map((row) => row.record.name),
      ['Safari'],
    );
    expect(service.tree.value.treeSearchQuery, 'saf');
    expect(service.tree.value.treeSearchMatchCount, 1);
    expect(service.tree.value.treeSearchSelectedMatchIndex, 0);
    expect(service.tree.value.selectedIdentity, _id(3));
  });

  test('tree rows label bundled helper processes by executable name', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(
            pid: 1,
            name: 'Xcode',
            executablePath:
                '/Applications/Xcode.app/Contents/Developer/usr/bin/git',
            commandLine:
                '/Applications/Xcode.app/Contents/Developer/usr/bin/git pull',
            appBundlePath: '/Applications/Xcode.app',
          ),
          _process(
            pid: 2,
            name: 'Xcode',
            executablePath: '/Applications/Xcode.app/Contents/MacOS/Xcode',
            appBundlePath: '/Applications/Xcode.app',
          ),
          _process(
            pid: 3,
            name: 'Example App',
            executablePath:
                '/Applications/Example App.app/Contents/MacOS/launcher',
            appBundlePath: '/Applications/Example App.app',
          ),
        ]),
      ]),
    );

    await service.refresh();

    expect(
      service.tree.value.visibleRows.map((row) => row.record.displayName),
      ['git', 'Xcode', 'Example App'],
    );
  });

  test('search matches bundled helper process executable labels', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(
            pid: 1,
            name: 'Xcode',
            executablePath:
                '/Applications/Xcode.app/Contents/Developer/usr/bin/git',
            appBundlePath: '/Applications/Xcode.app',
          ),
          _process(
            pid: 2,
            name: 'Xcode',
            executablePath: '/Applications/Xcode.app/Contents/MacOS/Xcode',
            appBundlePath: '/Applications/Xcode.app',
          ),
        ]),
      ]),
    );

    await service.refresh();
    service.setFilter('git');

    expect(service.tree.value.visibleRows.single.record.displayName, 'git');
  });

  test('tree search only searches visible stable columns', () async {
    final settingsService = _FakeSettingsService(
      const AppSettings(visibleColumns: <String>['name', 'pid']),
    );
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'launchd', uid: 501),
          _process(pid: 2, ppid: 1, name: 'Dock', uid: 502),
        ]),
      ]),
      settingsService: settingsService,
    );

    await service.initialize();
    await service.refresh();
    service.setTreeSearch('502');

    expect(service.tree.value.treeSearchMatchCount, 0);
    expect(service.tree.value.visibleRows.map((row) => row.record.name), [
      'launchd',
      'Dock',
    ]);

    await settingsService.updateVisibleColumns(<String>['name', 'pid', 'uid']);

    expect(service.tree.value.treeSearchMatchCount, 1);
    expect(
      service.tree.value.visibleRows
          .singleWhere((row) => row.record.name == 'Dock')
          .treeSearchMatchedColumnIds,
      contains('uid'),
    );
  });

  test('tree search navigation cycles through highlighted rows', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'Safari'),
          _process(pid: 3, ppid: 1, name: 'Safari Web Content'),
        ]),
      ]),
    );

    await service.refresh();
    service.setTreeSearch('safari');

    expect(service.tree.value.selectedIdentity, _id(2));
    expect(service.tree.value.treeSearchSelectedMatchIndex, 0);

    service.selectNextTreeSearchMatch();
    expect(service.tree.value.selectedIdentity, _id(3));
    expect(service.tree.value.treeSearchSelectedMatchIndex, 1);

    service.selectNextTreeSearchMatch();
    expect(service.tree.value.selectedIdentity, _id(2));
    expect(service.tree.value.treeSearchSelectedMatchIndex, 0);

    service.selectPreviousTreeSearchMatch();
    expect(service.tree.value.selectedIdentity, _id(3));
    expect(service.tree.value.treeSearchSelectedMatchIndex, 1);
  });

  test('selection survives metric only refresh by process identity', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'Dock', rssBytes: 1024),
        ]),
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'Dock', rssBytes: 4096),
        ], generatedAtUnixMs: 2),
      ]),
    );

    await service.refresh();
    service.selectProcess(_id(2));
    final selectedRow = service.tree.value.selectedRow;

    await service.refresh();

    expect(service.tree.value.selectedIdentity, _id(2));
    expect(service.tree.value.selectedProcess?.rssBytes, 4096);
    expect(identical(service.tree.value.selectedRow, selectedRow), isFalse);
  });

  test('selection publishes tree and selected identity', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'Dock'),
        ]),
      ]),
    );

    await service.refresh();
    var treeNotifications = 0;
    var selectionNotifications = 0;
    service.tree.addListener(() => treeNotifications++);
    service.selectedIdentity.addListener(() => selectionNotifications++);

    service.selectProcess(_id(2));

    expect(treeNotifications, greaterThanOrEqualTo(1));
    expect(selectionNotifications, 1);
    expect(service.tree.value.selectedIdentity, _id(2));
    expect(service.tree.value.selectedRow?.record.name, 'Dock');
    expect(service.inspector.value.process?.name, 'Dock');
  });

  test('preserves repository cpu usage', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([_process(pid: 1, name: 'launchd', cpuUsage: 50)]),
      ]),
    );

    await service.refresh();

    expect(service.tree.value.visibleRows.single.record.cpuUsage, 50);
  });

  test('sorts sibling branches by tree cpu usage', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'Dock', cpuUsage: 10),
          _process(pid: 3, ppid: 2, name: 'Dock helper', cpuUsage: 70),
          _process(pid: 4, ppid: 1, name: 'Safari', cpuUsage: 30),
        ]),
      ]),
    );

    await service.refresh();
    service.toggleExpansion(_id(2));

    expect(service.tree.value.visibleRows.map((row) => row.record.name), [
      'launchd',
      'Dock',
      'Dock helper',
      'Safari',
    ]);
    expect(
      service.tree.value.visibleRows
          .singleWhere((row) => row.record.name == 'Dock')
          .treeCpuUsage,
      80,
    );
    expect(service.tree.value.sortColumn, ProcessSortColumn.treeCpu);
    expect(service.tree.value.sortDirection, ProcessSortDirection.descending);
  });

  test('computes tree rss gpu and network aggregates', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(
            pid: 1,
            name: 'parent',
            rssBytes: 100,
            gpuUsage: 3,
            networkInBytesPerSecond: 10,
            networkOutBytesPerSecond: 2,
          ),
          _process(
            pid: 2,
            ppid: 1,
            name: 'child',
            rssBytes: 900,
            gpuUsage: 7,
            networkInBytesPerSecond: 90,
            networkOutBytesPerSecond: 8,
          ),
        ]),
      ]),
    );

    await service.refresh();

    final parent = service.tree.value.visibleRows.first;
    expect(parent.treeRssBytes, 1000);
    expect(parent.treeGpuUsage, 10);
    expect(parent.treeNetworkInBytesPerSecond, 100);
    expect(parent.treeNetworkOutBytesPerSecond, 10);
  });

  test('records separate process and tree metric histories', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'parent', rssBytes: 100),
          _process(pid: 2, ppid: 1, name: 'child', rssBytes: 900),
        ]),
      ]),
    );

    await service.refresh();
    service.selectProcess(_id(1));

    final parent = service.tree.value.visibleRows.first;
    expect(parent.processRssHistory, hasLength(1));
    expect(parent.processRssHistory.last, 100);
    expect(parent.rssHistory.last, 1000);
  });

  test('aggregates partial subtree storage and records histories', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'parent'),
          _process(
            pid: 2,
            ppid: 1,
            name: 'child',
            storageReadBytesPerSecond: 4096,
            storageWriteBytesPerSecond: 2048,
            storageIoAvailable: true,
          ),
        ]),
      ]),
    );

    await service.refresh();
    service.selectProcess(_id(1));

    final parent = service.tree.value.visibleRows.first;
    expect(parent.record.storageIoAvailable, isFalse);
    expect(parent.treeStorageIoAvailable, isTrue);
    expect(parent.treeStorageReadBytesPerSecond, 4096);
    expect(parent.treeStorageWriteBytesPerSecond, 2048);
    expect(parent.storageReadHistory.last, 4096);
    expect(parent.storageWriteHistory.last, 2048);
    expect(parent.processStorageReadHistory.last, 0);
  });

  test('publishes resolved process icon paths on tree rows', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'Finder', iconUri: 'file:///tmp/finder.png'),
        ]),
      ]),
    );

    await service.refresh();

    expect(
      service.tree.value.visibleRows.single.iconPath,
      'file:///tmp/finder.png',
    );
  });

  test(
    'publishes asynchronously resolved Linux application metadata',
    () async {
      final identity = _id(1);
      final service = _createService(
        _FakeProcessRepository([
          _snapshot([
            _process(
              pid: identity.pid,
              name: 'code',
              executablePath: '/usr/share/code/code',
              appBundlePath: '/usr/share/code/code',
            ),
          ]),
          _snapshot([
            _process(
              pid: identity.pid,
              name: 'Visual Studio Code',
              executablePath: '/usr/share/code/code',
              appBundlePath: '/usr/share/code/code',
              iconUri: 'file:///usr/share/pixmaps/vscode.png',
            ),
          ]),
        ]),
      );

      await service.refresh();
      expect(service.tree.value.visibleRows.single.record.displayName, 'code');

      await service.refresh();
      final row = service.tree.value.visibleRows.single;
      expect(row.record.displayName, 'Visual Studio Code');
      expect(row.iconPath, 'file:///usr/share/pixmaps/vscode.png');
    },
  );

  test('sorts sibling branches by tree network rate', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'low'),
          _process(
            pid: 3,
            ppid: 1,
            name: 'high parent',
            networkInBytesPerSecond: 5,
          ),
          _process(
            pid: 4,
            ppid: 3,
            name: 'high child',
            networkInBytesPerSecond: 995,
          ),
        ]),
      ]),
    );

    await service.refresh();
    service.sortBy(ProcessSortColumn.treeNetworkIn);
    service.toggleExpansion(_id(3));

    expect(service.tree.value.visibleRows.map((row) => row.record.name), [
      'launchd',
      'high parent',
      'high child',
      'low',
    ]);
  });

  test('keeps visible tree order stable while interacted with', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'alpha', rssBytes: 1000),
          _process(pid: 3, ppid: 1, name: 'beta', rssBytes: 500),
        ]),
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'alpha', rssBytes: 100),
          _process(pid: 3, ppid: 1, name: 'beta', rssBytes: 5000),
        ], generatedAtUnixMs: 2),
      ]),
    );

    await service.refresh();
    service.sortBy(ProcessSortColumn.memory);
    expect(service.tree.value.visibleRows.map((row) => row.record.name), [
      'launchd',
      'alpha',
      'beta',
    ]);

    service.setTreeHovering(true);
    await service.refresh();

    expect(service.tree.value.isOrderLockedByInteraction, isTrue);
    expect(service.tree.value.visibleRows.map((row) => row.record.name), [
      'launchd',
      'alpha',
      'beta',
    ]);
    expect(
      service.tree.value.visibleRows
          .singleWhere((row) => row.record.name == 'beta')
          .record
          .rssBytes,
      5000,
    );

    service.setTreeHovering(false);

    expect(
      service.tree.value.isOrderLockedByInteraction,
      isTrue,
      reason: 'release is intentionally debounced to bridge hover handoffs',
    );

    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(service.tree.value.isOrderLockedByInteraction, isFalse);
    expect(service.tree.value.visibleRows.map((row) => row.record.name), [
      'launchd',
      'beta',
      'alpha',
    ]);
  });

  test(
    'keyboard navigation temporarily keeps visible tree order stable',
    () async {
      final service = _createService(
        _FakeProcessRepository([
          _snapshot([
            _process(pid: 1, name: 'launchd'),
            _process(pid: 2, ppid: 1, name: 'alpha', rssBytes: 1000),
            _process(pid: 3, ppid: 1, name: 'beta', rssBytes: 500),
          ]),
          _snapshot([
            _process(pid: 1, name: 'launchd'),
            _process(pid: 2, ppid: 1, name: 'alpha', rssBytes: 100),
            _process(pid: 3, ppid: 1, name: 'beta', rssBytes: 5000),
          ], generatedAtUnixMs: 2),
        ]),
      );

      await service.refresh();
      service.sortBy(ProcessSortColumn.memory);
      service.selectNextVisible();
      await service.refresh();

      expect(service.tree.value.isOrderLockedByInteraction, isTrue);
      expect(service.tree.value.visibleRows.map((row) => row.record.name), [
        'launchd',
        'alpha',
        'beta',
      ]);
    },
  );

  for (final contextMenu in [false, true]) {
    test(
      '${contextMenu ? 'context menu' : 'modal overlay'} keeps visible tree order stable without hovering',
      () async {
        final service = _createService(
          _FakeProcessRepository([
            _snapshot([
              _process(pid: 1, name: 'launchd'),
              _process(pid: 2, ppid: 1, name: 'alpha', rssBytes: 1000),
              _process(pid: 3, ppid: 1, name: 'beta', rssBytes: 500),
            ]),
            _snapshot([
              _process(pid: 1, name: 'launchd'),
              _process(pid: 2, ppid: 1, name: 'alpha', rssBytes: 100),
              _process(pid: 3, ppid: 1, name: 'beta', rssBytes: 5000),
            ], generatedAtUnixMs: 2),
          ]),
        );

        await service.refresh();
        service.sortBy(ProcessSortColumn.memory);
        service.setTreeHovering(true);
        await service.refresh();
        expect(service.tree.value.isOrderLockedByInteraction, isTrue);

        final setOverlayOpen = contextMenu
            ? service.setTreeContextMenuOpen
            : service.setModalOverlayOpen;
        setOverlayOpen(true);
        // Pointer leaves the tree toward the menu or dialog.
        service.setTreeHovering(false);

        expect(service.tree.value.isOrderLockedByInteraction, isTrue);
        expect(service.tree.value.visibleRows.map((row) => row.record.name), [
          'launchd',
          'alpha',
          'beta',
        ]);

        await service.refresh();

        // Ordering stays frozen while the overlay is open with new metrics.
        expect(service.tree.value.isOrderLockedByInteraction, isTrue);
        expect(service.tree.value.visibleRows.map((row) => row.record.name), [
          'launchd',
          'alpha',
          'beta',
        ]);

        setOverlayOpen(false);

        expect(
          service.tree.value.isOrderLockedByInteraction,
          isTrue,
          reason: 'closing the overlay starts the deferred release window',
        );

        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(service.tree.value.isOrderLockedByInteraction, isFalse);
        expect(service.tree.value.visibleRows.map((row) => row.record.name), [
          'launchd',
          'beta',
          'alpha',
        ]);
      },
    );
  }

  test('pins and unpins selected process identities', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'Dock'),
        ]),
      ]),
    );

    await service.refresh();
    service.togglePin(_id(2));

    expect(service.tree.value.pinnedIdentities, contains(_id(2)));

    service.togglePin(_id(2));

    expect(service.tree.value.pinnedIdentities, isNot(contains(_id(2))));
  });

  test('process actions are routed through process repository', () async {
    final repository = _FakeProcessRepository([
      _snapshot([
        _process(pid: 1, name: 'launchd'),
        _process(pid: 2, ppid: 1, name: 'Dock'),
      ]),
    ]);
    final tracker = RepositoryOperationTrackerImpl();
    final service = _service(
      processRepository: repository,
      snapshotRepository: _FakeSnapshotRepository(),
      repositoryOperationTracker: tracker,
    );

    await service.refresh();
    await service.terminateProcess(_id(2));
    await service.killProcess(_id(2));
    await service.suspendProcess(_id(2));
    await service.resumeProcess(_id(2));

    expect(repository.signals, [
      (_id(2), ProcessSignal.terminate),
      (_id(2), ProcessSignal.kill),
      (_id(2), ProcessSignal.suspend),
      (_id(2), ProcessSignal.resume),
    ]);
    expect(tracker.getOperationStats()['ProcessRepository.sendSignal'], 4);
  });

  test('focuses and clears a selected subtree', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'Dock'),
          _process(pid: 3, ppid: 2, name: 'Dock helper'),
          _process(pid: 4, ppid: 1, name: 'Safari'),
        ]),
      ]),
    );

    await service.refresh();
    service.focusSubtree(_id(2));

    expect(service.tree.value.isSubtreeFocused, isTrue);
    expect(service.tree.value.focusedIdentity, _id(2));
    expect(service.tree.value.focusedProcessName, 'Dock');
    expect(service.tree.value.visibleRows.map((row) => row.record.name), [
      'Dock',
      'Dock helper',
    ]);
    expect(service.tree.value.visibleRows.first.depth, 0);

    service.clearSubtreeFocus();

    expect(service.tree.value.isSubtreeFocused, isFalse);
    expect(service.tree.value.visibleRows.map((row) => row.record.name), [
      'launchd',
      'Dock',
      'Dock helper',
      'Safari',
    ]);
  });

  test('nested subtree focus can step back one level', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'parent'),
          _process(pid: 3, ppid: 2, name: 'child'),
          _process(pid: 4, ppid: 3, name: 'grandchild'),
        ]),
      ]),
    );

    await service.refresh();
    service.focusSubtree(_id(2));
    service.focusSubtree(_id(3));

    expect(service.tree.value.focusedIdentity, _id(3));
    expect(service.tree.value.focusStack, [_id(2)]);
    expect(service.tree.value.visibleRows.map((row) => row.record.name), [
      'child',
      'grandchild',
    ]);

    service.popSubtreeFocus();

    expect(service.tree.value.focusedIdentity, _id(2));
    expect(service.tree.value.focusStack, isEmpty);
    expect(service.tree.value.visibleRows.map((row) => row.record.name), [
      'parent',
      'child',
      'grandchild',
    ]);
  });

  test('structural refresh reports spawned and terminated markers', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'Dock'),
        ]),
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 3, ppid: 1, name: 'Safari'),
        ], generatedAtUnixMs: 2),
      ]),
    );

    await service.refresh();
    await service.refresh();

    final markers = {
      for (final row in service.tree.value.visibleRows)
        row.record.name: row.changeMarker,
    };
    expect(markers['Safari'], ProcessChangeMarker.spawned);
    expect(markers['Dock'], ProcessChangeMarker.terminated);
  });

  test('freeze keeps the visible order while metrics change', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'Dock', cpuUsage: 40),
          _process(pid: 3, ppid: 1, name: 'Safari', cpuUsage: 10),
        ]),
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'Dock', cpuUsage: 5),
          _process(pid: 3, ppid: 1, name: 'Safari', cpuUsage: 60),
        ], generatedAtUnixMs: 2),
      ]),
    );
    List<String> names() =>
        service.tree.value.visibleRows.map((row) => row.record.name).toList();

    await service.refresh();
    expect(names(), ['launchd', 'Dock', 'Safari']);

    service.setFrozen(true);
    await service.refresh();

    // Values update, the order does not.
    expect(names(), ['launchd', 'Dock', 'Safari']);
    expect(service.tree.value.visibleRows.last.record.cpuUsage, 60);

    service.setFrozen(false);
    expect(names(), ['launchd', 'Safari', 'Dock']);
  });

  test('freeze queues structural mutations but keeps metric updates', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'Dock', rssBytes: 1024),
        ]),
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'Dock', rssBytes: 2048),
          _process(pid: 3, ppid: 1, name: 'Safari'),
        ], generatedAtUnixMs: 2),
      ]),
    );

    await service.refresh();
    service.setFrozen(true);
    await service.refresh();

    expect(service.tree.value.isFrozen, isTrue);
    expect(service.tree.value.hasQueuedStructuralMutations, isTrue);
    expect(service.tree.value.visibleRows.map((row) => row.record.name), [
      'launchd',
      'Dock',
    ]);
    expect(service.tree.value.visibleRows.last.record.rssBytes, 2048);

    service.setFrozen(false);

    expect(service.tree.value.isFrozen, isFalse);
    expect(service.tree.value.visibleRows.map((row) => row.record.name), [
      'launchd',
      'Dock',
      'Safari',
    ]);
    expect(
      service.tree.value.visibleRows
          .singleWhere((row) => row.record.name == 'Safari')
          .changeMarker,
      ProcessChangeMarker.spawned,
    );
  });

  test('publishes inspector state for selected process', () async {
    final service = _createService(
      _FakeProcessRepository([
        _snapshot([
          _process(pid: 1, name: 'launchd'),
          _process(pid: 2, ppid: 1, name: 'Dock'),
        ], platform: 'macos'),
      ]),
    );

    await service.refresh();
    service.selectProcess(_id(2));
    await Future<void>.delayed(Duration.zero);

    expect(service.inspector.value.process?.name, 'Dock');
    expect(
      service.inspector.value.overview.availability,
      InspectorAvailability.available,
    );
    expect(
      service.inspector.value.threads.availability,
      InspectorAvailability.available,
    );
  });

  test('takes and loads snapshots through snapshot repository', () async {
    final snapshotRepository = _FakeSnapshotRepository();
    final service = _service(
      processRepository: _FakeProcessRepository([
        _snapshot([_process(pid: 1, name: 'launchd')]),
      ]),
      snapshotRepository: snapshotRepository,
      repositoryOperationTracker: RepositoryOperationTrackerImpl(),
    );

    await service.refresh();
    await service.takeSnapshot();
    await service.loadSnapshot('/tmp/snapshot.processlama-snapshot.json');

    expect(service.snapshot.value.processes.single.name, 'launchd');
    expect(service.savedSnapshots.value, hasLength(1));
    expect(service.savedSnapshots.value.single.processCount, 1);
  });

  test('renames snapshots through snapshot repository', () async {
    final snapshotRepository = _FakeSnapshotRepository();
    final service = _service(
      processRepository: _FakeProcessRepository([
        _snapshot([_process(pid: 1, name: 'launchd')]),
      ]),
      snapshotRepository: snapshotRepository,
      repositoryOperationTracker: RepositoryOperationTrackerImpl(),
    );

    await service.refresh();
    await service.takeSnapshot();
    final entry = service.savedSnapshots.value.single;
    await service.renameSnapshot(entry, 'Incident baseline');

    expect(service.savedSnapshots.value.single.name, 'Incident baseline');
  });

  test('loading external snapshot imports it into saved snapshots', () async {
    final snapshotRepository = _FakeSnapshotRepository();
    snapshotRepository.externalSnapshot = _snapshot([
      _process(pid: 7, name: 'external'),
    ]);
    final service = _service(
      processRepository: _FakeProcessRepository([
        _snapshot([_process(pid: 1, name: 'live')]),
      ]),
      snapshotRepository: snapshotRepository,
      repositoryOperationTracker: RepositoryOperationTrackerImpl(),
    );

    await service.loadSnapshot('/tmp/exported.processlama-snapshot.json');

    expect(service.snapshot.value.processes.single.name, 'external');
    expect(
      service.loadedSnapshotPath.value,
      '/tmp/imported.processlama-snapshot.json',
    );
    expect(service.savedSnapshots.value, hasLength(1));
    expect(
      service.savedSnapshots.value.single.path,
      '/tmp/imported.processlama-snapshot.json',
    );
  });

  test('loaded snapshot stays static until live mode is selected', () async {
    final snapshotRepository = _FakeSnapshotRepository();
    final service = _service(
      processRepository: _FakeProcessRepository([
        _snapshot([_process(pid: 1, name: 'saved')]),
        _snapshot([_process(pid: 2, name: 'live')], generatedAtUnixMs: 2),
      ]),
      snapshotRepository: snapshotRepository,
      repositoryOperationTracker: RepositoryOperationTrackerImpl(),
    );

    await service.refresh();
    await service.takeSnapshot();
    await service.loadSnapshot('/tmp/snapshot.processlama-snapshot.json');
    await service.refresh();

    expect(service.loadedSnapshotPath.value, isNotNull);
    expect(service.snapshot.value.processes.single.name, 'saved');

    await service.showLiveSnapshot();

    expect(service.loadedSnapshotPath.value, isNull);
    expect(service.snapshot.value.processes.single.name, 'live');
  });

  test('deleting loaded snapshot returns to live mode', () async {
    final snapshotRepository = _FakeSnapshotRepository();
    final service = _service(
      processRepository: _FakeProcessRepository([
        _snapshot([_process(pid: 1, name: 'saved')]),
        _snapshot([_process(pid: 2, name: 'live')], generatedAtUnixMs: 2),
      ]),
      snapshotRepository: snapshotRepository,
      repositoryOperationTracker: RepositoryOperationTrackerImpl(),
    );

    await service.refresh();
    await service.takeSnapshot();
    final entry = service.savedSnapshots.value.single;
    await service.loadSnapshot(entry.path);

    await service.deleteSnapshot(entry);

    expect(service.loadedSnapshotPath.value, isNull);
    expect(service.savedSnapshots.value, isEmpty);
    expect(service.snapshot.value.processes.single.name, 'live');
  });
}

ProcessServiceImpl _service({
  required ProcessRepository processRepository,
  required SnapshotRepository snapshotRepository,
  required RepositoryOperationTracker repositoryOperationTracker,
  SettingsService? settingsService,
  TargetPlatform? platform,
}) {
  switch (_source) {
    case _Source.local:
      return ProcessServiceImpl(
        processRepository: processRepository,
        snapshotRepository: snapshotRepository,
        repositoryOperationTracker: repositoryOperationTracker,
        settingsService: settingsService,
        platform: platform,
      );
    case _Source.remote:
      final source = WireLoopbackRemoteSource(
        repository: processRepository,
        tracker: repositoryOperationTracker,
        platform: platform,
      );
      final session = ProcessSession(
        source: source,
        snapshotRepository: snapshotRepository,
        repositoryOperationTracker: repositoryOperationTracker,
        settingsService: settingsService,
        iconResolver: source.iconResolver,
      );
      return ProcessServiceImpl.overSessions(
        activeSession: ValueNotifier(session),
        initializer: session.initialize,
      );
  }
}

ProcessServiceImpl _createService(
  ProcessRepository repository, {
  SettingsService? settingsService,
  TargetPlatform? platform,
}) {
  return _service(
    processRepository: repository,
    snapshotRepository: _FakeSnapshotRepository(),
    repositoryOperationTracker: RepositoryOperationTrackerImpl(),
    settingsService: settingsService,
    platform: platform,
  );
}

ProcessSnapshot _snapshot(
  List<ProcessRecord> processes, {
  int generatedAtUnixMs = 1,
  String platform = 'test',
  ProcessTopology? topology,
}) {
  return ProcessSnapshot(
    generatedAtUnixMs: generatedAtUnixMs,
    topology: topology,
    platform: platform,
    processes: processes,
  );
}

ProcessRecord _process({
  required int pid,
  int ppid = 0,
  int uid = 0,
  int startTimeUnixMs = 1000,
  int rssBytes = 1024,
  int cpuTimeNanos = 0,
  double cpuUsage = 0,
  double gpuUsage = 0,
  double networkInBytesPerSecond = 0,
  double networkOutBytesPerSecond = 0,
  double storageReadBytesPerSecond = 0,
  double storageWriteBytesPerSecond = 0,
  bool storageIoAvailable = false,
  String? iconUri,
  String? executablePath,
  String? commandLine,
  String appBundlePath = '',
  required String name,
}) {
  final resolvedExecutablePath = executablePath ?? '/bin/$name';
  return ProcessRecord(
    pid: pid,
    ppid: ppid,
    uid: uid,
    user: uid.toString(),
    status: ProcessStatus.running,
    rssBytes: rssBytes,
    virtualMemoryBytes: rssBytes,
    cpuTimeNanos: cpuTimeNanos,
    threadCount: 0,
    openFileCount: 0,
    nice: 0,
    priority: 0,
    cpuUsage: cpuUsage,
    gpuUsage: gpuUsage,
    networkInBytesPerSecond: networkInBytesPerSecond,
    networkOutBytesPerSecond: networkOutBytesPerSecond,
    totalNetworkInBytes: 0,
    totalNetworkOutBytes: 0,
    storageReadBytesPerSecond: storageReadBytesPerSecond,
    storageWriteBytesPerSecond: storageWriteBytesPerSecond,
    storageIoAvailable: storageIoAvailable,
    startTimeUnixMs: startTimeUnixMs,
    name: name,
    executablePath: resolvedExecutablePath,
    commandLine: commandLine ?? resolvedExecutablePath,
    appBundlePath: appBundlePath,
    iconUri: iconUri,
    treeCpuUsage: cpuUsage,
    treeGpuUsage: gpuUsage,
    treeRssBytes: rssBytes,
    treeNetworkInBytesPerSecond: networkInBytesPerSecond,
    treeNetworkOutBytesPerSecond: networkOutBytesPerSecond,
    treeStorageReadBytesPerSecond: storageReadBytesPerSecond,
    treeStorageWriteBytesPerSecond: storageWriteBytesPerSecond,
    treeStorageIoAvailable: storageIoAvailable,
  );
}

class _FakeSettingsService implements SettingsService {
  _FakeSettingsService(AppSettings settings)
    : _settings = ValueNotifier(settings);

  final ValueNotifier<AppSettings> _settings;

  @override
  ValueListenable<AppSettings> get settings => _settings;

  @override
  Future<void> initialize() async {}

  @override
  void dispose() {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> updatePollingIntervalMs(int value) async {
    _settings.value = _settings.value.copyWith(pollingIntervalMs: value);
  }

  @override
  Future<void> updateRememberTreeExpansion(bool value) async {
    _settings.value = _settings.value.copyWith(rememberTreeExpansion: value);
  }

  @override
  Future<void> updateSavedFilters(List<String> value) async {
    _settings.value = _settings.value.copyWith(savedFilters: value);
  }

  @override
  Future<void> addSavedFilter(String value) async {
    _settings.value = _settings.value.copyWith(
      savedFilters: [..._settings.value.savedFilters, value],
    );
  }

  @override
  Future<void> removeSavedFilter(String value) async {
    _settings.value = _settings.value.copyWith(
      savedFilters: [
        for (final filter in _settings.value.savedFilters)
          if (filter != value) filter,
      ],
    );
  }

  @override
  Future<void> updateVisibleColumns(List<String> value) async {
    _settings.value = _settings.value.copyWith(visibleColumns: value);
  }

  @override
  Future<void> updateColumnWidths(Map<String, double> value) async {
    _settings.value = _settings.value.copyWith(columnWidths: value);
  }

  @override
  Future<void> updateInspectorWidth(double value) async {
    _settings.value = _settings.value.copyWith(inspectorWidth: value);
  }

  @override
  Future<void> updateProcessSort(
    ProcessSortColumn column,
    ProcessSortDirection direction,
  ) async {
    _settings.value = _settings.value.copyWith(
      processSortColumn: column,
      processSortDirection: direction,
    );
  }

  @override
  Future<void> updateAppearanceMode(AppAppearanceMode value) async {
    _settings.value = _settings.value.copyWith(appearanceMode: value);
  }

  @override
  Future<void> updateRowHeatmap(bool value) async {
    _settings.value = _settings.value.copyWith(rowHeatmap: value);
  }

  @override
  Future<void> updateRowDensity(AppRowDensity value) async {
    _settings.value = _settings.value.copyWith(rowDensity: value);
  }

  @override
  Future<void> updateLanguageCode(String value) async {
    _settings.value = _settings.value.copyWith(languageCode: value);
  }

  @override
  Future<void> updateReleaseChannel(AppReleaseChannel value) async {
    _settings.value = _settings.value.copyWith(releaseChannel: value);
  }
}

ProcessIdentity _id(int pid, [int startTimeUnixMs = 1000]) {
  return ProcessIdentity(pid: pid, startTimeUnixMs: startTimeUnixMs);
}

class _FakeProcessRepository implements ProcessRepository {
  _FakeProcessRepository(this.snapshots, {this.socketsByPid = const {}});

  final List<ProcessSnapshot> snapshots;
  final Map<int, List<NetworkEndpointInfo>> socketsByPid;
  final List<(ProcessIdentity, ProcessSignal)> signals =
      <(ProcessIdentity, ProcessSignal)>[];
  int _index = 0;
  int fetchCount = 0;

  @override
  Future<ProcessSnapshot> fetchSnapshot({
    required int pollingIntervalMs,
  }) async {
    fetchCount++;
    final snapshot = snapshots[_index.clamp(0, snapshots.length - 1)];
    _index++;
    return snapshot;
  }

  @override
  Future<ProcessDetail> fetchProcessDetail(ProcessIdentity identity) async {
    return ProcessDetail(
      identity: identity,
      files: const ProcessDetailAvailable(<FileDescriptorInfo>[]),
      sockets: ProcessDetailAvailable(
        socketsByPid[identity.pid] ?? const <NetworkEndpointInfo>[],
      ),
      threads: const ProcessDetailAvailable(
        ThreadInspectionInfo(summary: null, threads: <ThreadInfo>[]),
      ),
      security: const ProcessDetailAvailable(
        SecurityDetailInfo(
          signingStatus: 'unknown',
          signingAuthority: '',
          teamId: '',
          bundleId: '',
          entitlementsSummary: '',
          entitlementsApproximate: true,
          gatekeeperOrigin: '',
          sandbox: false,
          hardenedRuntime: false,
          architecture: 'unknown',
          rosettaTranslated: false,
        ),
      ),
    );
  }

  @override
  Future<void> sendSignal(
    ProcessIdentity identity,
    ProcessSignal signal,
  ) async {
    signals.add((identity, signal));
  }
}

class _FakeSnapshotRepository implements SnapshotRepository {
  @override
  Future<String> saveRemoteSnapshot(
    ProcessSnapshot snapshot, {
    required SnapshotHost host,
    required Map<String, Uint8List> icons,
  }) => saveSnapshot(snapshot);

  @override
  Future<Map<String, Uint8List>> importSnapshotIcons(String path) async =>
      const {};

  ProcessSnapshot? snapshot;
  ProcessSnapshot? externalSnapshot;
  String? path;
  String? name;

  @override
  Future<String> saveSnapshot(ProcessSnapshot snapshot) async {
    this.snapshot = snapshot;
    path = '/tmp/snapshot.processlama-snapshot.json';
    return path!;
  }

  @override
  Future<ProcessSnapshot> importSnapshot(String path) async {
    if (path == '/tmp/imported.processlama-snapshot.json') {
      return externalSnapshot ?? ProcessSnapshot.empty();
    }
    return snapshot ?? ProcessSnapshot.empty();
  }

  @override
  Future<String> saveSnapshotDocument(String path) async {
    snapshot = externalSnapshot;
    this.path = '/tmp/imported.processlama-snapshot.json';
    return this.path!;
  }

  @override
  Future<List<SnapshotEntry>> listSnapshots() async {
    if (snapshot == null) {
      return const <SnapshotEntry>[];
    }
    return [
      SnapshotEntry(
        path: path ?? '/tmp/snapshot.processlama-snapshot.json',
        generatedAtUnixMs: snapshot!.generatedAtUnixMs,
        processCount: snapshot!.processes.length,
        platform: snapshot!.platform,
        name: name,
      ),
    ];
  }

  @override
  Future<void> exportSnapshotToPath(
    SnapshotEntry entry,
    String targetPath,
  ) async {}

  @override
  Future<void> renameSnapshot(SnapshotEntry entry, String name) async {
    this.name = name;
  }

  @override
  Future<void> deleteSnapshot(SnapshotEntry entry) async {
    snapshot = null;
    path = null;
    name = null;
  }
}
