// The rail's accept-offer action toasts a failed bridge accept the way every
// other screen does: worded by the bridge error's kind, never the runtime's
// diagnostic sentence. A failed accept also dismisses nothing and opens
// nothing.
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/sessions/sessions_rail_actions.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/rust/api/conversation_bridge.dart'
    show ConversationBridgeError, ConversationBridgeErrorKind;
import 'package:mosh/src/rust/conversation/dm_offers.dart' show DmOffer;
import 'package:mosh/src/state/dm_offer_providers.dart' show PendingDmOffer;
import 'package:mosh/src/state/gateway_provider.dart' show gatewayProvider;

import '../../support/action_harness.dart';
import '../../support/scriptable_bridge.dart';
import '../../support/scriptable_gateway.dart';

const PendingDmOffer _kPending = PendingDmOffer(
  offer: DmOffer(
    offerId: 'offer-1',
    fromDevice: 'ann',
    fromFingerprint: 'ff',
    targetFingerprint: 'me',
    inviteUri: 'mosh://invite?mesh=m&session=s#fp=ff',
  ),
  kind: ConversationKind.channel,
  host: 'general',
);

void main() {
  testWidgets('a failed accept is worded by the bridge error\'s kind',
      (tester) async {
    const error = ConversationBridgeError(
      kind: ConversationBridgeErrorKind.unavailable,
      message: 'dm runtime unavailable: node down',
    );
    final gateway = ScriptableGateway();
    final bridge = ScriptableBridge(conversations: gateway.conversations)
      ..failAlways(BridgeMethod.acceptInvite, error: error);
    final harness = await mountActionHarness(
      tester,
      bridge: bridge,
      overrides: [gatewayProvider.overrideWithValue(gateway)],
    );

    await acceptOfferAction(harness.context, harness.ref, _kPending);
    await tester.pumpAndSettle();

    final l = AppLocalizations.of(harness.context)!;
    expect(find.text(l.chatActionErrorUnavailable), findsOneWidget);
    expect(find.textContaining(error.message), findsNothing);
    expect(find.text(kActionHarnessStartLabel), findsOneWidget);
    expect(gateway.countOf(GatewayMethod.dismissDmOffer), 0);
  });
}
