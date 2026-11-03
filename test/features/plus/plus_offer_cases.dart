import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/plus/plus_provider.dart';
import 'package:mosh/src/features/sessions/rail_entry.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/conversation/dm_offers.dart';
import 'package:mosh/src/rust/plus/types.dart';
import 'package:mosh/src/state/dm_offer_providers.dart';
import '../../support/plus/fakes.dart';
import '../../support/pump.dart';

void main() {
  for (final authenticated in [false, true]) {
    testWidgets('offer badge requires native provenance: $authenticated',
        (tester) async {
      final native = MemoryPlusCommands()
        ..current = PlusSnapshot(active: false, visible: false, peerBadges: [
          PlusPeerBadge(
              identity: 'paid-peer',
              expiresAtMs: BigInt.from(DateTime.now()
                  .add(const Duration(days: 1))
                  .millisecondsSinceEpoch))
        ]);
      final entry = OfferRailEntry(
          pending: PendingDmOffer(
              kind: ConversationKind.channel,
              host: 'public',
              offer: DmOffer(
                  authenticated: authenticated ? true : null,
                  offerId: 'forged',
                  fromDevice: 'Forged name',
                  fromFingerprint: 'paid-peer',
                  targetFingerprint: 'me',
                  inviteUri: 'untrusted-invite')),
          onAccept: () {},
          onDismiss: () {});
      await pumpScreen(
          tester,
          Scaffold(
              body: Builder(
                  builder: (context) => entry.buildRow(context,
                      (unreadCount: 0, active: false, onSelect: null)))),
          overrides: [
            plusConfigProvider
                .overrideWithValue(const PlusConfig(issuerKey: 'pin')),
            plusCommandsProvider.overrideWithValue(native),
            plusPollIntervalProvider.overrideWithValue(null),
          ]);
      expect(find.text('Forged name'), findsOneWidget);
      expect(find.byIcon(Icons.workspace_premium),
          authenticated ? findsOneWidget : findsNothing);
    });
  }
}
