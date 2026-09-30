// The rail row chrome under the conditions users bring: large text,
// keyboard navigation and the themed row surfaces.
import 'package:flutter/material.dart';
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

RailItem _row({bool active = false}) => RailItem(
      kind: RailItemKind.dm,
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
}
