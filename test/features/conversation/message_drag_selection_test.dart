// IVO-25: dragging across messages picks them. A mouse drag that leaves
// its message switches from text to messages; on touch a long press starts
// the drag while picking, and plain swipes still scroll.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/message_selection_bar.dart';

import '../../support/conversation_cases.dart';
import '../../support/message_selection.dart';

List<TestMessage> _notes(int count) => [
      for (var i = 0; i < count; i++)
        TestMessage(
            body: 'note $i',
            messageId: 'm$i',
            sentAtMs: BigInt.from(1700000000000 + i * 1000)),
    ];

final _dm = conversationCases().first;

/// The bar's count, or null when nothing is being picked.
int? _picked(WidgetTester tester) {
  final bar = find.byType(MessageSelectionBar);
  return bar.evaluate().isEmpty
      ? null
      : tester.widget<MessageSelectionBar>(bar).count;
}

/// How many rows lie fully inside the list's viewport.
int _shown(WidgetTester tester, Rect list) => find
    .textContaining('note ')
    .evaluate()
    .where((e) => list.contains(tester.getCenter(find.byWidget(e.widget))))
    .length;

double _scrolled(WidgetTester tester) => tester
    .state<ScrollableState>(find
        .descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable))
        .first)
    .position
    .pixels;

Offset _at(WidgetTester tester, String body) =>
    tester.getCenter(find.text(body));

Future<void> _mouseDrag(WidgetTester tester, List<String> path) async {
  final gesture = await tester.startGesture(_at(tester, path.first),
      kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
  for (final body in path.skip(1)) {
    await gesture.moveTo(_at(tester, body));
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _startSelecting(WidgetTester tester, String body) async {
  await tester.tap(find.text(body),
      buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Select message'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a mouse drag into another message picks the range',
      (tester) async {
    final copied = captureClipboard(tester);
    await pumpConversation(tester, _dm, messages: _notes(4));
    await _mouseDrag(tester, ['note 0', 'note 1', 'note 2']);
    expect(_picked(tester), 3);
    await sendPlatformShortcut(tester, LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(copied, ['note 0\n\nnote 1\n\nnote 2']);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('dragging back returns rows the range left', (tester) async {
    await pumpConversation(tester, _dm, messages: _notes(4));
    await _mouseDrag(tester, ['note 0', 'note 2', 'note 1']);
    expect(_picked(tester), 2);
  });

  testWidgets('a drag inside one message still selects its text',
      (tester) async {
    final copied = captureClipboard(tester);
    await pumpConversation(tester, _dm, messages: _notes(2));
    final text = find.text('note 1');
    final gesture = await tester.startGesture(
        tester.getTopLeft(text) + const Offset(1, 4),
        kind: PointerDeviceKind.mouse);
    await gesture.moveTo(tester.getTopRight(text) + const Offset(-1, 4));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_picked(tester), isNull);
    await sendPlatformShortcut(tester, LogicalKeyboardKey.keyC);
    expect(copied, ['note 1']);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('dragging from a picked row deselects the range', (tester) async {
    await pumpConversation(tester, _dm, messages: _notes(4));
    await _mouseDrag(tester, ['note 0', 'note 3']);
    expect(_picked(tester), 4);
    await _mouseDrag(tester, ['note 1', 'note 2']);
    expect(_picked(tester), 2);
  });

  testWidgets('a long press drag picks rows on touch', (tester) async {
    await pumpConversation(tester, _dm, messages: _notes(4));
    await _startSelecting(tester, 'note 3');
    final gesture = await tester.startGesture(_at(tester, 'note 0'));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(_at(tester, 'note 1'));
    await tester.pump();
    await gesture.moveTo(_at(tester, 'note 2'));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_picked(tester), 4);
  });

  testWidgets('a plain swipe scrolls instead of picking', (tester) async {
    await pumpConversation(tester, _dm, messages: _notes(60));
    await _startSelecting(tester, 'note 59');
    await tester.drag(find.text('note 58'), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(_picked(tester), 1);
    expect(_scrolled(tester), greaterThan(80));
  });

  testWidgets('holding a touch drag at the edge scrolls and keeps picking',
      (tester) async {
    await pumpConversation(tester, _dm, messages: _notes(60));
    await _startSelecting(tester, 'note 59');
    final list = tester.getRect(find.byType(ListView));
    final shown = _shown(tester, list);
    final gesture = await tester.startGesture(_at(tester, 'note 58'));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(Offset(list.center.dx, list.top + 4));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_scrolled(tester), greaterThan(list.height / 2));
    expect(_picked(tester), greaterThan(shown + 1));
    final stopped = _scrolled(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(_scrolled(tester), stopped);
  });

  testWidgets('a mouse drag past the list edge scrolls and keeps picking',
      (tester) async {
    await pumpConversation(tester, _dm, messages: _notes(60));
    final list = tester.getRect(find.byType(ListView));
    final gesture = await tester.startGesture(_at(tester, 'note 59'),
        kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
    await gesture.moveTo(_at(tester, 'note 57'));
    await tester.pump();
    await gesture.moveTo(Offset(list.center.dx, list.top - 10));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_scrolled(tester), greaterThan(100));
    expect(_picked(tester), greaterThan(_shown(tester, list)));
  });
}
