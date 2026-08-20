// S4.7: widget test for the DM screen. Pumps it in a ProviderScope +
// localized MaterialApp with a test gateway (pre-seeded via createInvite so
// the session has a known id + 0 messages), types a message, taps send, and
// asserts the seeded + sent messages render.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/dm_screen.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';

void main() {
  testWidgets('renders seeded messages and appends on send', (tester) async {
    final gateway = ScriptableGateway();
    final invite = await gateway.createInvite(
      request: const StartSessionRequest(displayName: 'alice', listenPort: 8765),
    );
    // Seed two messages on the fake session so the list is non-empty.
    await gateway.sendMessage(sessionId: invite.sessionId, body: 'hello');
    await gateway.sendMessage(sessionId: invite.sessionId, body: 'world');

    await tester.pumpWidget(ProviderScope(
      overrides: [gatewayProvider.overrideWithValue(gateway as Gateway)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DmScreen(sessionId: invite.sessionId),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
    expect(find.text('world'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'fresh');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('fresh'), findsOneWidget);
  });
}