// The unread badge's typographic contract.
//
// Audit (2026-09-21) HIGH: the badge painted its numeral with `Colors.white`
// on the moss primary (#B7D84A) -- ~1.6:1 contrast. The theme already carries
// the correct on-accent token (`onPrimary` = mossInk), so the badge must read
// it instead of hardcoding white. The count is also a live number, so it
// renders with tabular figures like the other live timers.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show moshThemeData;
import 'package:mosh/src/features/conversation/conversation_helpers.dart'
    show UnreadBadge;

Widget _host(Widget child) => MaterialApp(
      theme: moshThemeData,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('the count paints with the theme on-accent ink, not white',
      (tester) async {
    await tester.pumpWidget(_host(const UnreadBadge(count: 3)));

    final text = tester.widget<Text>(find.text('3'));
    expect(text.style!.color, moshThemeData.colorScheme.onPrimary);
  });

  testWidgets('the count renders with tabular figures', (tester) async {
    await tester.pumpWidget(_host(const UnreadBadge(count: 3)));

    final text = tester.widget<Text>(find.text('3'));
    expect(text.style!.fontFeatures, contains(FontFeature.tabularFigures()));
  });

  testWidgets('counts over 99 collapse to 99+', (tester) async {
    await tester.pumpWidget(_host(const UnreadBadge(count: 100)));

    expect(find.text('99+'), findsOneWidget);
  });
}
