import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/state/gateway_provider.dart';

import '../../support/gateway_snapshots.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

void main() {
  for (final available in [true, false]) {
    testWidgets(
        'offline DM invite actions follow durable availability $available',
        (tester) async {
      final gateway = ScriptableGateway()
        ..seedSessions([
          fakeSession(
              sessionId: 'alice',
              displayName: 'me',
              role: 'inviter',
              inviteUri: 'mosh://invite?alice',
              fingerprint: 'aabbccdd',
              inviteAvailable: available)
        ]);
      final bridge = ScriptableBridge(conversations: gateway.conversations);
      await pumpScreen(tester, const DmScreen(sessionId: 'alice'), overrides: [
        bridgeFacadeProvider.overrideWithValue(bridge),
        gatewayProvider.overrideWithValue(gateway),
      ]);
      await tester.tap(find.byTooltip('More chat actions'));
      await tester.pumpAndSettle();
      expect(find.text('Copy link'), available ? findsOneWidget : findsNothing);
      expect(
          find.text('Replace link'), available ? findsOneWidget : findsNothing);
    });
  }

  testWidgets('waiting DM copies and replaces the same conversation invitation',
      (tester) async {
    const uri = 'mosh://invite?alice';
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map?)?['text'] as String?;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final gateway = ScriptableGateway()
      ..seedSessions([
        fakeSession(
            sessionId: 'alice',
            displayName: 'me',
            role: 'inviter',
            inviteUri: uri,
            fingerprint: 'aabbccdd',
            inviteAvailable: true)
      ]);
    final bridge = ScriptableBridge(conversations: gateway.conversations);
    await pumpScreen(tester, const DmScreen(sessionId: 'alice'), overrides: [
      bridgeFacadeProvider.overrideWithValue(bridge),
      gatewayProvider.overrideWithValue(gateway),
    ]);
    await tester.tap(find.byTooltip('More chat actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(copied, uri);
    await tester.tap(find.byTooltip('More chat actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace link'));
    await tester.pumpAndSettle();
    expect(bridge.lastCall(BridgeMethod.replaceInvite)?.args['sessionId'],
        'alice');
    expect(gateway.conversations.sessions.length, 1);
    expect(gateway.conversations.sessions['alice']!.inviteUri, isNot(uri));
  });
}
