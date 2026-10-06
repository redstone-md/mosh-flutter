import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/conversation/message_copy.dart';

import '../../support/pump.dart';
import '../../support/message_selection.dart';

Future<void> _pump(WidgetTester tester,
        {List<Widget>? rows,
        bool reducedMotion = false,
        double textScale = 1,
        EdgeInsets viewInsets = EdgeInsets.zero}) =>
    pumpScreen(
      tester,
      Theme(
        data: buildMoshTheme(),
        child: Builder(
            builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    disableAnimations: reducedMotion,
                    textScaler: TextScaler.linear(textScale),
                    viewInsets: viewInsets,
                  ),
                  child: Scaffold(
                    body: MessageSelectionArea(
                      child: Column(
                          children: rows ??
                              [
                                CopyableMessage(
                                  body: 'first word\nsecond paragraph',
                                  onSelect: () {},
                                  onDelete: () {},
                                  child: const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text('first word\nsecond paragraph'),
                                  ),
                                ),
                                CopyableMessage(
                                  body: '',
                                  onSelect: () {},
                                  onDelete: () {},
                                  child: const SelectionContainer.disabled(
                                    child: Padding(
                                        padding: EdgeInsets.all(24),
                                        child: Text('report.pdf')),
                                  ),
                                ),
                                const CopyableMessage(
                                    body: 'other message',
                                    child: Text('other message')),
                              ]),
                    ),
                  ),
                )),
      ),
    );

Offset _firstWord(WidgetTester tester) =>
    tester.getTopLeft(find.text('first word\nsecond paragraph')) +
    const Offset(10, 8);

