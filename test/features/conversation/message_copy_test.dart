// Copying message text.
//
// The list's text drag-selects and copies with the platform shortcuts, and
// every text message offers "Copy message": in the selection menu (right-click
// on desktop, long-press on mobile), as Ctrl/Cmd+C on a focused message and
// as a screen-reader action. "Copy message" copies the body alone.
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';

import 'package:mosh/src/rust/outbound_delivery.dart'
    show MessageDeliveryStatus;

import '../../support/conversation_cases.dart';
import '../../support/message_selection.dart';

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

/// A DM holding a message from the peer and an own one that failed, so
/// the list also shows a Retry button.
Future<void> _pump(WidgetTester tester) => pumpConversation(
      tester,
      conversationCases().first,
      messages: _messages,
    );

Future<void> _pressCopyText(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Copy message'));
  await tester.pumpAndSettle();
}

void main() {
  for (final testCase in conversationCases()) {
    testWidgets(
        '${testCase.label}: right-click, Copy message copies the body alone',
        (tester) async {
      final copied = captureClipboard(tester);
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

  testWidgets('long-press, Copy message copies the body alone', (tester) async {
    final copied = captureClipboard(tester);
    await _pump(tester);

    await tester.longPress(find.text('first message'));
    await tester.pump();
    await _pressCopyText(tester);

    expect(copied, ['first message']);
    expect(find.text('Copied'), findsOneWidget);
  }, variant: TargetPlatformVariant.mobile());

  testWidgets('select all and copy takes the texts, not the button labels',
      (tester) async {
    final copied = captureClipboard(tester);
    await _pump(tester);

    await tester.tap(find.text('first message'), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await sendPlatformShortcut(tester, LogicalKeyboardKey.keyA);
    await sendPlatformShortcut(tester, LogicalKeyboardKey.keyC);

    expect(copied, hasLength(1));
    expect(copied.single, contains('first message'));
    expect(copied.single, contains('second message'));
    expect(copied.single, isNot(contains('Retry')));
    expect(copied.single, isNot(contains(formatClock(_sentAt, locale: 'en')!)));
    expect(copied.single, isNot(contains('\uFFFC')));
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('the copy shortcut on a focused message copies its body',
      (tester) async {
    final copied = captureClipboard(tester);
    await _pump(tester);

    Focus.of(tester.element(find.text('second message'))).requestFocus();
    await tester.pump();
    await sendPlatformShortcut(tester, LogicalKeyboardKey.keyC);

    expect(copied, ['second message']);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('screen readers get a Copy message action on each message',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final copied = captureClipboard(tester);
    await _pump(tester);

    tester.semantics.customAction(
      find.semantics.byLabel(RegExp('first message')),
      CustomSemanticsAction(label: 'Copy message'),
    );
    await tester.pump();

    expect(copied, ['first message']);
    semantics.dispose();
  });
}
