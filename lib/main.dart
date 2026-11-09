import 'package:devmil_logging/devmil_logging.dart';
import 'package:flutter/widgets.dart';

import 'app/app_launcher.dart';

void main() {
  installDiagnosticErrorHooks();
  runApp(const AppLauncher());
}
