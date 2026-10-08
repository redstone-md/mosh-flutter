import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/message_copy.dart';
import 'package:mosh/src/features/conversation/message_selection_bar.dart';

import '../../support/conversation_cases.dart';
import '../../support/message_selection.dart';

const _body = 'first message';
const _messages = [TestMessage(body: _body, messageId: 'first')];

// Inspect the row's actual painting, including foreground decorations.
// Message bubbles keep their own backgrounds and rounded corners.
void _expectNoRowOutline(WidgetTester tester) {
  final row = tester.renderObject<RenderBox>(
    find.ancestor(of: find.text(_body), matching: find.byType(CopyableMessage)),
  );
  final canvas = TestRecordingCanvas();
  row.paint(TestRecordingPaintingContext(canvas), Offset.zero);
  expect(canvas.invocations, isNotEmpty);
  final outlines = canvas.invocations.where((call) {
    final invocation = call.invocation;
    if (invocation.memberName != #drawDRRect) return false;
    final outer = invocation.positionalArguments.first as RRect;
    return outer.outerRect.size == row.size;
  });
  expect(
    outlines,
    isEmpty,
    reason: 'Message focus must not paint an outline around the row.',
  );
}

Future<void> _keyboardFocus(WidgetTester tester) async {
  final copied = captureClipboard(tester);
  await pumpConversation(
    tester,
    conversationCases().first,
    messages: _messages,
  );
  final focus = Focus.of(tester.element(find.text(_body)));
  focus.requestFocus();
  await tester.pump();
  expect(focus.hasPrimaryFocus, isTrue);
  _expectNoRowOutline(tester);

  await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
  await tester.pumpAndSettle();
  expect(find.text('Copy message'), findsOneWidget);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
  expect(copied, [_body]);
  expect(focus.hasPrimaryFocus, isTrue);
  _expectNoRowOutline(tester);
  await tester.pumpAndSettle();

  await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump(const Duration(milliseconds: 50));
  expect(focus.hasPrimaryFocus, isTrue);
  _expectNoRowOutline(tester);
  await tester.pumpAndSettle();
  await sendPlatformShortcut(tester, LogicalKeyboardKey.keyC);
  expect(copied, [_body, _body]);
}

Future<void> _menuSelection(
  WidgetTester tester,
  ConversationCase conversation,
) async {
  final copied = captureClipboard(tester);
  await pumpConversation(tester, conversation, messages: _messages);
  final focus = Focus.of(tester.element(find.text(_body)));
  await tester.tap(
    find.text(_body),
    buttons: kSecondaryMouseButton,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Select message'));
  await tester.pump(const Duration(milliseconds: 50));
  expect(focus.hasPrimaryFocus, isTrue);
  _expectNoRowOutline(tester);
  await tester.pumpAndSettle();
  expect(find.byType(MessageSelectionBar), findsOneWidget);
  final tint = tester.widget<ColoredBox>(
    find
        .ancestor(of: find.text(_body), matching: find.byType(ColoredBox))
        .first,
  );
  final theme = Theme.of(tester.element(find.text(_body)));
  expect(tint.color, theme.colorScheme.primary.withValues(alpha: 0.16));

  await sendPlatformShortcut(tester, LogicalKeyboardKey.keyC);
  expect(copied, [_body]);
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expect(find.byType(MessageSelectionBar), findsNothing);
  expect(focus.hasPrimaryFocus, isTrue);
  _expectNoRowOutline(tester);
}

void main() {
  setUp(() {
    final manager = FocusManager.instance;
    final strategy = manager.highlightStrategy;
    manager.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => manager.highlightStrategy = strategy);
  });

  testWidgets(
    'keyboard focus and menu dismissal never outline a message row',
    _keyboardFocus,
    variant: TargetPlatformVariant.desktop(),
  );

  for (final conversation in conversationCases()) {
    testWidgets(
      '${conversation.label}: selecting through the menu restores focus '
      'with only the selection tint',
      (tester) => _menuSelection(tester, conversation),
      variant: TargetPlatformVariant.desktop(),
    );
  }
}
