// Shared message selection behavior and Telegram-style selection controls.
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/conversation_app_bar.dart';
import 'package:mosh/src/features/conversation/conversation_search_box.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
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

Finder get _bar => find.byType(MessageSelectionBar);

/// The count stays visible independently of the actions.
void _expectPicked(int count) {
  expect(_bar, findsOneWidget);
  expect(find.descendant(of: _bar, matching: find.text('Selected: $count')),
      findsOneWidget);
}

Color? _bubbleColor(WidgetTester tester, String id) => (tester
        .widget<Container>(find.byKey(ValueKey('message-bubble-$id')))
        .decoration as BoxDecoration)
    .color;

void main() {
  for (final c in conversationCases()) {
    testWidgets('${c.label}: the selection bar replaces the header',
        (tester) async {
      await pumpConversation(tester, c, messages: _messages);
      final header = find.byType(ConversationAppBar);
      expect(header, findsOneWidget);
      await startMessageSelection(tester, 'second note');
      _expectPicked(1);
      expect(header, findsNothing);
      expect(find.byType(Checkbox), findsNWidgets(4));
      final selectors = tester.widgetList<Checkbox>(find.byType(Checkbox));
      expect(
          selectors.where((selector) => selector.value == true), hasLength(1));
      expect(selectors.every((selector) => selector.shape is CircleBorder),
          isTrue);
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(_bar, findsNothing);
      expect(header, findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
    });
  }

  final dm = conversationCases().first;

  for (final c in conversationCases()) {
    testWidgets(
        '${c.label}: mobile actions replace the composer and keep its draft',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final copied = captureClipboard(tester);
      await pumpConversation(tester, c, messages: _messages);
      await tester.enterText(find.byType(TextField), 'draft to keep');
      final editable =
          tester.state<EditableTextState>(find.byType(EditableText));
      await startMessageSelection(tester, 'third note');
      _expectPicked(1);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(ConversationComposer), findsNothing);
      expect(
          find.descendant(of: _bar, matching: find.text('Copy')), findsNothing);
      expect(tester.getTopLeft(find.text('Copy')).dy,
          greaterThan(tester.getBottomRight(find.text('fourth note')).dy));
      final selector = find.byKey(const ValueKey('message-selector-m0'));
      expect(tester.getRect(selector).right,
          lessThan(tester.getRect(find.text('first note')).left));
      await tester.tap(selector);
      await tester.pumpAndSettle();
      _expectPicked(2);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(copied, ['first note\n\nthird note']);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('draft to keep'), findsOneWidget);
      expect(tester.state<EditableTextState>(find.byType(EditableText)),
          same(editable));
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.mobile());
  }

  testWidgets('a tap anywhere on a row picks it and tints only its bubble',
      (tester) async {
    await pumpConversation(tester, dm, messages: _messages);
    final firstColor = _bubbleColor(tester, 'm0');
    final secondColor = _bubbleColor(tester, 'm1');
    await startMessageSelection(tester, 'second note');
    expect(_bubbleColor(tester, 'm0'), firstColor);
    expect(_bubbleColor(tester, 'm1'), isNot(secondColor));
    await tester.tapAt(
        tester.getTopRight(find.text('first note')) + const Offset(120, 4));
    await tester.pumpAndSettle();
    _expectPicked(2);
    expect(_bubbleColor(tester, 'm0'), isNot(firstColor));
  });

  testWidgets('the last deselection leaves the mode', (tester) async {
    await pumpConversation(tester, dm, messages: _messages);
    await startMessageSelection(tester, 'second note');
    await tester.tap(find.text('second note'));
    await tester.pumpAndSettle();
    expect(_bar, findsNothing);
  });

  testWidgets('Escape leaves the mode', (tester) async {
    await pumpConversation(tester, dm, messages: _messages);
    await startMessageSelection(tester, 'second note');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_bar, findsNothing);
  });

  testWidgets('screen readers only get the pick action while picking',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpConversation(tester, dm, messages: _messages);
      await startMessageSelection(tester, 'second note');
      final labels = tester
          .getSemantics(find.text('first note'))
          .getSemanticsData()
          .customSemanticsActionIds!
          .map((id) => CustomSemanticsAction.getAction(id)!.label);
      expect(labels, ['Select message']);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('system back leaves the mode before the chat', (tester) async {
    await pumpConversation(tester, dm, messages: _messages);
    await startMessageSelection(tester, 'second note');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_bar, findsNothing);
    expect(find.text('second note'), findsOneWidget);
  });

  testWidgets('Shift extends the pick from the last picked row',
      (tester) async {
    await pumpConversation(tester, dm, messages: _messages);
    await startMessageSelection(tester, 'first note');
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
    await startMessageSelection(tester, 'third note');
    await tester.tap(find.text('first note'));
    await tester.pumpAndSettle();
    await sendPlatformShortcut(tester, LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(copied, ['first note\n\nthird note']);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('row controls rest while picking', (tester) async {
    await pumpConversation(tester, dm, messages: _messages);
    await startMessageSelection(tester, 'second note');
    await tester.tap(find.text('third note'),
        buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text('Select message'), findsNothing);
    _expectPicked(1);
  });

  testWidgets('the desktop toolbar copies picked messages oldest first',
      (tester) async {
    final copied = captureClipboard(tester);
    await pumpConversation(tester, dm, messages: _messages);
    await startMessageSelection(tester, 'third note');
    await tester.tap(find.text('first note'));
    await tester.pumpAndSettle();
    _expectPicked(2);
    final copy = find.descendant(of: _bar, matching: find.text('Copy'));
    expect(copy, findsOneWidget);
    expect(find.descendant(of: _bar, matching: find.text('Delete')),
        findsOneWidget);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(copied, ['first note\n\nthird note']);
    _expectPicked(2);
    final focus = Focus.of(tester.element(copy));
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);
    await sendPlatformShortcut(tester, LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(copied, ['first note\n\nthird note', 'first note\n\nthird note']);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('search narrows the pick to the messages it shows',
      (tester) async {
    final gateway = ScriptableGateway();
    await pumpConversation(tester, dm, gateway: gateway, messages: _messages);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await startMessageSelection(tester, 'first note');
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
