import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/app/app_theme_data.dart';
import 'package:processlama/l10n/l10n.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/repositories/repositories.dart';
import 'package:processlama/screens/workspace_tabs/remote_host_dialogs.dart';
import 'package:processlama/screens/workspace_tabs/remote_hosts_settings_section.dart';
import 'package:processlama/screens/workspace_tabs/remote_tab_banner.dart';
import 'package:processlama/screens/workspace_tabs/workspace_tab_strip.dart';
import 'package:processlama/services/services.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../support/remote_ui_fakes.dart';

RemoteHostProfile _profile(String id, String name) =>
    RemoteHostProfile(id: id, displayName: name, sshAlias: '$id-alias');

const _facts = RemoteHostFacts(
  target: RemoteHelperTarget.linuxX8664,
  kernel: '6.1',
  hostInstanceId: 'host',
  hostnameHash: 'hash',
  helperBuildId: '0000000000000000000000000000000000000001',
  compatibility: 1,
  processtreeRevision: 'rev',
  uid: 1000,
);

Widget _app(
  Widget child, {
  required List<SingleChildWidget> providers,
  String language = 'en',
}) => MultiProvider(
  providers: providers,
  child: MaterialApp(
    locale: Locale(language),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: buildProcessLamaTheme(),
    home: Scaffold(body: child),
  ),
);

