import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/sessions/sessions_screen.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/message_builders.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

void main() {
  for (final loading in [true, false]) {
    testWidgets('DM ${loading ? 'loading' : 'error'} keeps other chats usable',
        (tester) async {
      final gateway = ScriptableGateway()
        ..seedSessions([
          TestSnapshots.dm(sessionId: 'alice', peerDisplayName: 'Alice'),
        ])
        ..seedGroups([
          TestSnapshots.group(
              groupId: 'crew',
              label: 'Crew',
              deviceFingerprint: 'self',
              messages: const []),
        ])
        ..seedChannels([
          TestSnapshots.channel(
              name: 'general', deviceFingerprint: 'self', messages: const []),
        ]);
      final bridge = ScriptableBridge(conversations: gateway.conversations);
      if (loading) {
        bridge.hold(BridgeMethod.listSessions);
      } else {
        bridge.failAlways(BridgeMethod.listSessions);
      }
      await pumpScreen(tester, const SessionsScreen(),
          settle: !loading,
          overrides: [
            gatewayProvider.overrideWithValue(gateway),
            bridgeFacadeProvider.overrideWithValue(bridge),
          ]);
      await tester.pump();

      expect(find.text('Crew'), findsOneWidget);
      expect(find.text('#general'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      expect(find.text('Welcome to Mosh.'), findsNothing);
      if (loading) {
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      } else {
        expect(find.text('Unable to load conversations'), findsOneWidget);
      }
      await tester.tap(find.widgetWithText(ChoiceChip, 'Groups'));
      await tester.pump();
      expect(find.text('Crew'), findsOneWidget);
      expect(find.text('#general'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pump();

      if (loading) {
        bridge.release(BridgeMethod.listSessions);
      } else {
        bridge.failNext(BridgeMethod.listSessions, times: 0);
        await tester.tap(find.text('Try again'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Crew'), findsOneWidget);
      expect(find.text('#general'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Try again'), findsNothing);
    });
  }
}
