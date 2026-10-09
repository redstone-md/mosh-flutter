import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Enter selection through the same menu action users invoke.
Future<void> startMessageSelection(WidgetTester tester, String body,
    {String label = 'Select message'}) async {
  await tester.tap(find.text(body),
      buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

/// Capture caller-visible clipboard writes without touching the OS clipboard.
List<String> captureClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

Future<void> sendPlatformShortcut(
    WidgetTester tester, LogicalKeyboardKey key) async {
  final apple = defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  final modifier =
      apple ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

/// Keep consecutive mouse clicks inside Flutter's multi-click time window.
Future<void> clickMessage(WidgetTester tester, Offset point,
    {int buttons = kPrimaryMouseButton}) async {
  await tester.tapAt(point, buttons: buttons, kind: PointerDeviceKind.mouse);
  await tester.pump(const Duration(milliseconds: 80));
}
