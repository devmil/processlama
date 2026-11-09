import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeLaunchScreen {
  NativeLaunchScreen._();

  static const MethodChannel _channel = MethodChannel(
    'de.devmil.processlama/native_launch_screen',
  );

  static Future<void> dismiss() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('ready');
    } on MissingPluginException {
      // The native launch screen is optional in non-standard test runners.
    }
  }
}
