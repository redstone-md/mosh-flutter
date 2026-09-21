// The rail row keeps one corner radius across states.
//
// Audit (2026-09-21) LOW: the active row inflated its radius 12 -> 14, so
// selecting a row made its corners jump. React parity is `border-radius:
// 12px` on `.rail-item` in every state -- the active ring is an inset 2px
// border that does not move the outer geometry. These tests pin radius 12
// for both the plain row and the ringed (active) row.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/sessions/rail_item.dart';

Material _rowMaterial(WidgetTester tester) => tester.widget<Material>(
      find
          .descendant(
            of: find.byType(RailItem),
            matching: find.byType(Material),
          )
          .first,
    );

void main() {
  testWidgets('the inactive row is radius 12', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RailItem(
            kind: RailItemKind.dm,
            leading: const Icon(Icons.person),
            title: 'Peer',
            subtitle: 'last message',
            onTap: null,
          ),
        ),
      ),
    );

    expect(_rowMaterial(tester).borderRadius, BorderRadius.circular(12));
  });

  testWidgets('the active (ringed) row is radius 12 too', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RailItem(
            kind: RailItemKind.dm,
            leading: const Icon(Icons.person),
            title: 'Peer',
            subtitle: 'last message',
            active: true,
            onTap: null,
          ),
        ),
      ),
    );

    expect(_rowMaterial(tester).borderRadius, BorderRadius.circular(12));
  });
}
