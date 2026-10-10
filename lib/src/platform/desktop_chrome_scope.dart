import 'package:flutter/widgets.dart';

/// Route-local headers yield to the application-level desktop titlebar.
class DesktopChromeScope extends InheritedWidget {
  const DesktopChromeScope({super.key, required super.child});

  static bool isPresent(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopChromeScope>() != null;

  @override
  bool updateShouldNotify(DesktopChromeScope oldWidget) => false;
}
