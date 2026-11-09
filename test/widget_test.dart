import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';

import 'package:processlama/app/app_launcher.dart';
import 'package:processlama/app/app_theme_data.dart';
import 'package:processlama/app/platform_capabilities.dart';
import 'package:processlama/l10n/l10n.dart';
import 'package:processlama/models/models.dart';
import 'package:processlama/screens/process_explorer_screen.dart';
import 'package:processlama/services/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'support/remote_ui_fakes.dart';

void main() {
  for (final language in ['en', 'de']) {
    testWidgets('search aspects and sorted ports fit in $language', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final process = _process(
        pid: 42,
        name: 'server',
        startTimeUnixMs: 1000,
      ).copyWith(localPorts: [53, 8080], listeningPorts: [8080]);
      final service = _FakeProcessService(
        _treeWithRows([_row(identity: process.identity, process: process)]),
      );
      final empty = ProcessInspectorView.empty();
      const postgres = ProcessIdentity(pid: 7, startTimeUnixMs: 1000);
      service._inspector.value = ProcessInspectorView(
        process: process,
        ports: ProcessPorts.ofRecord(process),
        treePorts: const ProcessPorts(listening: [8080], other: [53, 443]),
        listenerOwnersByPort: {
          5432: [
            ProcessPortOwner(identity: postgres, pid: 7, name: 'postgres'),
          ],
        },
        identity: process.identity,
        changeMarker: ProcessChangeMarker.none,
        iconPath: null,
        platform: 'linux',
        detail: ProcessDetail(
          identity: process.identity,
          files: const ProcessDetailAvailable(<FileDescriptorInfo>[]),
          sockets: const ProcessDetailAvailable([
            NetworkEndpointInfo(
              protocol: 'TCP',
              localAddress: '127.0.0.1',
              localPort: 53,
              localAddressApproximate: false,
              remoteAddress: '127.0.0.1',
              remotePort: 5432,
              remoteAddressApproximate: false,
              state: 'Established',
            ),
          ]),
          threads: const ProcessDetailNotFound('n/a'),
          security: const ProcessDetailNotFound('n/a'),
        ),
        overview: empty.overview,
        openFiles: empty.openFiles,
        sockets: empty.sockets,
        network: empty.network,
        threads: empty.threads,
        security: empty.security,
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ProcessService>.value(value: service),
            Provider<SettingsService>.value(value: _FakeSettingsService()),
            Provider<AppUpdateService>.value(value: _FakeAppUpdateService()),
            ...remoteUiProviders(),
          ],
          child: MaterialApp(
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildProcessLamaTheme(),
            home: const ProcessExplorerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      String portCount() => tester
          .widget<MeridianCount>(
            find.byKey(const ValueKey('overview-port-count')),
          )
          .label;
      Finder chip(int port) => find.descendant(
        of: find.byKey(const ValueKey('overview-ports')),
        matching: find.byKey(ValueKey(('port-chip', port))),
      );
      expect(portCount(), '3');
      expect(chip(8080), findsNothing, reason: 'ports start collapsed');
      final portsHeader = find.text(
        language == 'en' ? 'Occupied ports' : 'Belegte Ports',
      );
      await tester.ensureVisible(portsHeader);
      await tester.tap(portsHeader);
      await tester.pumpAndSettle();
      expect(chip(8080), findsOneWidget);
      expect(chip(443), findsOneWidget, reason: 'tree scope lists all ports');
      expect(
        find.text(language == 'en' ? 'Listening' : 'Lauschend'),
        findsOneWidget,
      );
      await tester.ensureVisible(chip(8080));
      await tester.tap(chip(8080));
      expect(service.shownPorts, [8080]);
      final processScope = find
          .text(language == 'en' ? 'Process' : 'Prozess')
          .first;
      await tester.ensureVisible(processScope);
      await tester.pumpAndSettle();
      await tester.tap(processScope);
      await tester.pumpAndSettle();
      expect(portCount(), '2');
      expect(chip(443), findsNothing);
      expect(chip(53), findsOneWidget);
      final menuLabel = language == 'en'
          ? 'Search aspect: Process text'
          : 'Suchkriterium: Prozesstext';
      await tester.tap(find.byTooltip(menuLabel));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(language == 'en' ? 'Local port' : 'Lokaler Port'),
      );
      await tester.pumpAndSettle();
      expect(service.searchOptions.value.aspect, ProcessSearchAspect.port);
      expect(
        find.text(
          language == 'en'
              ? 'Local port (e.g. 8080)'
              : 'Lokaler Port (z. B. 8080)',
        ),
        findsOneWidget,
      );
      final filesTab = find.text(
        language == 'en' ? 'Files & Sockets' : 'Dateien & Sockets',
      );
      await tester.ensureVisible(filesTab);
      await tester.pumpAndSettle();
      await tester.tap(filesTab);
      await tester.pumpAndSettle();
      final peer = find.descendant(
        of: find.byKey(const ValueKey('socket-peers')),
        matching: find.text(':5432 · postgres (7)'),
      );
      await tester.ensureVisible(peer);
      await tester.tap(peer);
      expect(service._selectedIdentity.value, postgres);
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    for (final language in ['en', 'de']) {
      testWidgets('ProcessLama signature and About in $language $brightness', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(1000, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final service = _FakeProcessService(ProcessTreeView.empty());
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<ProcessService>.value(value: service),
              Provider<SettingsService>.value(value: _FakeSettingsService()),
              Provider<AppUpdateService>.value(value: _FakeAppUpdateService()),
              ...remoteUiProviders(),
            ],
            child: MaterialApp(
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildProcessLamaTheme(brightness: brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
              home: const ProcessExplorerScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final label = language == 'de'
            ? 'Über ProcessLama'
            : 'About ProcessLama';
        expect(find.bySemanticsLabel(label), findsOneWidget);
        final signature = find.byTooltip('ProcessLama · by Devmil Solutions');
        expect(signature, findsOneWidget);
        expect(tester.getBottomLeft(signature).dy, greaterThan(500));
        await tester.tap(signature);
        await tester.pumpAndSettle();
        expect(find.text('by Devmil Solutions'), findsOneWidget);
        expect(
          find
                  .textContaining('build 26', findRichText: true)
                  .evaluate()
                  .length +
              find
                  .textContaining('Build 26', findRichText: true)
                  .evaluate()
                  .length,
          1,
        );
        expect(
          find.text('ProcessLama · GitLama · MailLama · ShotLama · NoteLama'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('by Devmil Solutions'), findsNothing);
        expect(signature, findsOneWidget);
        // Pointer activation gives the control focus. Space must reopen About.
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(find.text('by Devmil Solutions'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
  testWidgets('CPU samples update meters without scheduling animation frames', (
    tester,
  ) async {
    ProcessTreeView sample(double cpu) => _treeWithRows([
      _row(
        identity: const ProcessIdentity(pid: 42, startTimeUnixMs: 1000),
        process: _process(
          pid: 42,
          name: 'Dock',
          startTimeUnixMs: 1000,
          cpuUsage: cpu,
        ),
      ),
    ]);
    await tester.binding.setSurfaceSize(const Size(1800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _FakeProcessService(sample(10));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProcessService>.value(value: service),
          Provider<SettingsService>.value(value: _FakeSettingsService()),
          Provider<AppUpdateService>.value(value: _FakeAppUpdateService()),
          ...remoteUiProviders(),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildProcessLamaTheme(),
          home: const ProcessExplorerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MeridianMeter), findsWidgets);
    service._tree.value = sample(70);
    await tester.pump();
    final fills = tester.widgetList<AnimatedFractionallySizedBox>(
      find.descendant(
        of: find.byType(MeridianMeter),
        matching: find.byType(AnimatedFractionallySizedBox),
      ),
    );
    expect(fills, isNotEmpty);
    expect(fills.every((fill) => fill.widthFactor == 0.7), isTrue);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('shows the process explorer shell', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const AppLauncher(forTest: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('ProcessLama'), findsWidgets);
    expect(find.text('0 processes'), findsOneWidget);
    if (PlatformCapabilities.isDesktop) {
      expect(find.byType(DragToMoveArea), findsOneWidget);
      // The unified title bar and toolbar moves the window.
      expect(
        tester.getSize(find.byType(DragToMoveArea)),
        const Size(800, MeridianSize.toolbar),
      );
    }
  });

  testWidgets('resumes process refresh after Linux resize events stop', (
    tester,
  ) async {
    final processService = _FakeProcessService(ProcessTreeView.empty());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProcessService>.value(value: processService),
          Provider<SettingsService>.value(value: _FakeSettingsService()),
          Provider<AppUpdateService>.value(value: _FakeAppUpdateService()),
          ...remoteUiProviders(),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildProcessLamaTheme(),
          home: const ProcessExplorerScreen(),
        ),
      ),
    );
    await tester.pump();

    final dynamic screenState = tester.state(
      find.byType(ProcessExplorerScreen),
    );
    screenState.onWindowResize();
    expect(processService.resizeStates, [true]);

    await tester.pump(const Duration(milliseconds: 250));

    expect(processService.resizeStates, [true, false]);
    expect(processService.refreshCount, 1);
  });

  testWidgets('selects a process row on pointer down', (tester) async {
    final dockIdentity = const ProcessIdentity(pid: 42, startTimeUnixMs: 1000);
    final processService = _FakeProcessService(
      _treeWithRows([
        _row(
          identity: dockIdentity,
          process: _process(pid: 42, name: 'Dock', startTimeUnixMs: 1000),
        ),
      ]),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProcessService>.value(value: processService),
          Provider<SettingsService>.value(value: _FakeSettingsService()),
          Provider<AppUpdateService>.value(value: _FakeAppUpdateService()),
          ...remoteUiProviders(),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildProcessLamaTheme(),
          home: const ProcessExplorerScreen(),
        ),
      ),
    );

    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Dock')),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );

    expect(processService.selectedIdentity.value, dockIdentity);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('tree rows follow the row density setting', (tester) async {
    final processService = _FakeProcessService(
      _treeWithRows([
        _row(
          identity: const ProcessIdentity(pid: 42, startTimeUnixMs: 1000),
          process: _process(pid: 42, name: 'Dock', startTimeUnixMs: 1000),
        ),
        _row(
          identity: const ProcessIdentity(pid: 43, startTimeUnixMs: 1000),
          process: _process(pid: 43, name: 'Finder', startTimeUnixMs: 1000),
        ),
      ]),
    );

    for (final (density, extent) in [
      (AppRowDensity.compact, MeridianSize.rowCompact),
      (AppRowDensity.regular, MeridianSize.row),
      (AppRowDensity.comfortable, MeridianSize.rowComfortable),
    ]) {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ProcessService>.value(value: processService),
            Provider<SettingsService>.value(value: _FakeSettingsService()),
            Provider<AppUpdateService>.value(value: _FakeAppUpdateService()),
            ...remoteUiProviders(),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildProcessLamaTheme(density: density),
            home: const ProcessExplorerScreen(),
          ),
        ),
      );
      // Let the theme transition finish; Meridian swaps density mid-lerp.
      await tester.pump(const Duration(seconds: 1));

      final pitch =
          tester.getCenter(find.text('Finder')).dy -
          tester.getCenter(find.text('Dock')).dy;
      expect(pitch.abs(), extent, reason: density.name);
    }
  });

  testWidgets('a hovered tree chevron stays visible on its hovered row', (
    tester,
  ) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    final parent = _row(
      identity: const ProcessIdentity(pid: 42, startTimeUnixMs: 1000),
      process: _process(pid: 42, name: 'Dock', startTimeUnixMs: 1000),
      hasChildren: true,
    );
    final processService = _FakeProcessService(_treeWithRows([parent]));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProcessService>.value(value: processService),
          Provider<SettingsService>.value(value: _FakeSettingsService()),
          Provider<AppUpdateService>.value(value: _FakeAppUpdateService()),
          ...remoteUiProviders(),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildProcessLamaTheme(),
          home: const ProcessExplorerScreen(),
        ),
      ),
    );
    await tester.pump();

    final chevron = find.byTooltip('Collapse');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(chevron));
    await tester.pump(const Duration(milliseconds: 200));

    final colors = MeridianTheme.of(tester.element(chevron)).colors;
    final chip =
        tester
                .widget<AnimatedContainer>(
                  find
                      .descendant(
                        of: chevron,
                        matching: find.byType(AnimatedContainer),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    // The row itself is pane-hover now; the chevron darkens it.
    expect(chip.color, meridianPressed(colors.paneHover, colors.ink));
  });

  for (final dismissal in ['escape', 'selection', 'unmount']) {
    testWidgets('process menu holds ordering until $dismissal', (tester) async {
      final service = _FakeProcessService(
        _treeWithRows([
          _row(
            identity: const ProcessIdentity(pid: 42, startTimeUnixMs: 1000),
            process: _process(pid: 42, name: 'Dock', startTimeUnixMs: 1000),
          ),
        ]),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ProcessService>.value(value: service),
            Provider<SettingsService>.value(value: _FakeSettingsService()),
            Provider<AppUpdateService>.value(value: _FakeAppUpdateService()),
            ...remoteUiProviders(),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildProcessLamaTheme(),
            home: const ProcessExplorerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Dock').first));
      await tester.pump();
      expect(service.treeHovering, isTrue);
      await mouse.down(tester.getCenter(find.text('Dock').first));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(service.treeContextMenuOpen, isTrue);
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(seconds: 4));
      expect(service.treeHovering, isFalse);
      expect(service.treeContextMenuOpen, isTrue);

      if (dismissal == 'unmount') {
        await tester.pumpWidget(const SizedBox.shrink());
      } else if (dismissal == 'selection') {
        await tester.tap(find.text('Pin process'));
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      }
      await tester.pumpAndSettle();
      expect(service.treeContextMenuOpen, isFalse);
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
    });
  }

  testWidgets('hovering a history chart shows the bar value', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final identity = const ProcessIdentity(pid: 42, startTimeUnixMs: 1000);
    final process = _process(pid: 42, name: 'Dock', startTimeUnixMs: 1000);
    final row = _row(
      identity: identity,
      process: process,
      cpuHistory: const [10, 20, 30],
    );
    final processService = _FakeProcessService(
      _treeWithRows([row], selectedIdentity: identity),
    );
    const available = InspectorSectionState(
      availability: InspectorAvailability.available,
      message: '',
    );
    processService._inspector.value = ProcessInspectorView(
      process: process,
      identity: identity,
      changeMarker: ProcessChangeMarker.none,
      iconPath: null,
      platform: 'test',
      detail: null,
      overview: available,
      openFiles: available,
      sockets: available,
      network: available,
      threads: available,
      security: available,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProcessService>.value(value: processService),
          Provider<SettingsService>.value(value: _FakeSettingsService()),
          Provider<AppUpdateService>.value(value: _FakeAppUpdateService()),
          ...remoteUiProviders(),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildProcessLamaTheme(),
          home: const ProcessExplorerScreen(),
        ),
      ),
    );
    await tester.pump();

    final chart = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter.runtimeType.toString() == '_MetricHistoryChartPainter',
    );
    // CPU, RSS and GPU; CPU comes first.
    expect(chart, findsNWidgets(3));
    final rect = tester.getRect(chart.first);
    // Three samples fill the last three of 60 slots; hover the middle one.
    final slot = rect.width / 60;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(Offset(rect.left + slot * 58.5, rect.center.dy));
    await tester.pump();
    expect(find.text('20%'), findsOneWidget);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(find.text('20%'), findsNothing);
  });

  testWidgets('opens the Meridian process menu on secondary click', (
    tester,
  ) async {
    final dockIdentity = const ProcessIdentity(pid: 42, startTimeUnixMs: 1000);
    final processService = _FakeProcessService(
      _treeWithRows([
        _row(
          identity: dockIdentity,
          process: _process(pid: 42, name: 'Dock', startTimeUnixMs: 1000),
        ),
      ]),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProcessService>.value(value: processService),
          Provider<SettingsService>.value(value: _FakeSettingsService()),
          Provider<AppUpdateService>.value(value: _FakeAppUpdateService()),
          ...remoteUiProviders(),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildProcessLamaTheme(),
          home: const ProcessExplorerScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(
      find.text('Dock'),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(processService.selectedIdentity.value, dockIdentity);
    expect(find.byType(MeridianMenuSurface), findsOneWidget);
    expect(find.text('Terminate process'), findsOneWidget);
    expect(find.text('Force kill process'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MeridianMenuSurface), findsNothing);
  });

  testWidgets('groups the preferences into pages', (tester) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = _FakeSettingsService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProcessService>.value(
            value: _FakeProcessService(_treeWithRows(const [])),
          ),
          Provider<SettingsService>.value(value: settings),
          Provider<AppUpdateService>.value(value: _FakeAppUpdateService()),
          ...remoteUiProviders(),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildProcessLamaTheme(),
          home: const ProcessExplorerScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Preferences').first);
    await tester.pumpAndSettle();

    final dialog = find.byType(MeridianSettingsDialog);
    expect(dialog, findsOne);
    expect(
      find.descendant(of: dialog, matching: find.byType(MeridianNavRow)),
      findsNWidgets(6),
    );
    // Appearance first; the other pages are not built until picked.
    expect(find.text('Row density'), findsWidgets);
    expect(find.byKey(const ValueKey('remote-hosts-settings')), findsNothing);

    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Remote hosts')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('remote-hosts-settings')), findsOne);
    expect(find.text('Row density'), findsNothing);

    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Columns')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MeridianCheckbox), findsWidgets);

    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Updates')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Release channel'), findsWidgets);
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Diagnostics')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Preview export'), findsOneWidget);
    expect(
      find.text('Enable detailed diagnostics for 15 minutes'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.bySemanticsLabel('Close').last);
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
  });

  testWidgets('opens an exported snapshot from the snapshots rail', (
    tester,
  ) async {
    const exportedPath = '/tmp/exported.processlama-snapshot.json';
    final processService = _FakeProcessService(_treeWithRows(const []));
    final filePickerChannel = const MethodChannel(
      'miguelruivo.flutter.plugins.filepicker',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(filePickerChannel, (call) async {
          switch (call.method) {
            case 'custom':
              return [
                {
                  'name': 'exported.processlama-snapshot.json',
                  'path': exportedPath,
                  'size': 0,
                },
              ];
            case 'pickFiles':
              return [exportedPath];
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(filePickerChannel, null),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProcessService>.value(value: processService),
          Provider<SettingsService>.value(value: _FakeSettingsService()),
          Provider<AppUpdateService>.value(value: _FakeAppUpdateService()),
          ...remoteUiProviders(),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildProcessLamaTheme(),
          home: const ProcessExplorerScreen(),
        ),
      ),
    );

    await tester.pump();
    // The snapshots section reveals its actions while the pointer is over
    // it, as a mouse would.
    final openSnapshot = find.byTooltip('Open snapshot…');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(openSnapshot));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(openSnapshot);
    await tester.pump();

    expect(processService.loadedPath, exportedPath);
    expect(find.text('Snapshot loaded'), findsOneWidget);
  });

  testWidgets('typing in the tree starts tree search without filtering', (
    tester,
  ) async {
    final processService = _FakeProcessService(
      _treeWithRows([
        _row(
          identity: const ProcessIdentity(pid: 42, startTimeUnixMs: 1000),
          process: _process(pid: 42, name: 'Dock', startTimeUnixMs: 1000),
        ),
        _row(
          identity: const ProcessIdentity(pid: 43, startTimeUnixMs: 1001),
          process: _process(pid: 43, name: 'Safari', startTimeUnixMs: 1001),
        ),
      ]),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProcessService>.value(value: processService),
          Provider<SettingsService>.value(value: _FakeSettingsService()),
          Provider<AppUpdateService>.value(value: _FakeAppUpdateService()),
          ...remoteUiProviders(),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildProcessLamaTheme(),
          home: const ProcessExplorerScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.tap(find.text('Dock'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS, character: 's');
    await tester.pump();

    expect(processService.filter.value, isEmpty);
    expect(processService.tree.value.treeSearchQuery, 's');
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('1/1'), findsOneWidget);
    expect(find.byTooltip('Previous match'), findsOneWidget);
    expect(find.byTooltip('Next match'), findsOneWidget);
    expect(find.text('Dock'), findsOneWidget);
    expect(find.text('Safari'), findsOneWidget);

    final overlayField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.focusNode?.debugLabel == 'tree-search-overlay',
      description: 'tree search overlay field',
    );
    final overlayTextField = tester.widget<TextField>(overlayField);
    expect(overlayTextField.controller?.text, 's');
    expect(overlayTextField.focusNode?.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
    await tester.pump();

    expect(processService.tree.value.treeSearchQuery, 'sa');
    expect(overlayTextField.controller?.text, 'sa');
    expect(overlayTextField.focusNode?.hasFocus, isFalse);

    await tester.showKeyboard(overlayField);
    await tester.pump();

    var focusedOverlayTextField = tester.widget<TextField>(overlayField);
    expect(focusedOverlayTextField.focusNode?.hasFocus, isTrue);

    await tester.enterText(overlayField, 'saf');
    await tester.pump();

    focusedOverlayTextField = tester.widget<TextField>(overlayField);
    expect(processService.tree.value.treeSearchQuery, 'saf');
    expect(focusedOverlayTextField.controller?.text, 'saf');
    expect(focusedOverlayTextField.focusNode?.hasFocus, isTrue);

    final findModifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.meta
        : LogicalKeyboardKey.control;
    await tester.sendKeyDownEvent(findModifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(findModifier);
    await tester.pump();

    expect(find.byType(TextField), findsNWidgets(2));
    expect(overlayTextField.focusNode?.hasFocus, isTrue);
    expect(
      focusedOverlayTextField.controller?.selection,
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(processService.tree.value.treeSearchQuery, isEmpty);
    expect(find.byType(TextField), findsOneWidget);
    expect(processService.filter.value, isEmpty);
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets(
    'tree search overlay survives order-lock toggle without losing focus',
    (tester) async {
      final processService = _FakeProcessService(
        _treeWithRows([
          _row(
            identity: const ProcessIdentity(pid: 42, startTimeUnixMs: 1000),
            process: _process(pid: 42, name: 'Dock', startTimeUnixMs: 1000),
          ),
          _row(
            identity: const ProcessIdentity(pid: 43, startTimeUnixMs: 1001),
            process: _process(pid: 43, name: 'Safari', startTimeUnixMs: 1001),
          ),
        ]),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ProcessService>.value(value: processService),
            Provider<SettingsService>.value(value: _FakeSettingsService()),
            Provider<AppUpdateService>.value(value: _FakeAppUpdateService()),
            ...remoteUiProviders(),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildProcessLamaTheme(),
            home: const ProcessExplorerScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.tap(find.text('Dock'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS, character: 's');
      await tester.pump();

      final overlayKey = const ValueKey('tree-search-overlay');
      expect(find.byKey(overlayKey), findsOneWidget);
      final overlayElementBefore = tester.element(find.byKey(overlayKey));

      // Simulate the interaction-lock toggle that used to dispose the overlay
      // because the Stack reconciled children by index.
      processService._tree.value = _treeWithRows(
        processService._tree.value.visibleRows,
        selectedIdentity: processService._tree.value.selectedIdentity,
        treeSearchQuery: processService._tree.value.treeSearchQuery,
        lock: const ProcessTreeLockState(
          isFrozen: false,
          hasQueuedStructuralMutations: false,
          queuedProcessCount: 0,
          isOrderLockedByInteraction: true,
        ),
      );
      await tester.pump();

      expect(find.byKey(overlayKey), findsOneWidget);

      processService._tree.value = _treeWithRows(
        processService._tree.value.visibleRows,
        selectedIdentity: processService._tree.value.selectedIdentity,
        treeSearchQuery: processService._tree.value.treeSearchQuery,
        lock: const ProcessTreeLockState.unlocked(),
      );
      await tester.pump();

      expect(find.byKey(overlayKey), findsOneWidget);
      final overlayElementAfter = tester.element(find.byKey(overlayKey));
      expect(
        overlayElementAfter,
        same(overlayElementBefore),
        reason:
            'tree search overlay Element must survive order-lock toggle; '
            'disposing it drops the search field focus on macOS',
      );
      await tester.pump(const Duration(milliseconds: 50));
    },
  );
}

class _FakeProcessService implements ProcessService {
  _FakeProcessService(ProcessTreeView tree)
    : _snapshot = ValueNotifier(ProcessSnapshot.empty()),
      _tree = ValueNotifier(tree);

  final ValueNotifier<ProcessSnapshot> _snapshot;
  final ValueNotifier<ProcessTreeView> _tree;
  final ValueNotifier<ProcessIdentity?> _selectedIdentity = ValueNotifier(null);
  final ValueNotifier<ProcessInspectorView> _inspector = ValueNotifier(
    ProcessInspectorView.empty(),
  );
  final ValueNotifier<String> _filter = ValueNotifier('');

  @override
  ProcessSourceDescriptor get sourceDescriptor => ProcessSourceDescriptor.local;

  @override
  final ValueListenable<ProcessSourceState> sourceState = ValueNotifier(
    const ProcessSourceState(phase: ProcessSourcePhase.live),
  );

  @override
  final ValueListenable<HostCapabilities> hostCapabilities = ValueNotifier(
    HostCapabilities.unknown,
  );
  final ValueNotifier<ProcessSearchOptions> _searchOptions = ValueNotifier(
    const ProcessSearchOptions(),
  );
  final ValueNotifier<List<SnapshotEntry>> _savedSnapshots = ValueNotifier(
    const <SnapshotEntry>[],
  );
  final ValueNotifier<String?> _loadedSnapshotPath = ValueNotifier(null);
  String? loadedPath;
  final List<bool> resizeStates = <bool>[];
  int refreshCount = 0;

  @override
  ValueListenable<ProcessSnapshot> get snapshot => _snapshot;

  @override
  ValueListenable<ProcessTreeView> get tree => _tree;

  @override
  ValueListenable<ProcessIdentity?> get selectedIdentity => _selectedIdentity;

  @override
  ValueListenable<ProcessInspectorView> get inspector => _inspector;

  @override
  ValueListenable<String> get filter => _filter;

  @override
  ValueListenable<ProcessSearchOptions> get searchOptions => _searchOptions;

  @override
  ValueListenable<List<SnapshotEntry>> get savedSnapshots => _savedSnapshots;

  @override
  ValueListenable<String?> get loadedSnapshotPath => _loadedSnapshotPath;

  @override
  void selectProcess(ProcessIdentity identity) {
    _selectedIdentity.value = identity;
    _tree.value = _treeWithRows(
      _tree.value.visibleRows,
      selectedIdentity: identity,
    );
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refresh() async {
    refreshCount++;
  }

  @override
  Future<void> takeSnapshot() async {}

  @override
  Future<List<SnapshotEntry>> listSnapshots() async => const <SnapshotEntry>[];

  @override
  Future<void> showLiveSnapshot() async {}

  @override
  Future<void> loadSnapshot(String path) async {
    loadedPath = path;
    _loadedSnapshotPath.value = path;
  }

  @override
  Future<void> exportSnapshot(SnapshotEntry entry, String targetPath) async {}

  @override
  Future<void> renameSnapshot(SnapshotEntry entry, String name) async {}

  @override
  Future<void> deleteSnapshot(SnapshotEntry entry) async {}

  @override
  void setFilter(String value) {}

  @override
  void setSearchMatchCase(bool value) {}

  @override
  void setSearchWholeWord(bool value) {}

  @override
  void showPort(int port) => shownPorts.add(port);

  final List<int> shownPorts = <int>[];

  @override
  void setSearchAspect(ProcessSearchAspect aspect) {
    _searchOptions.value = _searchOptions.value.copyWith(aspect: aspect);
  }

  @override
  void setTreeSearch(String value) {
    final nextTree = _treeWithRows(
      _tree.value.visibleRows,
      selectedIdentity: _tree.value.selectedIdentity,
      treeSearchQuery: value,
    );
    final firstMatch = nextTree.visibleRows
        .where((row) => row.matchesTreeSearch)
        .firstOrNull;
    final selectedIdentity = value.isNotEmpty && firstMatch != null
        ? firstMatch.identity
        : _tree.value.selectedIdentity;
    _selectedIdentity.value = selectedIdentity;
    _tree.value = _treeWithRows(
      _tree.value.visibleRows,
      selectedIdentity: selectedIdentity,
      treeSearchQuery: value,
    );
  }

  @override
  void selectNextTreeSearchMatch() {}

  @override
  void selectPreviousTreeSearchMatch() {}

  @override
  void toggleExpansion(ProcessIdentity identity) {}

  @override
  void selectNextVisible() {}

  @override
  void selectPreviousVisible() {}

  @override
  void markTreeInteraction() {}

  @override
  void expandSelected() {}

  @override
  void collapseSelected() {}

  @override
  void focusSelectedSubtree() {}

  @override
  void focusSubtree(ProcessIdentity identity) {}

  @override
  void clearSubtreeFocus() {}

  @override
  void popSubtreeFocus() {}

  @override
  void expandSelectedSubtree() {}

  @override
  void collapseSelectedSubtree() {}

  @override
  void sortBy(ProcessSortColumn column) {}

  @override
  void togglePin(ProcessIdentity identity) {}

  @override
  void setTreeHovering(bool hovering) {
    treeHovering = hovering;
  }

  bool treeHovering = false;
  bool treeContextMenuOpen = false;

  @override
  void setTreeContextMenuOpen(bool open) {
    treeContextMenuOpen = open;
  }

  @override
  void setFrozen(bool frozen) {}

  @override
  void toggleFrozen() {}

  @override
  Future<void> killProcess(ProcessIdentity identity) async {}

  @override
  Future<void> terminateProcess(ProcessIdentity identity) async {}

  @override
  Future<void> suspendProcess(ProcessIdentity identity) async {}

  @override
  Future<void> resumeProcess(ProcessIdentity identity) async {}

  @override
  void setModalOverlayOpen(bool open) {}

  @override
  void setWindowResizing(bool resizing) {
    resizeStates.add(resizing);
  }
}

class _FakeSettingsService implements SettingsService {
  final ValueNotifier<AppSettings> _settings = ValueNotifier(
    const AppSettings(),
  );

  @override
  ValueListenable<AppSettings> get settings => _settings;

  @override
  Future<void> initialize() async {}

  @override
  void dispose() {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> updatePollingIntervalMs(int value) async {}

  @override
  Future<void> updateRememberTreeExpansion(bool value) async {}

  @override
  Future<void> updateSavedFilters(List<String> value) async {}

  @override
  Future<void> addSavedFilter(String value) async {}

  @override
  Future<void> removeSavedFilter(String value) async {}

  @override
  Future<void> updateVisibleColumns(List<String> value) async {}

  @override
  Future<void> updateColumnWidths(Map<String, double> value) async {}

  @override
  Future<void> updateInspectorWidth(double value) async {}

  @override
  Future<void> updateProcessSort(
    ProcessSortColumn column,
    ProcessSortDirection direction,
  ) async {}

  @override
  Future<void> updateAppearanceMode(AppAppearanceMode value) async {}

  @override
  Future<void> updateRowHeatmap(bool value) async {}

  @override
  Future<void> updateRowDensity(AppRowDensity value) async {}

  @override
  Future<void> updateLanguageCode(String value) async {}

  @override
  Future<void> updateReleaseChannel(AppReleaseChannel value) async {}
}

class _FakeAppUpdateService implements AppUpdateService {
  @override
  Future<InstalledAppVersion> loadInstalledVersion() async =>
      const InstalledAppVersion(version: "1.0.0", build: 26);

  @override
  bool get isSupported => false;

  @override
  String get feedUrl => '';

  @override
  String get releaseManifestUrl => '';

  @override
  AppReleaseChannel get releaseChannel => AppReleaseChannel.stable;

  @override
  Future<void> initialize() async {}

  @override
  Future<AppUpdateCheckResult> checkForUpdates() async =>
      const AppUpdateCheckResult(
        status: AppUpdateCheckStatus.upToDate,
        installedVersion: '1.0.0',
        installedBuild: 1,
      );
}

ProcessTreeView _treeWithRows(
  List<ProcessTreeRow> rows, {
  ProcessIdentity? selectedIdentity,
  String treeSearchQuery = '',
  ProcessTreeLockState lock = const ProcessTreeLockState.unlocked(),
}) {
  final searchedRows = rows
      .map((row) => _rowWithSearch(row, treeSearchQuery))
      .toList(growable: false);
  final matchingRows = searchedRows
      .where((row) => row.matchesTreeSearch)
      .toList(growable: false);
  final selectedMatchIndex = matchingRows.indexWhere(
    (row) => row.matchesTreeSearch && row.identity == selectedIdentity,
  );
  return ProcessTreeView(
    snapshot: ProcessSnapshot(
      generatedAtUnixMs: 1,
      platform: 'test',
      processes: searchedRows.map((row) => row.record).toList(),
    ),
    visibleRows: searchedRows,
    expandedIdentities: const <ProcessIdentity>{},
    selectedIdentity: selectedIdentity,
    filter: '',
    treeSearchQuery: treeSearchQuery,
    treeSearchMatchCount: matchingRows.length,
    treeSearchSelectedMatchIndex: selectedMatchIndex,
    searchOptions: const ProcessSearchOptions(),
    lock: lock,
    sortColumn: ProcessSortColumn.treeCpu,
    sortDirection: ProcessSortDirection.descending,
    pinnedIdentities: const <ProcessIdentity>{},
    focusedIdentity: null,
    focusStack: const <ProcessIdentity>[],
    focusedProcessName: null,
    cpuScaleMax: 1,
  );
}

ProcessTreeRow _row({
  required ProcessIdentity identity,
  required ProcessRecord process,
  bool hasChildren = false,
  List<double> cpuHistory = const <double>[],
}) {
  return ProcessTreeRow(
    identity: identity,
    record: process,
    iconPath: null,
    depth: 0,
    treeCpuUsage: process.cpuUsage,
    treeGpuUsage: process.gpuUsage,
    treeRssBytes: process.rssBytes,
    treeNetworkInBytesPerSecond: process.networkInBytesPerSecond,
    treeNetworkOutBytesPerSecond: process.networkOutBytesPerSecond,
    processCpuHistory: const <double>[],
    processGpuHistory: const <double>[],
    processRssHistory: const <double>[],
    processNetworkInHistory: const <double>[],
    processNetworkOutHistory: const <double>[],
    cpuHistory: cpuHistory,
    gpuHistory: const <double>[],
    rssHistory: const <double>[],
    networkInHistory: const <double>[],
    networkOutHistory: const <double>[],
    descendantCount: hasChildren ? 1 : 0,
    hasChildren: hasChildren,
    isExpanded: hasChildren,
    matchesFilter: false,
    preservesFilterBranch: false,
    matchesTreeSearch: false,
    treeSearchMatchedColumnIds: const <String>{},
    changeMarker: ProcessChangeMarker.none,
  );
}

ProcessTreeRow _rowWithSearch(ProcessTreeRow row, String query) {
  final normalized = query.toLowerCase();
  final matchesTreeSearch =
      normalized.isNotEmpty &&
      (row.record.name.toLowerCase().contains(normalized) ||
          row.record.pid.toString().contains(normalized) ||
          row.record.executablePath.toLowerCase().contains(normalized) ||
          row.record.commandLine.toLowerCase().contains(normalized) ||
          row.record.appBundlePath.toLowerCase().contains(normalized));
  return ProcessTreeRow(
    identity: row.identity,
    record: row.record,
    iconPath: row.iconPath,
    depth: row.depth,
    treeCpuUsage: row.treeCpuUsage,
    treeGpuUsage: row.treeGpuUsage,
    treeRssBytes: row.treeRssBytes,
    treeNetworkInBytesPerSecond: row.treeNetworkInBytesPerSecond,
    treeNetworkOutBytesPerSecond: row.treeNetworkOutBytesPerSecond,
    processCpuHistory: row.processCpuHistory,
    processGpuHistory: row.processGpuHistory,
    processRssHistory: row.processRssHistory,
    processNetworkInHistory: row.processNetworkInHistory,
    processNetworkOutHistory: row.processNetworkOutHistory,
    cpuHistory: row.cpuHistory,
    gpuHistory: row.gpuHistory,
    rssHistory: row.rssHistory,
    networkInHistory: row.networkInHistory,
    networkOutHistory: row.networkOutHistory,
    descendantCount: row.descendantCount,
    hasChildren: row.hasChildren,
    isExpanded: row.isExpanded,
    matchesFilter: row.matchesFilter,
    preservesFilterBranch: row.preservesFilterBranch,
    matchesTreeSearch: matchesTreeSearch,
    treeSearchMatchedColumnIds: matchesTreeSearch
        ? const <String>{'name'}
        : const <String>{},
    changeMarker: row.changeMarker,
  );
}

ProcessRecord _process({
  required int pid,
  required String name,
  required int startTimeUnixMs,
  double cpuUsage = 0,
}) {
  return ProcessRecord(
    pid: pid,
    ppid: 1,
    uid: 501,
    user: 'test',
    status: ProcessStatus.running,
    rssBytes: 1024,
    virtualMemoryBytes: 1024,
    cpuTimeNanos: 0,
    threadCount: 0,
    openFileCount: 0,
    nice: 0,
    priority: 0,
    cpuUsage: cpuUsage,
    gpuUsage: 0,
    networkInBytesPerSecond: 0,
    networkOutBytesPerSecond: 0,
    totalNetworkInBytes: 0,
    totalNetworkOutBytes: 0,
    startTimeUnixMs: startTimeUnixMs,
    name: name,
    executablePath: '',
    commandLine: '',
    appBundlePath: '',
  );
}
