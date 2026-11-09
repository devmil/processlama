import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../l10n/l10n.dart';
import 'app_bootstrap.dart';
import 'app_theme_data.dart';
import 'native_launch_screen.dart';

class AppLauncher extends StatefulWidget {
  const AppLauncher({super.key, this.forTest = false});

  final bool forTest;

  @override
  State<AppLauncher> createState() => _AppLauncherState();
}

class _AppLauncherState extends State<AppLauncher> {
  late final Future<Widget> _appRootFuture;
  bool _launchScreenDismissalScheduled = false;

  @override
  void initState() {
    super.initState();
    _appRootFuture = buildAppRoot(forTest: widget.forTest);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _appRootFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          _scheduleLaunchScreenDismissal();
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            onGenerateTitle: (context) => context.l10n.appTitle,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildProcessLamaTheme(),
            darkTheme: buildProcessLamaTheme(brightness: Brightness.dark),
            home: _BootstrapErrorScreen(
              error: snapshot.error!,
              stackTrace: snapshot.stackTrace,
            ),
          );
        }

        if (snapshot.hasData) {
          _scheduleLaunchScreenDismissal();
          return snapshot.data!;
        }

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          onGenerateTitle: (context) => context.l10n.appTitle,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildProcessLamaTheme(),
          darkTheme: buildProcessLamaTheme(brightness: Brightness.dark),
          home: const _BootstrapLoadingScreen(),
        );
      },
    );
  }

  void _scheduleLaunchScreenDismissal() {
    if (_launchScreenDismissalScheduled || widget.forTest) {
      return;
    }
    _launchScreenDismissalScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(NativeLaunchScreen.dismiss());
    });
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({required this.error, this.stackTrace});

  final Object error;
  final StackTrace? stackTrace;

  @override
  Widget build(BuildContext context) {
    final meridian = context.meridian;
    final details = stackTrace == null ? '$error' : '$error\n\n$stackTrace';

    return MeridianGround(
      child: Padding(
        padding: const EdgeInsets.all(MeridianSpace.space3),
        child: MeridianIsland(
          expandChild: true,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(MeridianSpace.space9),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: MeridianLayout.dialogMaxWidth,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MeridianIcon(
                      MeridianIcons.circleX,
                      extent: MeridianLayout.emptyStateIconSize,
                      color: meridian.colors.danger,
                    ),
                    const SizedBox(height: MeridianSpace.space5),
                    Text(
                      context.l10n.bootstrapErrorTitle,
                      style: meridian.text.title,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: MeridianSpace.space3),
                    Text(
                      context.l10n.bootstrapErrorDescription,
                      style: meridian.text.body.copyWith(
                        color: meridian.colors.inkMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: MeridianSpace.space7),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: meridian.colors.paneAlt,
                        borderRadius: BorderRadius.circular(meridian.radius.md),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(MeridianSpace.space5),
                        child: SelectableText(
                          details,
                          style: meridian.text.codeSm.copyWith(
                            color: meridian.colors.inkMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BootstrapLoadingScreen extends StatelessWidget {
  const _BootstrapLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const MeridianGround(
      child: Center(child: MeridianSpinner(size: MeridianSpace.space8)),
    );
  }
}
