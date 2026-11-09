// The remote hosts flow in the real app against an Ubuntu 22.04 sshd
// container (scripts/verify_remote_hosts.py --ui): add a host through the
// `+` menu, test it, install the helper through the dialog, stream its tree,
// terminate a process through the confirmation that names the host, turn
// stale while the container is paused and recover, and remove the helper
// from Settings. With PROCESSLAMA_SCREENSHOT_DIR it stores screenshots of
// the tab strip, the `+` menu, the remote tab and the stale banner at 1180
// px and at the 900 px window minimum.
@TestOn('linux')
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:processlama/app/app_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _fixture(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    throw StateError('run through scripts/verify_remote_hosts.py --ui ($name)');
  }
  return value;
}

const _root = ValueKey('screenshot-root');

/// The narrowest window: minimumDesktopWindowSize. The 640 px layouts of
/// the strip and banner are covered by test/screens/remote_hosts_ui_test.dart.
const _narrow = 900.0;

Future<void> _settle(WidgetTester tester, [int frames = 5]) async {
  for (var frame = 0; frame < frames; frame++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
  }
}

Future<void> _until(
  WidgetTester tester,
  bool Function() condition,
  String what, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out after ${timeout.inSeconds} s waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
}

Future<void> _width(WidgetTester tester, double width) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 760);
  await _settle(tester);
}

Future<void> _screenshot(WidgetTester tester, String name) async {
  final directory = Platform.environment['PROCESSLAMA_SCREENSHOT_DIR'];
  if (directory == null || directory.isEmpty) {
    return;
  }
  await _settle(tester, 10);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_root),
  );
  final image = await boundary.toImage(pixelRatio: 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  await File(
    '$directory/$name.png',
  ).writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
}

/// podman with its storage where the lane's container lives: the app's
/// own XDG_DATA_HOME points elsewhere.
Future<ProcessResult> _podman(List<String> arguments) => Process.run(
  'podman',
  arguments,
  environment: {'XDG_DATA_HOME': _fixture('PROCESSLAMA_PODMAN_XDG_DATA_HOME')},
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('remote host: add, install, stream, stale, recover, remove', (
    tester,
  ) async {
    final alias = _fixture('PROCESSLAMA_TEST_ALIAS');
    final container = _fixture('PROCESSLAMA_TEST_CONTAINER');
    // Settings stay in memory: the run never touches the user's profiles.
    SharedPreferences.setMockInitialValues({});
    addTearDown(tester.view.reset);
    final sleeper = await _podman([
      'exec',
      '--user',
      'tester',
      '--detach',
      container,
      'sleep',
      '600',
    ]);
    expect(sleeper.exitCode, 0);

    await tester.pumpWidget(
      const RepaintBoundary(key: _root, child: AppLauncher()),
    );
    await _width(tester, 1180);
    await _until(
      tester,
      () => find
          .byKey(const ValueKey('workspace-tab-strip'))
          .evaluate()
          .isNotEmpty,
      'the window',
    );
    await _screenshot(tester, 'tab-strip-local-1180');

    // + → Add remote host…, test the connection, save.
    await tester.tap(find.bySemanticsLabel('Open remote host'));
    await _settle(tester);
    await _screenshot(tester, 'plus-menu-1180');
    await tester.tap(find.text('Add remote host…'));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('remote-host-alias')),
      alias,
    );
    await tester.tap(find.byKey(const ValueKey('remote-host-test')));
    await _until(
      tester,
      () => find.text('Helper missing').evaluate().isNotEmpty,
      'the probe to report the missing helper',
    );
    await tester.tap(find.byKey(const ValueKey('remote-host-save')));

    // The install dialog, then the tree.
    await _until(
      tester,
      () => find.text('Install helper on $alias?').evaluate().isNotEmpty,
      'the install dialog',
    );
    await _screenshot(tester, 'install-dialog-1180');
    await tester.tap(find.text('Install'));
    await _until(
      tester,
      () => find.text('sleep').evaluate().isNotEmpty,
      'the remote tree',
      timeout: const Duration(seconds: 90),
    );
    await _settle(tester, 20);
    await _screenshot(tester, 'remote-tab-1180');
    await _width(tester, _narrow);
    await _screenshot(tester, 'remote-tab-900');
    await tester.tap(find.bySemanticsLabel('Open remote host'));
    await _settle(tester);
    await _screenshot(tester, 'plus-menu-900');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    await _width(tester, 1180);

    // Terminate the sleeper; the confirmation names the host.
    await tester.tap(find.text('sleep'), buttons: kSecondaryButton);
    await _settle(tester);
    await tester.tap(find.text('Terminate process'));
    await _settle(tester);
    expect(find.textContaining('on $alias'), findsOne);
    await tester.tap(find.text('Terminate process').last);
    await _until(
      tester,
      () => find.text('sleep').evaluate().isEmpty,
      'the terminated process to leave',
    );

    // Local keeps its own tree; switching back shows the host again.
    await tester.tap(find.byKey(const ValueKey('workspace-tab-local')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('remote-status-host')), findsNothing);
    await tester.tap(find.text(alias).first);
    await _settle(tester);
    expect(find.byKey(const ValueKey('remote-status-host')), findsOne);

    // Pause the host: after the heartbeat window the tab turns stale.
    expect((await _podman(['pause', container])).exitCode, 0);
    var paused = true;
    addTearDown(() async {
      if (paused) await _podman(['unpause', container]);
    });
    await _until(
      tester,
      () => find.textContaining('Reconnecting to').evaluate().isNotEmpty,
      'the stale banner',
      timeout: const Duration(seconds: 120),
    );
    expect(find.textContaining('Showing data from'), findsOne);
    await _screenshot(tester, 'stale-banner-1180');
    await _width(tester, _narrow);
    await _screenshot(tester, 'stale-banner-900');
    await _width(tester, 1180);
    expect((await _podman(['unpause', container])).exitCode, 0);
    paused = false;
    await _until(
      tester,
      () => find.byKey(const ValueKey('remote-tab-banner')).evaluate().isEmpty,
      'the tab to recover',
      timeout: const Duration(minutes: 3),
    );

    // Settings → Remote hosts → Remove helper from host…
    await tester.tap(find.bySemanticsLabel('Open remote host'));
    await _settle(tester);
    await tester.tap(find.text('Manage remote hosts…'));
    await _settle(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('remote-hosts-settings')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await _screenshot(tester, 'settings-remote-hosts-1180');
    await tester.tap(find.bySemanticsLabel('Actions for $alias'));
    await _settle(tester);
    await tester.tap(find.text('Remove helper from host…'));
    await _settle(tester);
    await tester.tap(find.text('Remove helper'));
    await _until(
      tester,
      () => find.text('Helper removed from $alias.').evaluate().isNotEmpty,
      'the helper removal',
    );
  });
}
