// Widget test for `Disclosure` (1-в-1 with React `Disclosure` in
// src/features/private-dm/NewSessionPanel.parts.tsx). Asserts the
// collapsible contract: body hidden when closed, shown when open, and
// toggling collapses it again.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/shared/disclosure.dart';

void main() {
  testWidgets('closed by default: head label visible, body hidden',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Disclosure(
            icon: Icons.verified_user,
            label: 'How Mosh protects you',
            child: const Text('body text'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('How Mosh protects you'), findsOneWidget);
    expect(find.text('body text'), findsNothing);
    expect(find.byType(InkWell), findsOneWidget);
  });

  testWidgets('tapping the head mounts the body', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Disclosure(
            icon: Icons.verified_user,
            label: 'How Mosh protects you',
            child: const Text('body text'),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('How Mosh protects you'));
    await tester.pump();

    expect(find.text('body text'), findsOneWidget);
  });

  testWidgets('tapping again collapses the body', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Disclosure(
            icon: Icons.verified_user,
            label: 'How Mosh protects you',
            child: const Text('body text'),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('How Mosh protects you'));
    await tester.pump();
    expect(find.text('body text'), findsOneWidget);

    await tester.tap(find.text('How Mosh protects you'));
    await tester.pump();
    expect(find.text('body text'), findsNothing);
  });

  testWidgets('head is a tappable button widget (React aria-expanded)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Disclosure(
            icon: Icons.verified_user,
            label: 'How Mosh protects you',
            child: const Text('body text'),
          ),
        ),
      ),
    );
    await tester.pump();

    // The head is an InkWell (a tap target); the caret icon mounts when
    // closed and rotates when open. Assert both visible + that the InkWell
    // carries a non-null onTap via a second tap closing the body.
    expect(find.byType(InkWell), findsOneWidget);
    expect(find.byIcon(Icons.verified_user), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);

    await tester.tap(find.byType(InkWell));
    await tester.pump();
    expect(find.text('body text'), findsOneWidget);
  });
}
