// IVO-50: the start menu fits its pane as one column under its heading;
// actions sit under encrypted and open headings, descriptions wrap in full
// in Russian, a keyboard user sees which row holds focus, and reduced
// motion shows everything at rest.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
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

void main() {
  testWidgets('the public channel sits apart, under the open heading',
      (tester) async {
    final l = await _pumpMenu(tester, 1200);
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top(l.startGroupEncrypted), lessThan(top(l.onboardTileChatTitle)));
    expect(top(l.onboardTileJoinTitle), lessThan(top(l.startGroupOpen)));
    expect(top(l.startGroupOpen), lessThan(top(l.onboardTileChannelTitle)));
  });

  testWidgets('row descriptions wrap in full on a phone in Russian',
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

  testWidgets('Tab onto a row draws the focus ring', (tester) async {
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
    expect(
        ringOf(l.onboardTileChatTitle)?.top.color, MoshColors.dark.focusRing);
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

  // Regression (CodeAnt PR #8): turning reduced motion on mid-reveal let the
  // reveal play out.
  testWidgets('reduced motion turned on mid-reveal shows it at rest',
      (tester) async {
    Widget reveal({required bool reduced}) => MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: StartReveal(child: SizedBox()),
          ),
        );
    await tester.pumpWidget(reveal(reduced: false));
    await tester.pump(const Duration(milliseconds: 16));

    await tester.pumpWidget(reveal(reduced: true));

    expect(
        tester
            .widget<Opacity>(find.descendant(
                of: find.byType(StartReveal), matching: find.byType(Opacity)))
            .opacity,
        1.0);
  });
}
