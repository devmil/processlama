import 'package:logging/logging.dart';
import 'package:devmil_logging/devmil_logging.dart';
import '../logging/diagnostic_policy.dart';

class LoggingUtils {
  const LoggingUtils._();
  static DiagnosticLease? _lease;
  static Future<void> initLogging({Level logLevel = Level.INFO}) async {
    configureDiagnosticPolicy();
    _lease ??= DiagnosticHistory.instance.acquire();
    Logger('Startup').info(const DiagnosticEvent('startup_diagnostics_ready'));
  }

  static Future<void> cleanup() async {
    final lease = _lease;
    _lease = null;
    await lease?.close();
  }
}
