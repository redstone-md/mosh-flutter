// S4.5: widget test for the Invite Paste screen. Pumps it in a ProviderScope
// + localized MaterialApp, drives live detection, and asserts the Connect
// button gates on detection and calls gateway.acceptInvite on tap.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/invite_paste/invite_paste_screen.dart';
import 'package:mosh/src/gateway/fake_gateway.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/state/gateway_provider.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester, Gateway gateway) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [gatewayProvider.overrideWithValue(gateway)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const InvitePasteScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('detects chat invite, rejects garbage, and connects on tap',
      (tester) async {
    final gateway = FakeGateway();
    await pumpScreen(tester, gateway);

    // Empty -> "waiting" badge; Connect disabled (onPressed null).
    expect(find.text('Waiting for a mosh:// link…'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);

    // Valid chat invite -> "Private chat invite detected"; Connect enabled.
    await tester.enterText(
        find.byType(TextField),
        'mosh://invite?mesh=7x9v&session=drift-41#fp=91A4-D2C8-77B0');
    await tester.pump();
    expect(find.text('Private chat invite detected'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);

    // Garbage -> "bad" badge; Connect disabled again.
    await tester.enterText(find.byType(TextField), 'garbage');
    await tester.pump();
    expect(find.text('That does not look like a mosh:// invite'),
        findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);

    // Re-enter a valid invite and tap Connect -> acceptInvite called.
    await tester.enterText(
        find.byType(TextField),
        'mosh://invite?mesh=7x9v&session=drift-41#fp=91A4-D2C8-77B0');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('Accepted session:'), findsOneWidget);
  });
}
