// The rail row chrome under the conditions users bring: large text,
// keyboard navigation and the themed row surfaces.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/sessions/rail_item.dart';

/// Mounts [child] in the rail's width on the app theme.
Future<void> _pumpRail(
  WidgetTester tester,
  Widget child, {
  TextScaler textScaler = TextScaler.noScaling,
}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: moshThemeData,
        home: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: Scaffold(
            backgroundColor: MoshColors.bg0,
            body: SizedBox(
              width: kRailWidth - 2 * kRailPadding,
              child: SingleChildScrollView(child: Column(children: [child])),
            ),
          ),
        ),
      ),
    );

/// WCAG contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

RailItem _row({RailItemKind kind = RailItemKind.dm, bool active = false}) =>
    RailItem(
      kind: kind,
      leading: const Icon(Icons.person),
      title: 'Alice',
      subtitle: 'Connected',
      active: active,
      onTap: () {},
    );

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
            border == Border.all(color: MoshColors.focusRing, width: 2),
          _ => false,
        },
      ),
    );
    expect(rings, findsOneWidget);
  });

  for (final kind in RailItemKind.values) {
    testWidgets('the ${kind.name} row subtitle reads at 4.5:1 on its surface',
        (tester) async {
      await _pumpRail(tester, _row(kind: kind));

      final fill = tester
          .widget<Material>(find
              .descendant(
                  of: find.byType(RailItem), matching: find.byType(Material))
              .first)
          .color!;
      final surface = Color.alphaBlend(fill, MoshColors.bg0);
      final ink = tester
          .renderObject<RenderParagraph>(find.text('Connected'))
          .text
          .style!
          .color!;
      expect(_contrast(ink, surface), greaterThanOrEqualTo(4.5));
    });
  }

  testWidgets('hovering a truncated row shows its full title and subtitle',
      (tester) async {
    const title = 'Alice from the design review with a very long name';
    await _pumpRail(
      tester,
      RailItem(
        kind: RailItemKind.dm,
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

  testWidgets('a row with its own screen-reader label still activates',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var accepted = 0;
    await _pumpRail(
      tester,
      RailItem(
        kind: RailItemKind.dm,
        leading: const Icon(Icons.person),
        title: 'Dora',
        subtitle: '#general',
        semanticLabel: 'Accept chat invite from Dora',
        onTap: () => accepted++,
      ),
    );

    tester.semantics
        .tap(find.semantics.byLabel('Accept chat invite from Dora'));
    expect(accepted, 1);
    semantics.dispose();
  });
}
