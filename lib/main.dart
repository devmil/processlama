import 'package:devmil_logging/devmil_logging.dart';
import 'package:flutter/widgets.dart';

import 'app/app_launcher.dart';
import 'app/app_licenses.dart';

void main() {
  installDiagnosticErrorHooks();
  registerProcessLamaLicenses();
  runApp(const AppLauncher());
}
