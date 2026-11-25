// The chat row under the conditions users bring: large text, keyboard
// navigation, both palettes and a row menu.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/sessions/rail_buttons.dart';
import 'package:mosh/src/features/sessions/rail_item.dart';
import 'package:mosh/src/gateway/conversation_target.dart';

import '../../support/contrast.dart';

/// Mounts [child] in the rail's width on the theme of [colors].
Future<void> _pumpRail(
  WidgetTester tester,
  Widget child, {
  MoshColors colors = MoshColors.dark,
  TextScaler textScaler = TextScaler.noScaling,
}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: buildMoshTheme(colors),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: Scaffold(
            backgroundColor: colors.surfaceContainerLowest,
            body: SizedBox(
              width: kRailWidth - 2 * kRailPadding,
              child: SingleChildScrollView(child: Column(children: [child])),
            ),
          ),
        ),
      ),
    );

RailItem _row({bool active = false, bool menuOpen = false}) => RailItem(
      kind: ConversationKind.dm,
      leading: const Icon(Icons.person),
      title: 'Alice',
      subtitle: 'Connected',
      timestamp: '8:34 AM',
      active: active,
      menuOpen: menuOpen,
      onTap: () {},
    );

/// The fill of the row's own surface.
Color _fill(WidgetTester tester) => tester
    .widget<Material>(find
        .descendant(of: find.byType(RailItem), matching: find.byType(Material))
        .first)
    .color!;

Color _ink(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!.color!;

void main() {
  testWidgets('every rail row grows with 200% text instead of overflowing',
      (tester) async {
    await _pumpRail(
      tester,
      Column(
        children: [
          RailNewButton(label: 'New chat', onTap: () {}),
          _row(),
          _row(active: true),
          RailSettingsButton(label: 'Settings', onTap: () {}),
        ],
      ),
      textScaler: const TextScaler.linear(2),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('Tab onto Settings draws the keyboard focus ring',
      (tester) async {
    await _pumpRail(
      tester,
      Column(
        children: [
          RailNewButton(label: 'New chat', onTap: () {}),
          _row(),
          RailSettingsButton(label: 'Settings', onTap: () {}),
        ],
      ),
    );

    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    }
    await tester.pump();

    final rings = find.descendant(
      of: find.byType(RailSettingsButton),
      matching: find.byWidgetPredicate(
        (w) => switch (w) {
          DecoratedBox(decoration: BoxDecoration(:final border)) =>
            border == Border.all(color: MoshColors.dark.focusRing, width: 2),
          _ => false,
        },
      ),
    );
    expect(rings, findsOneWidget);
  });

  for (final (palette, colors) in [
    ('dark', MoshColors.dark),
    ('light', MoshColors.light),
  ]) {
    for (final active in [false, true]) {
      testWidgets(
          'a ${active ? 'selected' : 'resting'} row reads at 4.5:1 under the '
          'pointer on the $palette palette', (tester) async {
        await _pumpRail(tester, _row(active: active), colors: colors);
        await tester.pump();

        // The hover layer is the darkest the row's surface gets.
        final surface = Color.alphaBlend(
            MoshState.tint(colors.onSurface, MoshState.hover),
            Color.alphaBlend(_fill(tester), colors.surfaceContainerLowest));
        for (final text in ['Alice', 'Connected', '8:34 AM']) {
          expect(contrastRatio(_ink(tester, text), surface),
              greaterThanOrEqualTo(4.5),
              reason: text);
        }
      });
    }
  }

  testWidgets('a row stays pressed while its menu is open', (tester) async {
    Finder pressed() => find.descendant(
        of: find.byType(RailItem),
        matching: find.byWidgetPredicate((w) =>
            w is ColoredBox &&
            w.color ==
                MoshState.tint(MoshColors.dark.onSurface, MoshState.pressed)));

    await _pumpRail(tester, _row());
    expect(pressed(), findsNothing);
    await _pumpRail(tester, _row(menuOpen: true));
    expect(pressed(), findsOneWidget);
  });

  testWidgets('an unread row without a last message still shows its count',
      (tester) async {
    await _pumpRail(
        tester,
        const RailItem(
            kind: ConversationKind.channel,
            leading: Icon(Icons.tag),
            title: '#general',
            subtitle: '',
            unreadCount: 4));
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('hovering a truncated row shows its full title and subtitle',
      (tester) async {
    const title = 'Alice from the design review with a very long name';
    await _pumpRail(
      tester,
      RailItem(
        kind: ConversationKind.dm,
        leading: const Icon(Icons.person),
        title: title,
        subtitle: 'Connected',
        onTap: () {},
      ),
    );
    // The rail width really truncates the title.
    expect(
        tester
            .renderObject<RenderParagraph>(find.text(title))
            .didExceedMaxLines,
        isTrue);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.text(title)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('$title\nConnected', findRichText: true), findsOneWidget);
  });
}
