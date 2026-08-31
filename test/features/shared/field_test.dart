// Widget test for `Field` (1-в-1 with React `Field` in
// src/features/private-dm/NewSessionPanel.parts.tsx, CSS `.field*`). Asserts
// the layout contract: label + child render, hint renders only when non-null.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/shared/field.dart';

void main() {
  testWidgets('label and hint render when both provided', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Field(
            label: 'Static peer',
            hint: 'Empty = Moss',
            child: const TextField(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Static peer'), findsOneWidget);
    expect(find.text('Empty = Moss'), findsOneWidget);
  });

  testWidgets('hint is absent when null', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Field(
            label: 'L',
            child: const TextField(),
          ),
        ),
      ),
    );
    await tester.pump();

    // The hint string from the previous test must NOT render for this Field.
    expect(find.text('Empty = Moss'), findsNothing);
    expect(find.text('L'), findsOneWidget);
  });

  testWidgets('child widget mounts in the field body', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Field(
            label: 'Static peer',
            hint: 'Empty = Moss',
            child: const TextField(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('field contains a single Column with stacked children',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Field(
            label: 'Static peer',
            hint: 'Empty = Moss',
            child: const TextField(),
          ),
        ),
      ),
    );
    await tester.pump();

    // Label + hint Texts + the child TextField = 3 children of the Column.
    // Now Label + gap(4) + child + gap(4) + hint = 5 (React `.field { gap: 4px }`
    // materialized as SizedBox spacers so the gap survives without a gap prop).
    final column = tester.widget<Column>(find.byType(Column));
    expect(column.children.length, 5);
    expect(column.crossAxisAlignment, CrossAxisAlignment.stretch);
  });
}
