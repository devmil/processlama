import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/repositories.dart';
import 'package:processlama/services/impl/repository_operation_tracker_impl.dart';
import 'package:processlama/services/impl/workspace_tabs_service_impl.dart';
import 'package:processlama/services/services.dart';

import '../support/fake_process_source.dart';

void main() {
  test('starts with the local tab active', () async {
    final factory = _FakeFactory();
    final service = WorkspaceTabsServiceImpl(sessionFactory: factory);
    await service.initialize();

    expect(service.tabs.value, [WorkspaceTab.local]);
    expect(service.activeTab.value, WorkspaceTab.local);
    expect(service.activeSession.value, factory.sessions[WorkspaceTab.local]);
  });

  test('restores remote tabs and the active tab in order', () async {
    final store = MemoryWorkspaceTabsStore();
    await store.write(
      const WorkspaceTabsLayout(
        remoteTabs: [RemoteWorkspaceTab('b'), RemoteWorkspaceTab('a')],
        activeTab: RemoteWorkspaceTab('a'),
      ),
    );
    final factory = _FakeFactory();
    final service = WorkspaceTabsServiceImpl(
      sessionFactory: factory,
      store: store,
    );
    await service.initialize();

    expect(service.tabs.value, [
      WorkspaceTab.local,
      const RemoteWorkspaceTab('b'),
      const RemoteWorkspaceTab('a'),
    ]);
    expect(service.activeTab.value, const RemoteWorkspaceTab('a'));
    expect(factory.sessions[const RemoteWorkspaceTab('a')]!.isActive, isTrue);
    expect(factory.sessions[WorkspaceTab.local]!.isActive, isFalse);
  });

  test('skips restored tabs whose profile no longer exists', () async {
    final store = MemoryWorkspaceTabsStore();
    await store.write(
      const WorkspaceTabsLayout(
        remoteTabs: [RemoteWorkspaceTab('gone'), RemoteWorkspaceTab('a')],
        activeTab: RemoteWorkspaceTab('gone'),
      ),
    );
    final service = WorkspaceTabsServiceImpl(
      sessionFactory: _FakeFactory(unavailable: {'gone'}),
      store: store,
    );
    await service.initialize();

    expect(service.tabs.value, [
      WorkspaceTab.local,
      const RemoteWorkspaceTab('a'),
    ]);
    expect(service.activeTab.value, WorkspaceTab.local);
  });

  test('reorders remote tabs, never the local tab, and persists', () async {
    final store = MemoryWorkspaceTabsStore();
    final service = WorkspaceTabsServiceImpl(
      sessionFactory: _FakeFactory(),
      store: store,
    );
    await service.initialize();
    for (final id in ['a', 'b', 'c']) {
      await service.openTab(RemoteWorkspaceTab(id), activate: false);
    }

    service.reorder(3, 1);
    expect(service.tabs.value.map((tab) => tab.key), [
      'local',
      'remote:c',
      'remote:a',
      'remote:b',
    ]);
    service.reorder(2, 0);
    expect(service.tabs.value.first, WorkspaceTab.local);
    service.reorder(0, 3);
    expect(service.tabs.value.first, WorkspaceTab.local);
    expect(store.read().remoteTabs.map((tab) => tab.profileId), [
      'a',
      'c',
      'b',
    ]);
  });

  test('closing a tab disposes its session, then its source', () async {
    final factory = _FakeFactory();
    final service = WorkspaceTabsServiceImpl(sessionFactory: factory);
    await service.initialize();
    const tab = RemoteWorkspaceTab('a');
    await service.openTab(tab);
    final source = factory.sources[tab]!;
    final session = factory.sessions[tab]!;
    bool? sessionDisposedFirst;
    source.onDispose = () => sessionDisposedFirst = session.isDisposed;

    await service.closeTab(tab);

    expect(sessionDisposedFirst, isTrue);
    expect(source.disposed, isTrue);
    expect(service.tabs.value, [WorkspaceTab.local]);
    expect(service.activeTab.value, WorkspaceTab.local);
    expect(service.activeSession.value, factory.sessions[WorkspaceTab.local]);
    expect(service.sessionFor(tab), isNull);
  });

  test('the local tab cannot be closed', () async {
    final factory = _FakeFactory();
    final service = WorkspaceTabsServiceImpl(sessionFactory: factory);
    await service.initialize();

    await service.closeTab(WorkspaceTab.local);

    expect(service.tabs.value, [WorkspaceTab.local]);
    expect(factory.sources[WorkspaceTab.local]!.disposed, isFalse);
  });

  test('hidden tabs sample at their background cadence', () async {
    final factory = _FakeFactory();
    final service = WorkspaceTabsServiceImpl(sessionFactory: factory);
    await service.initialize();
    const tab = RemoteWorkspaceTab('a');
    await service.openTab(tab);
    final local = factory.sources[WorkspaceTab.local]!;
    final remote = factory.sources[tab]!;

    expect(
      local.cadence,
      const ProcessCadence.background(defaultBackgroundRefreshInterval),
    );
    expect(remote.cadence, isA<LiveCadence>());

    service.activate(WorkspaceTab.local);
    expect(local.cadence, isA<LiveCadence>());
    expect(
      remote.cadence,
      const ProcessCadence.background(defaultBackgroundRefreshInterval),
    );
  });

  test('switching tabs keeps each session selection', () async {
    final factory = _FakeFactory();
    final service = WorkspaceTabsServiceImpl(sessionFactory: factory);
    await service.initialize();
    const tab = RemoteWorkspaceTab('a');
    await service.openTab(tab);
    final remote = factory.sources[tab]!;
    remote.emit(_snapshot([_process(7, 'remote-only')]));
    factory.sessions[tab]!.selectProcess(_id(7));

    service.activate(WorkspaceTab.local);
    service.activate(tab);

    expect(service.activeSession.value.selectedIdentity.value, _id(7));
  });

  test('limits the number of remote tabs', () async {
    final service = WorkspaceTabsServiceImpl(sessionFactory: _FakeFactory());
    await service.initialize();
    for (var index = 0; index < maximumRemoteTabs; index++) {
      expect(
        await service.openTab(RemoteWorkspaceTab('$index'), activate: false),
        isTrue,
      );
    }
    expect(await service.openTab(const RemoteWorkspaceTab('over')), isFalse);
    expect(service.tabs.value, hasLength(maximumRemoteTabs + 1));
  });

  test('cycles and selects tabs by index', () async {
    final service = WorkspaceTabsServiceImpl(sessionFactory: _FakeFactory());
    await service.initialize();
    await service.openTab(const RemoteWorkspaceTab('a'), activate: false);
    await service.openTab(const RemoteWorkspaceTab('b'), activate: false);

    service.cycle();
    expect(service.activeTab.value, const RemoteWorkspaceTab('a'));
    service.cycle(backwards: true);
    service.cycle(backwards: true);
    expect(service.activeTab.value, const RemoteWorkspaceTab('b'));
    service.activateIndex(0);
    expect(service.activeTab.value, WorkspaceTab.local);
    service.activateIndex(9);
    expect(service.activeTab.value, WorkspaceTab.local);
  });
}

