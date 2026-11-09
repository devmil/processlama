import 'package:devmil_logging/devmil_logging.dart';

// Reviewed static product messages. Interpolated legacy text and external
// exceptions are excluded. Add typed DiagnosticEvent numeric fields for new sites.
const _reviewedMessages = <String>{
  "Failed to apply process snapshot.",
  "Failed to configure process icon cache; falling back to Rust default.",
  "Failed to refresh process inspector detail.",
  "Failed to refresh process snapshot.",
  "Rust core unavailable; using bootstrap snapshot.",
  "remote_icon_cache_unavailable",
  "remote_icons_not_stored",
  "workspace_tab_unavailable",
  "workspace_tabs_save_failed",
};

const _reviewedComponents = <String>{
  "LocalProcessSource",
  "ProcessIconService",
  "ProcessService",
  "RemoteHostService",
  "RemoteProcessSource",
  "RustProcessRepository",
  "Startup",
  "WorkspaceTabsService",
};

void configureDiagnosticPolicy() {
  DiagnosticHistory.instance.formatReviewedRecord = (record) {
    final component = _reviewedComponents.contains(record.loggerName)
        ? record.loggerName
        : 'component';
    final Object event = record.object ?? record.message;
    return event is String && _reviewedMessages.contains(event)
        ? '$component: $event'
        : null;
  };
}
