import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:processlama/app/desktop_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  const screenChannel = MethodChannel(
    'dev.leanflutter.plugins/screen_retriever',
  );
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method.startsWith('is')) return false;
          if (call.method == 'getBounds') {
            return {'x': 0.0, 'y': 0.0, 'width': 1180.0, 'height': 760.0};
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(screenChannel, (call) async {
          final display = {
            'id': 'test-display',
            'size': {'width': 1920.0, 'height': 1080.0},
            'visiblePosition': {'dx': 0.0, 'dy': 0.0},
            'visibleSize': {'width': 1920.0, 'height': 1080.0},
            'scaleFactor': 1.0,
          };
          if (call.method == 'getAllDisplays') {
            return {
              'displays': [display],
            };
          }
          if (call.method == 'getCursorScreenPoint') {
            return {'dx': 0.0, 'dy': 0.0};
          }
          return display;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(screenChannel, null);
  });

  test('Linux preserves the native rounded window decorations', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await configureDesktopWindow();
    // The ready callback is asynchronous, so drain its platform calls.
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((call) => call.method), contains('show'));
    expect(
      calls.map((call) => call.method),
      isNot(contains('setTitleBarStyle')),
    );
    expect(calls.map((call) => call.method), isNot(contains('setAsFrameless')));
  });

  testWidgets('Linux native frame follows light and dark app backgrounds', (
    tester,
  ) async {
    Future<void> show(Color color) => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: color),
        themeAnimationDuration: Duration.zero,
        home: const DesktopWindowSurface(child: SizedBox()),
      ),
    );
    await show(Colors.white);
    await tester.pump();
    var backgrounds = calls.where(
      (call) => call.method == 'setBackgroundColor',
    );
    expect(backgrounds, hasLength(1));
    expect((backgrounds.last.arguments as Map)['backgroundColorR'], 255);
    await show(Colors.white);
    await tester.pump();
    expect(backgrounds, hasLength(1));
    await show(Colors.black);
    await tester.pump();
    expect(backgrounds, hasLength(2));
    expect((backgrounds.last.arguments as Map)['backgroundColorR'], 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Other platforms keep their native window surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: DesktopWindowSurface(child: SizedBox())),
    );
    await tester.pump();
    expect(calls.where((call) => call.method == 'setBackgroundColor'), isEmpty);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    test('$platform keeps its existing title bar setup', () async {
      debugDefaultTargetPlatformOverride = platform;
      await configureDesktopWindow();
      await Future<void>.delayed(Duration.zero);
      final call = calls.singleWhere(
        (call) => call.method == 'setTitleBarStyle',
      );
      expect(
        (call.arguments as Map)['titleBarStyle'],
        platform == TargetPlatform.macOS ? 'hidden' : 'normal',
      );
    });
  }
}
