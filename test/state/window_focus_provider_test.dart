import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/state/window_focus_provider.dart';

void main() {
  // An iPhone has no window to focus; an app sent to the background must not
  // pass for focused, or no message there raises a notification.
  testWidgets('an iOS app is focused only while in the foreground',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final isFocused = container.read(windowFocusProvider);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(await isFocused(), isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(await isFocused(), isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