void main() {
  testWidgets('text and file menus share styled rows and pointer placement',
      (tester) async {
    await _pump(tester);
    for (final target in ['first word\nsecond paragraph', 'report.pdf']) {
      final point = tester.getCenter(find.text(target));
      await clickMessage(tester, point, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MenuItemButton, 'Select message'),
          findsOneWidget);
      expect(find.widgetWithText(MenuItemButton, 'Delete…'), findsOneWidget);
      final menu =
          tester.getRect(find.byKey(const ValueKey('message-context-menu')));
      expect((menu.topLeft - point).distance, lessThan(12));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('copy-selected preserves the fragment across menu focus and copy',
      (tester) async {
    final copied = captureClipboard(tester);
    await _pump(tester);
    final point = _firstWord(tester);
    await clickMessage(tester, point);
    await clickMessage(tester, point);
    await clickMessage(tester, point, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Copy selected text'), findsOneWidget);
    expect(find.text('Copy message'), findsOneWidget);
    await tester.tap(find.text('Copy selected text'));
    await tester.pumpAndSettle();
    expect(copied, ['first']);
    await sendPlatformShortcut(tester, LogicalKeyboardKey.keyC);
    expect(copied, ['first', 'first']);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('third timed click selects every paragraph of one message',
      (tester) async {
    final copied = captureClipboard(tester);
    await _pump(tester);
    final point = _firstWord(tester);
    await clickMessage(tester, point);
    await clickMessage(tester, point);
    await clickMessage(tester, point);
    await sendPlatformShortcut(tester, LogicalKeyboardKey.keyC);
    expect(copied, ['first word\nsecond paragraph']);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('Escape clears text selection while restoring message focus',
      (tester) async {
    final copied = captureClipboard(tester);
    await _pump(tester);
    final point = _firstWord(tester);
    await clickMessage(tester, point);
    await clickMessage(tester, point);
    await clickMessage(tester, point, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await sendPlatformShortcut(tester, LogicalKeyboardKey.keyC);
    expect(copied, isNot(contains('first')));
    expect(find.text('Copy selected text'), findsNothing);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets(
      'right-clicking another row clears selection and hides its actions',
      (tester) async {
    final copied = captureClipboard(tester);
    await _pump(tester);
    final point = _firstWord(tester);
    await clickMessage(tester, point);
    await clickMessage(tester, point);
    await clickMessage(tester, tester.getCenter(find.text('other message')),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Copy selected text'), findsNothing);
    expect(find.text('Delete…'), findsNothing);
    expect(find.text('Select message'), findsNothing);
    await tester.tap(find.text('Copy message'));
    await tester.pumpAndSettle();
    expect(copied, ['other message']);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('outside click dismisses the menu and clears text selection',
      (tester) async {
    await _pump(tester);
    final point = _firstWord(tester);
    await clickMessage(tester, point);
    await clickMessage(tester, point);
    await clickMessage(tester, point, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await clickMessage(tester, const Offset(700, 500));
    await tester.pumpAndSettle();
    expect(find.text('Copy message'), findsNothing);
    await clickMessage(tester, point, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Copy selected text'), findsNothing);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('menu key and Shift+F10 support arrow navigation and activation',
      (tester) async {
    var selected = 0;
    await _pump(tester, rows: [
      CopyableMessage(
        body: 'keyboard message',
        onSelect: () => selected++,
        child: const Text('keyboard message'),
      ),
    ]);
    final focus = Focus.of(tester.element(find.text('keyboard message')));
    for (final key in [
      LogicalKeyboardKey.contextMenu,
      LogicalKeyboardKey.f10
    ]) {
      focus.requestFocus();
      await tester.pump();
      if (key == LogicalKeyboardKey.f10) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      }
      await tester.sendKeyEvent(key);
      if (key == LogicalKeyboardKey.f10) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }
      await tester.pumpAndSettle();
      expect(find.text('Copy message'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Copy message'), findsNothing);
      expect(focus.hasFocus, isTrue);
    }
    expect(selected, 2);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('cross-message drag still copies only the selected range',
      (tester) async {
    final copied = captureClipboard(tester);
    await _pump(tester);
    final start = _firstWord(tester);
    final end =
        tester.getTopLeft(find.text('other message')) + const Offset(30, 8);
    final gesture =
        await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await gesture.moveTo(start + const Offset(10, 0));
    await tester.pump();
    await gesture.moveTo(end);
    await gesture.up();
    await tester.pump();
    await sendPlatformShortcut(tester, LogicalKeyboardKey.keyC);
    expect(copied.single, contains('second paragraph'));
    expect(copied.single, endsWith('ot'));
    expect(copied.single, isNot(contains('report.pdf')));
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('edge placement stays inside the viewport with enlarged text',
      (tester) async {
    await _pump(tester, textScale: 2, rows: [
      Expanded(
        child: Align(
          alignment: Alignment.bottomRight,
          child: CopyableMessage(
            body: 'edge',
            onSelect: () {},
            onDelete: () {},
            child: const SizedBox(width: 60, height: 60, child: Text('edge')),
          ),
        ),
      ),
    ]);
    final point = tester.getBottomRight(find.text('edge')) - const Offset(5, 5);
    await clickMessage(tester, point, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final menu =
        tester.getRect(find.byKey(const ValueKey('message-context-menu')));
    expect(menu.left, greaterThanOrEqualTo(8));
    expect(menu.top, greaterThanOrEqualTo(8));
    expect(menu.right, lessThanOrEqualTo(792));
    expect(menu.bottom, lessThanOrEqualTo(592));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long-press uses Mosh menus for text and files on mobile',
      (tester) async {
    await _pump(tester);
    for (final target in ['first word\nsecond paragraph', 'report.pdf']) {
      await tester.longPress(find.text(target));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MenuItemButton, 'Select message'),
          findsOneWidget);
      expect(find.widgetWithText(MenuItemButton, 'Delete…'), findsOneWidget);
      await tester.tapAt(const Offset(700, 500));
      await tester.pumpAndSettle();
    }
  }, variant: TargetPlatformVariant.mobile());

  testWidgets('reopening during closing keeps the new menu interactive',
      (tester) async {
    await _pump(tester);
    await clickMessage(tester, _firstWord(tester),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 40));
    await clickMessage(tester, tester.getCenter(find.text('other message')),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Copy message'), findsOneWidget);
    expect(find.text('Delete…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion opens and dismisses without an animation',
      (tester) async {
    await _pump(tester, reducedMotion: true);
    await clickMessage(tester, _firstWord(tester),
        buttons: kSecondaryMouseButton);
    expect(find.text('Copy message'), findsOneWidget);
    final menu = find.byKey(const ValueKey('message-context-menu'));
    final initial = tester.getRect(menu);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getRect(menu), initial);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Copy message'), findsNothing);
  });

  testWidgets('removing the menu source closes it without a stale action',
      (tester) async {
    final rows = ValueNotifier(true);
    addTearDown(rows.dispose);
    await _pump(tester, rows: [
      ValueListenableBuilder(
        valueListenable: rows,
        builder: (context, present, child) => present
            ? CopyableMessage(
                body: 'temporary message',
                onDelete: () {},
                child: const Text('temporary message'))
            : const SizedBox.shrink(),
      ),
    ]);
    await clickMessage(tester, tester.getCenter(find.text('temporary message')),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    rows.value = false;
    await tester.pumpAndSettle();
    expect(find.text('Copy message'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing during an opening animation releases the overlay',
      (tester) async {
    await _pump(tester);
    await clickMessage(tester, _firstWord(tester),
        buttons: kSecondaryMouseButton);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(find.text('Copy message'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('menus stay above the software keyboard', (tester) async {
    tester.view.viewInsets =
        FakeViewPadding(bottom: 240 * tester.view.devicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await _pump(tester, viewInsets: const EdgeInsets.only(bottom: 240), rows: [
      Expanded(
        child: Align(
          alignment: Alignment.bottomRight,
          child: CopyableMessage(
            body: 'keyboard edge',
            onSelect: () {},
            onDelete: () {},
            child: const SizedBox(
                width: 120, height: 60, child: Text('keyboard edge')),
          ),
        ),
      ),
    ]);
    await clickMessage(tester, tester.getCenter(find.text('keyboard edge')),
        buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final menu =
        tester.getRect(find.byKey(const ValueKey('message-context-menu')));
    expect(menu.bottom, lessThanOrEqualTo(352));
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard menu opening preserves the selected fragment',
      (tester) async {
    final copied = captureClipboard(tester);
    await _pump(tester);
    final point = _firstWord(tester);
    await clickMessage(tester, point);
    await clickMessage(tester, point);
    Focus.of(tester.element(find.text('first word\nsecond paragraph')))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(find.text('Copy selected text'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(copied, ['first']);
  }, variant: TargetPlatformVariant.desktop());
}