class _FakeFactory implements ProcessSessionFactory {
  _FakeFactory({this.unavailable = const {}});

  final Set<String> unavailable;
  final sources = <WorkspaceTab, FakeProcessSource>{};
  final sessions = <WorkspaceTab, ProcessSession>{};

  @override
  ProcessSessionHandle create(WorkspaceTab tab) {
    if (tab is RemoteWorkspaceTab && unavailable.contains(tab.profileId)) {
      throw ProcessSessionUnavailable(tab);
    }
    final source = FakeProcessSource(
      descriptor: switch (tab) {
        LocalWorkspaceTab() => ProcessSourceDescriptor.local,
        RemoteWorkspaceTab(:final profileId) => RemoteProcessSourceDescriptor(
          profileId,
        ),
      },
    );
    final session = ProcessSession(
      source: source,
      snapshotRepository: _NoSnapshots(),
      repositoryOperationTracker: RepositoryOperationTrackerImpl(),
      settingsService: _Settings(),
    );
    sources[tab] = source;
    sessions[tab] = session;
    return ProcessSessionHandle(session: session, source: source);
  }
}

class _Settings implements SettingsService {
  final _settings = ValueNotifier(const AppSettings());

  @override
  ValueListenable<AppSettings> get settings => _settings;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoSnapshots implements SnapshotRepository {
  @override
  Future<List<SnapshotEntry>> listSnapshots() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProcessIdentity _id(int pid) => ProcessIdentity(pid: pid, startTimeUnixMs: 1);

ProcessSnapshot _snapshot(List<ProcessRecord> processes) => ProcessSnapshot(
  generatedAtUnixMs: 1,
  platform: 'test',
  processes: processes,
);

ProcessRecord _process(int pid, String name) => ProcessRecord(
  pid: pid,
  ppid: 0,
  uid: 0,
  user: '0',
  status: ProcessStatus.running,
  rssBytes: 0,
  virtualMemoryBytes: 0,
  cpuTimeNanos: 0,
  threadCount: 0,
  openFileCount: 0,
  nice: 0,
  priority: 0,
  cpuUsage: 0,
  gpuUsage: 0,
  networkInBytesPerSecond: 0,
  networkOutBytesPerSecond: 0,
  totalNetworkInBytes: 0,
  totalNetworkOutBytes: 0,
  startTimeUnixMs: 1,
  name: name,
  executablePath: '/bin/$name',
  commandLine: name,
  appBundlePath: '',
);
