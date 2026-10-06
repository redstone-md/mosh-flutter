// IVO-25: picking messages for a bulk action, Telegram-style. The selection
// bar replaces the chat header, picked rows are tinted rather than
// checkboxed, and a tap anywhere on a row picks it.
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_app_bar.dart';
import 'package:mosh/src/features/conversation/conversation_search_box.dart';
import 'package:mosh/src/features/conversation/message_selection_bar.dart';

import '../../support/conversation_cases.dart';
import '../../support/message_selection.dart';
import '../../support/scriptable_gateway.dart';

final _messages = [
  for (final (i, body) in ['first', 'second', 'third', 'fourth'].indexed)
    TestMessage(
        body: '$body note',
        messageId: 'm$i',
        sentAtMs: BigInt.from(1700000000000 + i * 1000)),
];

Future<void> _startSelecting(WidgetTester tester, String body) async {
  await tester.tap(find.text(body),
      buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Select message'));
  await tester.pumpAndSettle();
}

Finder get _bar => find.byType(MessageSelectionBar);

/// The bar's count sits next to the Delete label.
void _expectPicked(int count) {
  expect(_bar, findsOneWidget);
  expect(
      find.descendant(
          of: find.widgetWithText(FilledButton, 'Delete'),
          matching: find.text('$count')),
      findsOneWidget);
}

Color? _tint(WidgetTester tester, String body) => tester
    .widget<ColoredBox>(find
        .ancestor(of: find.text(body), matching: find.byType(ColoredBox))
        .first)
    .color;

void main() {
  for (final c in conversationCases()) {
    testWidgets('${c.label}: the selection bar replaces the header',
        (tester) async {
      await pumpConversation(tester, c, messages: _messages);
      final header = find.byType(ConversationAppBar);
      expect(header, findsOneWidget);
      await _startSelecting(tester, 'second note');
      _expectPicked(1);
      expect(header, findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(_bar, findsNothing);
      expect(header, findsOneWidget);
    });
  }

  final dm = conversationCases().first;

  testWidgets('a tap anywhere on a row picks it and tints it', (tester) async {
    await pumpConversation(tester, dm, messages: _messages);
    await _startSelecting(tester, 'second note');
    expect(_tint(tester, 'first note'), Colors.transparent);
    await tester.tapAt(
        tester.getTopRight(find.text('first note')) + const Offset(120, 4));
    await tester.pumpAndSettle();
    _expectPicked(2);
    expect(_tint(tester, 'first note'), isNot(Colors.transparent));
  });

  testWidgets('the last deselection leaves the mode', (tester) async {
    await pumpConversation(tester, dm, messages: _messages);
    await _startSelecting(tester, 'second note');
    await tester.tap(find.text('second note'));
    await tester.pumpAndSettle();
    expect(_bar, findsNothing);
  });

  testWidgets('Escape leaves the mode', (tester) async {
    await pumpConversation(tester, dm, messages: _messages);
    await _startSelecting(tester, 'second note');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_bar, findsNothing);
  });

  testWidgets('system back leaves the mode before the chat', (tester) async {
    await pumpConversation(tester, dm, messages: _messages);
    await _startSelecting(tester, 'second note');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_bar, findsNothing);
    expect(find.text('second note'), findsOneWidget);
  });

  testWidgets('Shift extends the pick from the last picked row',
      (tester) async {
    await pumpConversation(tester, dm, messages: _messages);
    await _startSelecting(tester, 'first note');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('fourth note'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    _expectPicked(4);
  });

  testWidgets('the copy shortcut copies picked messages oldest first',
      (tester) async {
    final copied = captureClipboard(tester);
    await pumpConversation(tester, dm, messages: _messages);
    await _startSelecting(tester, 'third note');
    await tester.tap(find.text('first note'));
    await tester.pumpAndSettle();
    await sendPlatformShortcut(tester, LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(copied, ['first note\n\nthird note']);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('row controls rest while picking', (tester) async {
    await pumpConversation(tester, dm, messages: _messages);
    await _startSelecting(tester, 'second note');
    await tester.tap(find.text('third note'),
        buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text('Select message'), findsNothing);
    _expectPicked(1);
  });

  testWidgets('search narrows the pick to the messages it shows',
      (tester) async {
    final gateway = ScriptableGateway();
    await pumpConversation(tester, dm, gateway: gateway, messages: _messages);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await _startSelecting(tester, 'first note');
    await tester.tap(find.text('second note'));
    await tester.pumpAndSettle();
    _expectPicked(2);
    await tester.enterText(
        find.descendant(
            of: find.byType(ConversationSearchBox),
            matching: find.byType(TextField)),
        'second');
    await tester.pumpAndSettle();
    _expectPicked(1);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete for me'));
    await tester.pumpAndSettle();
    expect(
        gateway
            .lastCall(GatewayMethod.deleteMessages)!
            .arg<List<String>>('messageIds'),
        ['m1']);
  });
}
