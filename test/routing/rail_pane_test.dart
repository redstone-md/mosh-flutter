// IVO-16: the desktop chat list resizes from the divider, collapses to an
// avatar strip and expands back to the width chosen before, across
// restarts too.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/sessions/rail_compact.dart';
import 'package:mosh/src/features/sessions/rail_item.dart';
import 'package:mosh/src/routing/rail_pane.dart';
import 'package:mosh/src/state/rail_layout_provider.dart';

import '../support/rail.dart';

final _handle = find.byWidgetPredicate((widget) =>
    widget is MouseRegion && widget.cursor == SystemMouseCursors.resizeColumn);

double _railWidth(WidgetTester tester) => tester
    .getTopLeft(find
        .descendant(
            of: find.byType(RailPane), matching: find.byType(VerticalDivider))
        .first)
    .dx;

Future<void> _drag(WidgetTester tester, double dx) async {
  final gesture = await tester.startGesture(tester.getCenter(_handle),
      kind: PointerDeviceKind.mouse);
  for (var i = 1; i <= 4; i++) {
    await gesture.moveBy(Offset(dx / 4, 0));
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _toggle(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
}

void main() {
  test('the list keeps the conversation readable', () {
    expect(railWidthFor(null, 1200), 336);
    expect(railWidthFor(null, 2000), kRailWidth);
    expect(railWidthFor(900, 1200), kRailMaxWidth);
    expect(railWidthFor(450, 700), 700 - kChatMinWidth);
    expect(railWidthFor(100, 1200), kRailMinWidth);
    expect(railWidthFor(400, 581), kRailMinWidth);
  });

  testWidgets('dragging the divider resizes the list and saves on release',
      (tester) async {
    final store = MemoryRailLayoutStore();
    await pumpRail(tester, store: store);
    expect(_railWidth(tester), 336);
    await _drag(tester, 80);
    expect(_railWidth(tester), 416);
    expect(store.writes, 1);
    expect(store.saved, const RailLayout(width: 416));
  });

  testWidgets('dragging past the narrowest width snaps to the strip and back',
      (tester) async {
    final store = MemoryRailLayoutStore(const RailLayout(width: 300));
    await pumpRail(tester, store: store);
    await _drag(tester, -200);
    expect(_railWidth(tester), kRailCompactWidth);
    expect(find.byType(CompactRailItem), findsOneWidget);
    expect(store.saved?.collapsed, isTrue);
    await _drag(tester, 120);
    expect(_railWidth(tester), greaterThanOrEqualTo(kRailMinWidth));
    expect(find.byType(CompactRailItem), findsNothing);
  });

  testWidgets('the titlebar button collapses and restores the chosen width',
      (tester) async {
    final store = MemoryRailLayoutStore(const RailLayout(width: 400));
    await pumpRail(tester, store: store);
    await tester.tap(find.byTooltip('Collapse chat list'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Mid-animation the list is between its widths.
    expect(_railWidth(tester), inExclusiveRange(kRailCompactWidth, 400));
    await tester.pumpAndSettle();
    expect(_railWidth(tester), kRailCompactWidth);
    expect(find.byTooltip('#general'), findsOneWidget);
    await _toggle(tester, 'Expand chat list');
    expect(_railWidth(tester), 400);
    expect(store.saved, const RailLayout(width: 400));
  });

  testWidgets('reduced motion collapses at once', (tester) async {
    await pumpRail(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.tap(find.byTooltip('Collapse chat list'));
    await tester.pump();
    await tester.pump();
    expect(_railWidth(tester), kRailCompactWidth);
  });

  testWidgets('the handle resizes and collapses from the keyboard',
      (tester) async {
    await pumpRail(tester,
        store: MemoryRailLayoutStore(const RailLayout(width: 300)));
    Focus.of(tester.element(find.descendant(
            of: _handle, matching: find.byType(GestureDetector))))
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_railWidth(tester), 316);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_railWidth(tester), kRailCompactWidth);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_railWidth(tester), 316);
  });

  testWidgets('a collapsed list comes back collapsed after a restart',
      (tester) async {
    await pumpRail(tester,
        store: MemoryRailLayoutStore(
            const RailLayout(width: 400, collapsed: true)));
    expect(_railWidth(tester), kRailCompactWidth);
    expect(find.byType(RailNewButton), findsNothing);
    expect(find.byTooltip('Start a conversation'), findsOneWidget);
  });

  testWidgets('phones ignore the collapsed desktop list', (tester) async {
    await pumpRail(tester,
        size: const Size(390, 844),
        store: MemoryRailLayoutStore(const RailLayout(collapsed: true)));
    expect(find.byType(RailNewButton), findsOneWidget);
    expect(find.byType(CompactRailItem), findsNothing);
  });

  testWidgets('Ctrl+K expands the strip into a focused search', (tester) async {
    await pumpRail(tester,
        store: MemoryRailLayoutStore(const RailLayout(collapsed: true)));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('chat-list-search'));
    expect(search, findsOneWidget);
    expect(tester.widget<TextField>(search).focusNode!.hasPrimaryFocus, isTrue);
  });

  testWidgets('collapsing keeps the search, its filter and the open chat',
      (tester) async {
    await pumpRail(tester, channels: ['general', 'random']);
    await tester.enterText(
        find.byKey(const ValueKey('chat-list-search')), 'rand');
    await tester.pump();
    await tester.tap(find.text('#random'));
    await tester.pumpAndSettle();
    await _toggle(tester, 'Collapse chat list');
    expect(find.byType(CompactRailItem), findsOneWidget);
    expect(
        tester
            .widget<CompactRailItem>(find.byType(CompactRailItem))
            .item
            .active,
        isTrue);
    await _toggle(tester, 'Expand chat list');
    expect(find.text('rand'), findsOneWidget);
    expect(find.text('#general'), findsNothing);
  });

  testWidgets('a double click on the handle toggles the list', (tester) async {
    await pumpRail(tester);
    await tester.tap(_handle, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(_handle, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(_railWidth(tester), kRailCompactWidth);
  });

  testWidgets('screen readers get the handle as a slider', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpRail(tester,
          store: MemoryRailLayoutStore(const RailLayout(width: 300)));
      final handle = find.bySemanticsLabel('Chat list width');
      expect(
          tester.getSemantics(handle),
          isSemantics(
            isSlider: true,
            value: '300',
            increasedValue: '316',
            decreasedValue: '284',
            hasIncreaseAction: true,
            hasDecreaseAction: true,
            customActions: [
              const CustomSemanticsAction(label: 'Collapse chat list')
            ],
          ));
      tester.semantics.performAction(
          find.semantics.byLabel('Chat list width'), SemanticsAction.decrease);
      await tester.pumpAndSettle();
      expect(_railWidth(tester), 284);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('a drag caught mid-animation starts from the visible edge',
      (tester) async {
    await pumpRail(tester,
        store: MemoryRailLayoutStore(const RailLayout(width: 400)));
    await tester.tap(find.byTooltip('Collapse chat list'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    final grabbed = _railWidth(tester);
    expect(grabbed, greaterThan(250));
    await _drag(tester, 40);
    expect(_railWidth(tester), moreOrLessEquals(grabbed + 40, epsilon: 1));
  });
}
