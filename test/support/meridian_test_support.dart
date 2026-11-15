import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';

/// A bare tap target for test fixtures that only need something to press
/// (the app itself uses Meridian buttons).
class TestButton extends StatelessWidget {
  const TestButton({required this.onPressed, required this.child, super.key});

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onPressed,
    child: child,
  );
}

/// `find.byTooltip` for Meridian: also finds a `MeridianTooltip` that is
/// excluded from semantics (flutter_test's finder sees only the semantic
/// tooltip of the widgets layer's `RawTooltip`).
Finder findTooltip(Pattern message) {
  bool matches(String? text) =>
      message is RegExp ? message.hasMatch(text ?? '') : text == message;
  return find.byWidgetPredicate((widget) {
    if (widget is MeridianTooltip && widget.excludeFromSemantics) {
      return matches(widget.message ?? widget.richMessage?.toPlainText());
    }
    return widget is RawTooltip && matches(widget.semanticsTooltip);
  });
}
