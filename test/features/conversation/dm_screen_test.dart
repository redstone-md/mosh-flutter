// S4.7: widget test for the DM screen. Pumps it in a ProviderScope +
// localized MaterialApp with a test gateway (pre-seeded via createInvite so
// the session has a known id + 0 messages), types a message, taps send, and
// asserts the seeded + sent messages render.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/dm_screen.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import '../../support/pump.dart';

void main() {
  testWidgets('renders seeded messages and appends on send', (tester) async {
    final gateway = ScriptableGateway();
    final invite = await gateway.createInvite(
      request:
          const StartSessionRequest(displayName: 'alice', listenPort: 8765),
    );
    // Seed two messages on the fake session so the list is non-empty.
    await gateway.send(DmTarget(invite.sessionId), body: 'hello');
    await gateway.send(DmTarget(invite.sessionId), body: 'world');

    await pumpScreen(tester, DmScreen(sessionId: invite.sessionId),
        overrides: [gatewayProvider.overrideWithValue(gateway as Gateway)]);

    expect(find.text('hello'), findsOneWidget);
    expect(find.text('world'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'fresh');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('fresh'), findsOneWidget);
  });
}
