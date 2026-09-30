// The onboarding menu on a narrow pane: tile descriptions wrap in full
// (Russian needs three lines), and a keyboard user sees which tile holds
// focus.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/onboarding/onboard_menu.dart';
import 'package:mosh/src/features/shared/focus_ring.dart';
import '../../support/pump.dart';

void _noop() {}

void main() {
  Future<AppLocalizations> pumpMenu(WidgetTester tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await pumpScreen(
      tester,
      const Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: SingleChildScrollView(
              child: OnboardMenu(
                onPickChat: _noop,
                onPickGroup: _noop,
                onPickChannel: _noop,
                onPickJoin: _noop,
              ),
            ),
          ),
        ),
      ),
    );
    return AppLocalizations.of(tester.element(find.byType(OnboardMenu)))!;
  }

  testWidgets('tile descriptions wrap in full at 300px in Russian',
      (tester) async {
    final l = await pumpMenu(tester);
    for (final desc in [
      l.onboardTileChatDesc,
      l.onboardTileGroupDesc,
      l.onboardTileJoinDesc,
      l.onboardTileChannelDesc,
    ]) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(desc));
      expect(paragraph.didExceedMaxLines, isFalse, reason: desc);
    }
  });

  testWidgets('Tab onto a tile draws the focus ring', (tester) async {
    final l = await pumpMenu(tester);
    Border? ringOf(String title) {
      final ring =
          find.ancestor(of: find.text(title), matching: find.byType(FocusRing));
      final box = tester.widget<DecoratedBox>(
          find.descendant(of: ring, matching: find.byType(DecoratedBox)).first);
      return (box.decoration as BoxDecoration).border as Border?;
    }

    expect(ringOf(l.onboardTileChatTitle), isNull);
    // Tab 1 lands on the display-name field, Tab 2 on the first tile.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(ringOf(l.onboardTileChatTitle)?.top.color, MoshColors.focusRing);
  });
}
