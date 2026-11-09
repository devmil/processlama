import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import 'remote_host_dialogs.dart';

/// Provides the active tab's session as the [ProcessService] its subtree
/// reads. The subtree is keyed by tab, so switching tabs builds the explorer
/// for the new session while hidden sessions keep their state.
class ActiveProcessSessionScope extends StatelessWidget {
  const ActiveProcessSessionScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tabs = context.read<WorkspaceTabsService>();
    return WorkspaceDialogAnchor(
      child: ValueListenableBuilder<WorkspaceTab>(
        valueListenable: tabs.activeTab,
        builder: (context, tab, _) {
          final session = tabs.sessionFor(tab);
          if (session == null) {
            return child;
          }
          return ProcessSessionScope(
            key: ValueKey<String>(tab.key),
            session: session,
            child: child,
          );
        },
      ),
    );
  }
}

/// Provides [session] as the [ProcessService] of its subtree.
class ProcessSessionScope extends StatelessWidget {
  const ProcessSessionScope({
    super.key,
    required this.session,
    required this.child,
  });

  final ProcessSession session;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Provider<ProcessService>.value(value: session, child: child);
  }
}
