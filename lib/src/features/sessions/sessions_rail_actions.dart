// Rail action orchestration for the Flutter port of React's SessionRail.
// These callbacks stay outside SessionsScreen so the screen remains focused
// on composing and rendering the combined rail.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mosh/src/routing/app_router.dart' show AppRoutes;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AcceptInviteRequest;
import 'package:mosh/src/state/conversation_providers.dart'
    show conversationListProvider;
import 'package:mosh/src/state/dm_offer_providers.dart'
    show PendingDmOffer, PendingDmOfferKind;
import 'package:mosh/src/state/gateway_provider.dart' show gatewayProvider;
import 'package:mosh/src/gateway/conversation_target.dart'
    show ChannelTarget, ConversationKind, DmOfferHost, GroupTarget;
import 'package:mosh/src/gateway/gateway.dart' show Gateway;
import 'package:mosh/src/state/active_conversation_key_provider.dart'
    show activeConversationKeyProvider;
import 'package:mosh/src/state/session_providers.dart' show inviteFlowProvider;

// Mirrors React SessionRail.onNew: reset setup state, clear the active
// conversation, and show the existing NewSessionPanel in the chat branch.
void openNewSessionAction(BuildContext context, WidgetRef ref) {
  ref.read(activeConversationKeyProvider.notifier).clear();
  ref.read(inviteFlowProvider.notifier).resetInviteState();
  context.go(AppRoutes.chat);
}

// Accept a pending DM offer, 1-в-1 with React `useDmOffers.acceptDmOffer`:
// gateway.acceptInvite with the offer's inviteUri (the existing DM accept
// path -- top-level offers reuse acceptInvite, NOT org's acceptDmOffer),
// then auto-dismiss the offer (React dismisses after accept so it leaves
// the channel/group's offer list), then navigate to the new DM session.
// The displayName/listenPort/staticPeer come from inviteFlowProvider (the
// same settings source onboarding uses, ADR 0010 DRY).
Future<void> acceptOfferAction(
  BuildContext context,
  WidgetRef ref,
  PendingDmOffer pending,
) async {
  final scaffold = ScaffoldMessenger.of(context);
  final flow = ref.read(inviteFlowProvider);
  final gateway = ref.read(gatewayProvider);
  try {
    final session = await gateway.acceptInvite(
      request: AcceptInviteRequest(
        inviteUri: pending.offer.inviteUri,
        displayName: flow.displayName.isEmpty ? 'anonymous' : flow.displayName,
        listenPort: flow.listenPort,
        staticPeer: flow.staticPeer,
      ),
    );
    // Auto-dismiss the offer after accept (React's acceptDmOffer calls
    // dismissChannelDmOffer/dismissGroupDmOffer after acceptPrivateInvite).
    await dismissOfferAction(ref, pending, gateway: gateway);
    // The accepted invite creates a new DM session. Refresh the rail's session
    // list after the offer and its source list have been refreshed, matching
    // React use-dm-offers.ts acceptDmOffer -> refresh(true).
    await ref
        .read(conversationListProvider(ConversationKind.dm).notifier)
        .refresh();
    if (!context.mounted) return;
    context.go(AppRoutes.dmFor(session.sessionId));
  } catch (e) {
    scaffold.showSnackBar(SnackBar(content: Text(e.toString())));
  }
}

// Dismiss a pending DM offer, 1-в-1 with React `useDmOffers.dismissDmOffer`:
// dismiss it on the channel or the group that carries it, then refresh the
// channel/group list so the offer row disappears. The accept path passes
// its already-acquired gateway to avoid a second read.
Future<void> dismissOfferAction(
  WidgetRef ref,
  PendingDmOffer pending, {
  Gateway? gateway,
}) async {
  final Gateway gw = gateway ?? ref.read(gatewayProvider);
  final DmOfferHost<Object?> host = pending.kind == PendingDmOfferKind.channel
      ? ChannelTarget(pending.host)
      : GroupTarget(pending.host);
  await gw.dismissDmOffer(host, offerId: pending.offer.offerId);
  // Refresh both lists so the offer row leaves the rail (the derived
  // pendingDmOffersProvider re-reads on invalidation).
  await ref
      .read(conversationListProvider(ConversationKind.channel).notifier)
      .refresh();
  await ref
      .read(conversationListProvider(ConversationKind.group).notifier)
      .refresh();
}
