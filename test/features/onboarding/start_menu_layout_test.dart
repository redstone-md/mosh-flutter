// IVO-50: the start menu fits its pane. Cards sit four, two or one to a
// row, the hero drops its illustration on narrow panes, descriptions wrap
// in full in Russian, a keyboard user sees which card holds focus, and
// reduced motion shows everything at rest.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/onboarding/start/start_card.dart';
import 'package:mosh/src/features/onboarding/start/start_menu.dart';
import 'package:mosh/src/features/onboarding/start/start_reveal.dart';
import 'package:mosh/src/features/shared/focus_ring.dart';
import '../../support/pump.dart';

void _noop() {}

Future<AppLocalizations> _pumpMenu(WidgetTester tester, double width,
    {Locale locale = const Locale('en')}) async {
  tester.view
    ..physicalSize = Size(width, 1400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  await pumpScreen(
    tester,
    const Scaffold(
      body: SingleChildScrollView(
        child: StartMenu(
          onPickChat: _noop,
          onPickGroup: _noop,
          onPickJoin: _noop,
          onPickChannel: _noop,
        ),
      ),
    ),
  );
  return AppLocalizations.of(tester.element(find.byType(StartMenu)))!;
}

/// How many cards share the first card's row.
int _cardsInFirstRow(WidgetTester tester) {
  final top = tester.getTopLeft(find.byType(StartCard).first).dy;
  return find
      .byType(StartCard)
      .evaluate()
      .where((e) => tester.getTopLeft(find.byWidget(e.widget)).dy == top)
      .length;
}

void main() {
  for (final (width, columns, illustrated) in [
    (1200.0, 4, true),
    (800.0, 2, true),
    (600.0, 2, false),
    (390.0, 1, false),
  ]) {
    testWidgets('at ${width.toInt()}px: $columns per row', (tester) async {
      await _pumpMenu(tester, width);
      expect(_cardsInFirstRow(tester), columns);
      expect(find.byType(Image), illustrated ? findsOneWidget : findsNothing);
    });
  }

  testWidgets('cards in a row share a height', (tester) async {
    await _pumpMenu(tester, 1200, locale: const Locale('ru'));
    final heights = {
      for (final e in find.byType(StartCard).evaluate())
        tester.getSize(find.byWidget(e.widget)).height
    };
    expect(heights, hasLength(1));
  });

  testWidgets('card descriptions wrap in full on a phone in Russian',
      (tester) async {
    final l = await _pumpMenu(tester, 320, locale: const Locale('ru'));
    for (final desc in [
      l.onboardTileChatDesc,
      l.onboardTileGroupDesc,
      l.onboardTileJoinDesc,
      l.onboardTileChannelDesc,
    ]) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(desc));
      expect(paragraph.didExceedMaxLines, isFalse, reason: desc);
      final needed = paragraph.getMaxIntrinsicHeight(paragraph.size.width);
      expect(paragraph.size.height, greaterThanOrEqualTo(needed), reason: desc);
    }
  });

  testWidgets('Tab onto a card draws the focus ring', (tester) async {
    final l = await _pumpMenu(tester, 1200);
    Border? ringOf(String title) {
      final ring =
          find.ancestor(of: find.text(title), matching: find.byType(FocusRing));
      final box = tester.widget<DecoratedBox>(
          find.descendant(of: ring, matching: find.byType(DecoratedBox)).first);
      return (box.decoration as BoxDecoration).border as Border?;
    }

    expect(ringOf(l.onboardTileChatTitle), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(ringOf(l.onboardTileChatTitle)?.top.color, MoshColors.focusRing);
  });

  testWidgets('a reveal plays in, and reduced motion shows it at rest',
      (tester) async {
    Iterable<double> opacities() => tester
        .widgetList<Opacity>(find.descendant(
            of: find.byType(StartReveal), matching: find.byType(Opacity)))
        .map((o) => o.opacity);

    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: StartReveal(
        delay: Duration(milliseconds: 40),
        child: SizedBox(),
      ),
    ));
    expect(opacities(), everyElement(0.0));
    await tester.pumpAndSettle();
    expect(opacities(), everyElement(1.0));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: StartReveal(child: SizedBox()),
      ),
    ));
    expect(opacities(), everyElement(1.0));
  });
}