Future<void> _size(WidgetTester tester, double width) async {
  await tester.binding.setSurfaceSize(Size(width, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// A [ProcessService] for one tab: only its source and state are read.
class _TabProcessService implements ProcessService {
  _TabProcessService(this.sourceDescriptor, ProcessSourceState state)
    : sourceState = ValueNotifier(state);

  @override
  final ProcessSourceDescriptor sourceDescriptor;

  @override
  final ValueNotifier<ProcessSourceState> sourceState;

  @override
  final ValueNotifier<HostCapabilities> hostCapabilities = ValueNotifier(
    HostCapabilities.unknown,
  );

  @override
  final ValueNotifier<String?> loadedSnapshotPath = ValueNotifier(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('tab strip', () {
    FakeRemoteHostService hosts() {
      final service = FakeRemoteHostService(
        profiles: [
          _profile('a', 'build-box'),
          _profile('b', 'a rather long staging host name'),
          _profile('c', 'nas'),
          _profile('d', 'not open'),
          _profile('e', 'edge-1'),
          _profile('f', 'edge-2'),
          _profile('g', 'edge-3'),
        ],
      );
      service.setState(
        'a',
        const RemoteHostConnectionState(phase: RemoteConnectionPhase.live),
      );
      service.setState(
        'b',
        const RemoteHostConnectionState(
          phase: RemoteConnectionPhase.reconnecting,
        ),
      );
      return service;
    }

    for (final width in [1180.0, 640.0]) {
      testWidgets('fits at $width px without wrapping', (tester) async {
        await _size(tester, width);
        // Six remote tabs need about 660 px; three fit either way.
        final tabs = FakeWorkspaceTabsService(
          remoteTabs: width < 1000
              ? ['a', 'b', 'c', 'e', 'f', 'g']
              : ['a', 'b', 'c'],
        );
        await tester.pumpWidget(
          _app(
            Align(
              alignment: Alignment.topCenter,
              child: WorkspaceTabStrip(onManageRemoteHosts: () {}),
            ),
            providers: remoteUiProviders(hosts: hosts(), tabs: tabs),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final strip = tester.getSize(
          find.byKey(const ValueKey('workspace-tab-strip')),
        );
        expect(strip.height, 34, reason: 'one row, never wrapped');
        expect(find.byKey(const ValueKey('workspace-tab-local')), findsOne);
        expect(find.text('build-box'), findsOne);
        expect(
          find.byKey(const ValueKey('workspace-tab-overflow')),
          width < 1000 ? findsOne : findsNothing,
        );

        if (width < 1000) {
          await tester.tap(
            find.byKey(const ValueKey('workspace-tab-overflow')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('nas').last);
          await tester.pumpAndSettle();
          expect(tabs.activeTab.value, const RemoteWorkspaceTab('c'));
        } else {
          await tester.tap(find.text('build-box'));
          await tester.pumpAndSettle();
          expect(tabs.activeTab.value, const RemoteWorkspaceTab('a'));
          await tester.tap(find.byKey(const ValueKey('workspace-tab-local')));
          await tester.pumpAndSettle();
          expect(tabs.activeTab.value, WorkspaceTab.local);
        }
      });
    }

    testWidgets('the + menu lists closed hosts and the actions', (
      tester,
    ) async {
      await _size(tester, 1180);
      final service = hosts();
      final tabs = FakeWorkspaceTabsService(remoteTabs: ['a', 'b', 'c']);
      var manage = 0;
      await tester.pumpWidget(
        _app(
          Align(
            alignment: Alignment.topCenter,
            child: WorkspaceTabStrip(onManageRemoteHosts: () => manage++),
          ),
          providers: remoteUiProviders(hosts: service, tabs: tabs),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Open remote host'));
      await tester.pumpAndSettle();

      expect(find.text('not open'), findsOne);
      expect(find.text('edge-1'), findsOne);
      expect(find.text('build-box'), findsOne, reason: 'only the strip');
      expect(find.text('Add remote host…'), findsOne);
      expect(find.text('Manage remote hosts…'), findsOne);

      await tester.tap(find.text('not open'));
      await tester.pumpAndSettle();
      expect(tabs.tabs.value.last, const RemoteWorkspaceTab('d'));
      expect(tabs.activeTab.value, const RemoteWorkspaceTab('d'));
      expect(service.connects, ['d']);

      await tester.tap(find.bySemanticsLabel('Open remote host'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage remote hosts…'));
      await tester.pumpAndSettle();
      expect(manage, 1);
    });
  });

  group('remote tab banner', () {
    Future<void> pumpBanner(
      WidgetTester tester, {
      required RemoteHostConnectionState state,
      required ProcessSourceState source,
      String language = 'en',
    }) async {
      final hosts = FakeRemoteHostService(
        profiles: [_profile('a', 'build-box')],
      )..setState('a', state);
      await tester.pumpWidget(
        _app(
          Provider<ProcessService>.value(
            value: _TabProcessService(
              const RemoteProcessSourceDescriptor('a'),
              source,
            ),
            child: const RemoteTabBanner(),
          ),
          providers: remoteUiProviders(hosts: hosts),
          language: language,
        ),
      );
      await tester.pump();
    }

    final lastSample = DateTime(2026, 10, 15, 14, 3, 9);

    testWidgets('a stale tab names the time, the reason and reconnects', (
      tester,
    ) async {
      await _size(tester, 640);
      await pumpBanner(
        tester,
        state: const RemoteHostConnectionState(
          phase: RemoteConnectionPhase.reconnecting,
          failure: RemoteFailureCode.heartbeatLost,
        ),
        source: ProcessSourceState(
          phase: ProcessSourcePhase.stale,
          lastSampleAt: lastSample,
        ),
      );
      expect(find.text('Reconnecting to build-box…'), findsOne);
      expect(
        find.text('Showing data from 14:03:09. The host stopped responding.'),
        findsOne,
      );
      expect(find.text('Reconnect'), findsOne);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a host without a helper offers the install', (tester) async {
      await _size(tester, 640);
      await pumpBanner(
        tester,
        state: const RemoteHostConnectionState(
          phase: RemoteConnectionPhase.failed,
          failure: RemoteFailureCode.helperNotInstalled,
          missingTarget: RemoteHelperTarget.linuxX8664,
        ),
        source: const ProcessSourceState(phase: ProcessSourcePhase.failed),
        language: 'de',
      );
      expect(find.text('Keine Verbindung zu build-box'), findsOne);
      expect(find.text('Helfer installieren …'), findsOne);
    });

    testWidgets('a live tab shows nothing', (tester) async {
      await pumpBanner(
        tester,
        state: const RemoteHostConnectionState(
          phase: RemoteConnectionPhase.live,
        ),
        source: ProcessSourceState(
          phase: ProcessSourcePhase.live,
          lastSampleAt: lastSample,
        ),
      );
      expect(find.byKey(const ValueKey('remote-tab-banner')), findsNothing);
    });
  });

  testWidgets('the install dialog shows the helper and returns the choice', (
    tester,
  ) async {
    await _size(tester, 1180);
    RemoteInstallChoice? choice;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await showDialog(
              context: context,
              builder: (_) => RemoteHelperInstallDialog(
                request: RemoteInstallRequest(
                  profile: _profile('a', 'build-box'),
                  target: RemoteHelperTarget.linuxX8664,
                  isUpdate: false,
                  artifact: RemoteHelperArtifact(
                    target: RemoteHelperTarget.linuxX8664,
                    buildId: '0000000000000000000000000000000000000001',
                    size: 2133672,
                    sha256: 'ab' * 32,
                    read: () async => Uint8List(0),
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
        providers: remoteUiProviders(),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Install helper on build-box?'), findsOne);
    expect(find.text('2.0 MB'), findsOne);
    expect(find.text('abababababab'), findsOne);
    expect(find.textContaining('~/.local/lib/processlama/remote/'), findsOne);
    await tester.tap(find.text('Install and always install for this host'));
    await tester.pumpAndSettle();
    expect(choice, RemoteInstallChoice.installAlways);
  });

  testWidgets('the editor validates, tests and saves a profile', (
    tester,
  ) async {
    await _size(tester, 1180);
    final hosts = FakeRemoteHostService();
    RemoteHostProfile? saved;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => saved = await showRemoteHostEditor(context),
            child: const Text('open'),
          ),
        ),
        providers: remoteUiProviders(hosts: hosts),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('remote-host-alias')),
      'bad alias',
    );
    await tester.tap(find.byKey(const ValueKey('remote-host-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Use letters, digits, dots'), findsOne);

    await tester.enterText(
      find.byKey(const ValueKey('remote-host-alias')),
      'build-box',
    );
    await tester.tap(find.byKey(const ValueKey('remote-host-test')));
    await tester.pumpAndSettle();
    expect(find.text('Helper missing'), findsOne);

    await tester.tap(find.byKey(const ValueKey('remote-host-save')));
    await tester.pumpAndSettle();
    expect(saved?.sshAlias, 'build-box');
    expect(saved?.displayName, 'build-box', reason: 'defaults to the alias');
    expect(saved?.autoInstallHelper, isFalse);
    expect(hosts.hosts.value.profiles.single.id, saved?.id);
  });

  testWidgets('the settings section lists hosts and manages the cache', (
    tester,
  ) async {
    await _size(tester, 1180);
    final hosts = FakeRemoteHostService(
      profiles: [
        _profile('a', 'build-box').copyWith(lastKnown: () => _facts),
        _profile('b', 'nas').copyWith(autoInstallHelper: true),
      ],
    );
    final icons = FakeProcessIconService()..cacheBytes = 3 * 1024 * 1024;
    final tabs = FakeWorkspaceTabsService(remoteTabs: ['b']);
    await tester.pumpWidget(
      _app(
        const SingleChildScrollView(child: RemoteHostsSettingsSection()),
        providers: remoteUiProviders(hosts: hosts, icons: icons, tabs: tabs),
      ),
    );
    expect(find.text('build-box'), findsOne);
    expect(find.text('a-alias · Linux/x86_64 · helper 1'), findsOne);
    expect(
      find.text(
        'b-alias · Not connected yet · Installs the helper automatically',
      ),
      findsOne,
    );
    expect(find.text('3.0 MB used of 64 MB'), findsOne);

    await tester.tap(find.byKey(const ValueKey('remote-icon-cache-clear')));
    await tester.pumpAndSettle();
    expect(icons.clears, 1);

    await tester.tap(find.text('Live'));
    await tester.pumpAndSettle();
    expect(
      hosts.hosts.value.defaultBackgroundRefresh,
      BackgroundRefreshMode.live,
    );

    await tester.tap(find.bySemanticsLabel('Actions for nas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();
    expect(tabs.closed, [const RemoteWorkspaceTab('b')]);
    expect(hosts.hosts.value.profiles.map((profile) => profile.id), ['a']);
    expect(tester.takeException(), isNull);
  });

  test('the network service command matches the release packages', () {
    expect(
      networkServiceInstallCommand(
        version: '1.0.0-beta.27',
        build: 34,
        target: RemoteHelperTarget.linuxArm64,
      ),
      'curl -fsSLO https://github.com/devmil/processlama/releases/download/'
      'v1.0.0-beta.27-34/processlama-network-service-1.0.0-beta.27-34-linux-'
      'aarch64.tar.gz && tar -xzf processlama-network-service-1.0.0-beta.27-'
      '34-linux-aarch64.tar.gz && sudo ./processlama-network-service-1.0.0-'
      'beta.27-34-linux-aarch64/install.sh',
    );
    expect(
      networkServiceInstallCommand(
        version: '1.0.0',
        build: 40,
        target: RemoteHelperTarget.macosArm64,
      ),
      isNull,
    );
  });
}
