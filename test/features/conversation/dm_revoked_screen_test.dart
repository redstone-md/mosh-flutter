import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/dm_screen.dart';
import 'package:mosh/src/features/conversation/conversation_composer.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import '../../support/message_builders.dart';
import '../../support/pump.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

void main() {
  testWidgets(
      'revoked desktop retains text with composer disabled and fresh-link guidance',
      (tester) async {
    final gateway = ScriptableGateway();
    final bridge = ScriptableBridge(conversations: gateway.conversations);
    gateway.seedSessions([
      TestSnapshots.dm(
          sessionId: 'revoked',
          deviceRevocation: DmDeviceRevocationState.revoked,
          messages: [
            TestMessages.dm(
                fromDevice: 'peer', body: 'Already received history')
          ])
    ]);
    await pumpScreen(tester, const DmScreen(sessionId: 'revoked'), overrides: [
      gatewayProvider.overrideWithValue(gateway),
      bridgeFacadeProvider.overrideWithValue(bridge),
    ]);
    expect(find.text('Already received history'), findsOneWidget);
    final l = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l.dmDeviceRevokedTitle), findsOneWidget);
    expect(find.text(l.dmDeviceRevokedBody), findsOneWidget);
    final composer = find.byType(ConversationComposer);
    expect(
        tester
            .widget<TextField>(
                find.descendant(of: composer, matching: find.byType(TextField)))
            .enabled,
        false);
    expect(
        tester
            .widget<FilledButton>(find.descendant(
                of: composer, matching: find.byType(FilledButton)))
            .onPressed,
        isNull);
  });
}
