// Copying message text.
//
// The list's text drag-selects and copies with the platform shortcuts, and
// every text message offers "Copy text": in the selection menu (right-click
// on desktop, long-press on mobile), as Ctrl/Cmd+C on a focused message and
// as a screen-reader action. "Copy text" copies the body alone.
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/rust/outbound_delivery.dart'
    show MessageDeliveryStatus;

import '../../support/conversation_cases.dart';

final BigInt _sentAt = BigInt.from(1700000000000);

final _messages = [
  TestMessage(body: 'first message', sentAtMs: _sentAt),
  TestMessage.own(
    body: 'second message',
    messageId: 'm2',
    sentAtMs: _sentAt,
    deliveryStatus: MessageDeliveryStatus.failed,
    deliveryError: 'peer offline',
    retryable: true,
  ),
];

/// Records what the app puts on the clipboard.
List<String> _captureClipboard(WidgetTester tester) {
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

/// A DM holding a message from the peer and an own one that failed, so
/// the list also shows a Retry button.
Future<void> _pump(WidgetTester tester) => pumpConversation(
      tester,
      conversationCases().first,
      messages: _messages,
    );

bool get _apple =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

LogicalKeyboardKey get _shortcutModifier =>
    _apple ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;

Future<void> _chord(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(_shortcutModifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(_shortcutModifier);
  await tester.pump();
}

Future<void> _pressCopyText(WidgetTester tester) async {
  await tester.tap(find.text('Copy text'));
  await tester.pump();
}

void main() {
  for (final testCase in conversationCases()) {
    testWidgets(
        '${testCase.label}: right-click, Copy text copies the body alone',
        (tester) async {
      final copied = _captureClipboard(tester);
      await pumpConversation(
        tester,
        testCase,
        messages: [TestMessage(body: 'hello there', sentAtMs: _sentAt)],
      );

      await tester.tap(find.text('hello there'),
          buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await tester.pump();
      await _pressCopyText(tester);

      expect(copied, ['hello there']);
      expect(find.text('Copied'), findsOneWidget);
    }, variant: TargetPlatformVariant.desktop());
  }

  testWidgets('long-press, Copy text copies the body alone', (tester) async {
    final copied = _captureClipboard(tester);
    await _pump(tester);

    await tester.longPress(find.text('first message'));
    await tester.pump();
    await _pressCopyText(tester);

    expect(copied, ['first message']);
    expect(find.text('Copied'), findsOneWidget);
  }, variant: TargetPlatformVariant.mobile());

  testWidgets('select all and copy takes the texts, not the button labels',
      (tester) async {
    final copied = _captureClipboard(tester);
    await _pump(tester);

    await tester.tap(find.text('first message'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await _chord(tester, LogicalKeyboardKey.keyA);
    await _chord(tester, LogicalKeyboardKey.keyC);

    expect(copied, hasLength(1));
    expect(copied.single, contains('first message'));
    expect(copied.single, contains('second message'));
    expect(copied.single, isNot(contains('Retry')));
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('the copy shortcut on a focused message copies its body',
      (tester) async {
    final copied = _captureClipboard(tester);
    await _pump(tester);

    Focus.of(tester.element(find.text('second message'))).requestFocus();
    await tester.pump();
    await _chord(tester, LogicalKeyboardKey.keyC);

    expect(copied, ['second message']);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('screen readers get a Copy text action on each message',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final copied = _captureClipboard(tester);
    await _pump(tester);

    tester.semantics.customAction(
      find.semantics.byLabel(RegExp('first message')),
      CustomSemanticsAction(label: 'Copy text'),
    );
    await tester.pump();

    expect(copied, ['first message']);
    semantics.dispose();
  });
}
