// A custom InkWell control shows a 2px focusRing border while it holds
// keyboard focus, and nothing otherwise.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/shared/focus_ring.dart';

void main() {
  BoxDecoration ringOf(WidgetTester tester) => tester
      .widget<DecoratedBox>(find.descendant(
        of: find.byType(FocusRing),
        matching: find.byType(DecoratedBox),
      ))
      .decoration as BoxDecoration;

  testWidgets('Tab onto the control draws the ring; leaving clears it',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: moshThemeData,
      home: Scaffold(
        body: Column(children: <Widget>[
          InkWell(
            onTap: () {},
            child: const FocusRing(
              radius: BorderRadius.all(Radius.circular(12)),
              child: SizedBox(width: 100, height: 40),
            ),
          ),
          TextButton(onPressed: () {}, child: const Text('next')),
        ]),
      ),
    ));
    expect(ringOf(tester).border, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final border = ringOf(tester).border! as Border;
    expect(border.top.color, MoshColors.focusRing);
    expect(border.top.width, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(ringOf(tester).border, isNull);
  });
}
