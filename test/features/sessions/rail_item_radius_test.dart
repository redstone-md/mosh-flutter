// The rail row keeps one corner radius across states.
//
// Audit (2026-09-21) LOW: the active row inflated its radius 12 -> 14, so
// selecting a row made its corners jump. The active ring is an inset border
// that must not move the outer geometry, so selecting a row keeps the radius
// of the plain row.
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/sessions/rail_item.dart';

Future<BorderRadiusGeometry?> _rowRadius(
    WidgetTester tester, bool active) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: moshThemeData,
      home: Scaffold(
        body: RailItem(
          kind: RailItemKind.dm,
          leading: const Icon(Icons.person),
          title: 'Peer',
          subtitle: 'last message',
          active: active,
          onTap: null,
        ),
      ),
    ),
  );
  return tester
      .widget<Material>(find
          .descendant(
              of: find.byType(RailItem), matching: find.byType(Material))
          .first)
      .borderRadius;
}

void main() {
  testWidgets('selecting a row keeps its corner radius', (tester) async {
    final plain = await _rowRadius(tester, false);
    final active = await _rowRadius(tester, true);

    expect(plain, isNotNull);
    expect(active, plain);
  });
}
