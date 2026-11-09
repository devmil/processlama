import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'platform_capabilities.dart';

const Size defaultDesktopWindowSize = Size(1180, 760);
const Size minimumDesktopWindowSize = Size(900, 560);

Future<void> configureDesktopWindow({
  String title = 'ProcessLama',
  Size initialSize = defaultDesktopWindowSize,
  Size minimumSize = minimumDesktopWindowSize,
}) async {
  if (!PlatformCapabilities.isDesktop) {
    return;
  }

  await windowManager.ensureInitialized();

  final options = WindowOptions(
    size: initialSize,
    minimumSize: minimumSize,
    center: true,
    title: title,
    // Linux already has a hidden native titlebar. Retain its CSD decorations
    // for rounded borders, shadows and resize edges.
    titleBarStyle: PlatformCapabilities.isLinux
        ? null
        : PlatformCapabilities.isMacOS
        ? TitleBarStyle.hidden
        : TitleBarStyle.normal,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setTitle(title);
    await windowManager.setMinimumSize(minimumSize);
    await windowManager.show();
    await windowManager.focus();
  });
}

class DesktopWindowShortcuts extends StatelessWidget {
  const DesktopWindowShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!PlatformCapabilities.isDesktop) {
      return child;
    }

    return Actions(
      actions: <Type, Action<Intent>>{
        _ToggleDesktopFullscreenIntent:
            CallbackAction<_ToggleDesktopFullscreenIntent>(
              onInvoke: (_) {
                _toggleDesktopFullscreen();
                return null;
              },
            ),
      },
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.f11):
              _ToggleDesktopFullscreenIntent(),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }

  Future<void> _toggleDesktopFullscreen() async {
    final isFullScreen = await windowManager.isFullScreen();
    await windowManager.setFullScreen(!isFullScreen);
  }
}

class _ToggleDesktopFullscreenIntent extends Intent {
  const _ToggleDesktopFullscreenIntent();
}

/// Keeps the narrow native Linux frame continuous with the app's surface.
class DesktopWindowSurface extends StatefulWidget {
  const DesktopWindowSurface({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopWindowSurface> createState() => _DesktopWindowSurfaceState();
}

class _DesktopWindowSurfaceState extends State<DesktopWindowSurface> {
  Color? _background;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!PlatformCapabilities.isLinux) return;
    final background = Theme.of(context).scaffoldBackgroundColor;
    if (_background == background) return;
    _background = background;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _background == background) {
        windowManager.setBackgroundColor(background);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
