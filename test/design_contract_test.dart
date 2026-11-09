import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ProcessLama's UI is built on Meridian (`meridian_ui`). Visible chrome comes
/// from the Meridian primitives and every colour, radius, size and duration
/// from its tokens or the app's `ProcessLamaTheme` extension.
///
/// This contract fails when UI code reaches for Material widgets or
/// hard-coded styling again.
void main() {
  // The theme file defines the app tokens and may hold their values.
  const allowedFiles = {'lib/app/app_theme_data.dart'};
  const uiRoots = ['lib/app', 'lib/screens'];

  final forbidden = <String, RegExp>{
    'Material ink or buttons': RegExp(
      r'(?<!Meridian)\b(InkWell|InkResponse|IconButton|TextButton|'
      r'ElevatedButton|FilledButton|OutlinedButton)\s*[(.]',
    ),
    'Material icons': RegExp(r'\bIcons\.'),
    'Material dialogs, menus and snack bars': RegExp(
      r'\b(showDialog|AlertDialog|SimpleDialog|SnackBar|ScaffoldMessenger|'
      r'PopupMenuButton|showMenu|BottomSheet)\b',
    ),
    'Material inputs and tabs': RegExp(
      r'\b(TextField|Checkbox|Switch|Slider|SegmentedButton|TabBar|'
      r'ListTile|SwitchListTile|CheckboxListTile|Chip|ActionChip)\s*\(',
    ),
    'Material surfaces': RegExp(r'\b(Scaffold|Card|AppBar|Divider)\s*\('),
    'colour literals': RegExp(r'\bColor\(0x|\bColors\.(?!transparent\b)'),
    'font size literals': RegExp(r'fontSize:\s*\d'),
    'radius literals': RegExp(r'Radius\.circular\(\s*\d'),
    'duration literals': RegExp(r'Duration\(\s*(milliseconds|seconds):\s*\d'),
  };

  // Only the screen's resize debounce is a timing, not motion.
  const allowedLines = {
    'static const _resizeEndDelay = Duration(milliseconds: 200);',
  };

  test('UI code uses Meridian primitives and tokens only', () {
    final violations = <String>[];
    for (final root in uiRoots) {
      final files = Directory(root)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      for (final file in files) {
        final path = file.path.replaceAll(r'\', '/');
        if (allowedFiles.contains(path)) {
          continue;
        }
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('//') || allowedLines.contains(line)) {
            continue;
          }
          for (final MapEntry(key: rule, value: pattern) in forbidden.entries) {
            if (pattern.hasMatch(line)) {
              violations.add('$path:${i + 1}: $rule: $line');
            }
          }
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
