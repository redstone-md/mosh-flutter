// S4.7: widget test for the DM screen. Pumps it in a ProviderScope +
// localized MaterialApp with the scripted doubles (pre-seeded via the
// bridge's createInvite so
// the session has a known id + 0 messages), types a message, taps send, and
// asserts the seeded + sent messages render.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/conversation_text_sends.dart'
    show maxTextCharsProvider;
import 'package:mosh/src/features/conversation/dm_screen.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import '../../support/pump.dart';
import '../../support/message_builders.dart';

void main() {
  for (final historySync in [
    null,
    DmHistorySyncState.waitingForSource,
    DmHistorySyncState.importing,
  ]) {
    testWidgets('renders text and sends during $historySync', (tester) async {
      final gateway = ScriptableGateway();
      final bridge = ScriptableBridge(conversations: gateway.conversations);
      final invite = await bridge.createInvite(
        request:
            const StartSessionRequest(displayName: 'alice', listenPort: 8765),
      );
      // Seed two messages on the fake session so the list is non-empty.
      await gateway.send(DmTarget(invite.sessionId), body: 'hello');
      await gateway.send(DmTarget(invite.sessionId), body: 'world');
      gateway.seedSessions([
        TestSnapshots.dm(
          sessionId: invite.sessionId,
          historySync: historySync,
          messages: gateway.conversations.sessions[invite.sessionId]!.messages,
        ),
      ]);

      await pumpScreen(tester, DmScreen(sessionId: invite.sessionId),
          overrides: [
            gatewayProvider.overrideWithValue(gateway),
            bridgeFacadeProvider.overrideWithValue(bridge),
          ]);

      expect(find.text('hello'), findsOneWidget);
      expect(find.text('world'), findsOneWidget);
      if (historySync != null) {
        expect(
            find.text(historySync == DmHistorySyncState.waitingForSource
                ? 'Waiting for message history'
                : 'Importing message history'),
            findsOneWidget);
      }

      await tester.enterText(find.byType(TextField).first, 'fresh');
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(find.text('fresh'), findsOneWidget);
    });
  }

  testWidgets('the composer counts down to the runtime limit and stops there',
      (tester) async {
    final gateway = ScriptableGateway();
    final bridge = ScriptableBridge(conversations: gateway.conversations);
    final invite = await bridge.createInvite(
      request:
          const StartSessionRequest(displayName: 'alice', listenPort: 8765),
    );
    gateway.seedSessions([TestSnapshots.dm(sessionId: invite.sessionId)]);
    Finder counter(String label) => find.byWidgetPredicate(
        (widget) => widget is Text && widget.semanticsLabel == label);
    await pumpScreen(tester, DmScreen(sessionId: invite.sessionId), overrides: [
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(bridge),
      maxTextCharsProvider.overrideWithValue(10),
    ]);

    await tester.enterText(find.byType(TextField).first, 'x' * 9);
    await tester.pump();
    expect(counter('1 character left'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'x' * 12);
    await tester.pump();
    expect(counter('2 characters over the limit'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(gateway.conversations.sessions[invite.sessionId]?.messages ?? [],
        isEmpty);
  });
}
