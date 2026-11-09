import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';

import '../di/di.dart' as di;
import '../services/services.dart';
import '../utils/logging_utils.dart';
import 'desktop_window.dart';
import 'processlama_app.dart';

Future<Widget> buildAppRoot({bool forTest = false}) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!forTest) {
    await LoggingUtils.initLogging(logLevel: Level.INFO);
    await configureDesktopWindow();
  }

  await di.initializeComponents(forTest: forTest);

  if (!forTest) {
    // Flush any pending debounced settings writes (e.g. the tail of a resize
    // drag) before the process exits, so the value survives across restarts.
    // The listener self-registers with WidgetsBinding on construction, which
    // keeps it alive; awaiting the flush before returning lets the disk write
    // complete before the process exits.
    AppLifecycleListener(
      onExitRequested: () async {
        await di.getComponentFor<SettingsService>().flush();
        return AppExitResponse.exit;
      },
    );
  }

  return di.createComponentProviderTree(child: const ProcessLamaApp());
}
