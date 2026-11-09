import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/models.dart';
import '../screens/process_explorer_screen.dart';
import '../screens/workspace_tabs/process_session_scope.dart';
import '../services/services.dart';
import 'app_theme_data.dart';
import 'desktop_window.dart';

class ProcessLamaApp extends StatelessWidget {
  const ProcessLamaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsService = context.read<SettingsService>();
    return DesktopWindowShortcuts(
      child: ValueListenableBuilder<AppSettings>(
        valueListenable: settingsService.settings,
        builder: (context, settings, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            onGenerateTitle: (context) => context.l10n.appTitle,
            locale: Locale(settings.languageCode),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildProcessLamaTheme(density: settings.rowDensity),
            darkTheme: buildProcessLamaTheme(
              brightness: Brightness.dark,
              density: settings.rowDensity,
            ),
            themeMode: switch (settings.appearanceMode) {
              AppAppearanceMode.light => ThemeMode.light,
              AppAppearanceMode.dark => ThemeMode.dark,
              AppAppearanceMode.system => ThemeMode.system,
            },
            home: Builder(
              builder: (context) {
                final media = MediaQuery.of(context);
                return MediaQuery(
                  data: media.copyWith(
                    disableAnimations: media.disableAnimations,
                    accessibleNavigation: media.accessibleNavigation,
                  ),
                  child: const DesktopWindowSurface(
                    child: ActiveProcessSessionScope(
                      child: ProcessExplorerScreen(),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
