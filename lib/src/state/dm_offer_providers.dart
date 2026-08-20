// DM-offer rail server-state provider -- the Flutter mirror of React
// useDmOffers pendingOffers (src/features/private-dm/use-dm-offers.ts).
// Flattens the per-channel + per-group dmOffers lists into one flat list
// of [PendingDmOffer] tagged with the originating host + kind, exactly as
// React pendingOffers = [...channels.flatMap(...), ...groups.flatMap(...)]
// does. The SessionsScreen renders one [OfferRailItem] per pending offer at
// the top of the rail (React SessionRail order: offers -> sessions -> groups
// -> channels -> orgs).
//
// Per ADR 0010: this is a derived provider (no Gateway call of its own --
// it watches channelListProvider + groupListProvider, the existing
// server-state reads), so it auto-refreshes when either list invalidates
// (after a dismiss/join/leave). No new Rust / frb codegen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/rust/conversation/dm_offers.dart';
import 'package:mosh/src/state/channel_group_providers.dart';

/// The originating conversation kind for a pending DM offer. Mirrors React
/// offer.kind === "channel" | "group" discriminator.
enum PendingDmOfferKind { channel, group }

/// A DM offer pending action, tagged with its originating host + kind.
/// Mirrors React PendingDmOffer = DmOffer & { kind, host } (use-dm-offers.ts):
/// the raw DmOffer (offerId/fromDevice/fromFingerprint/targetFingerprint/
/// inviteUri) plus kind (channel | group) and host (channel name OR group
/// groupId -- the key the dismiss call needs).
class PendingDmOffer {
  const PendingDmOffer({
    required this.offer,
    required this.kind,
    required this.host,
  });

  final DmOffer offer;
  final PendingDmOfferKind kind;

  /// The channel name (kind == channel) or group groupId (kind == group).
  /// Passed to [Gateway.dismissChannelDmOffer] / [Gateway.dismissGroupDmOffer]
  /// as the name / groupId arg.
  final String host;
}

/// The flat list of pending DM offers across all channels + groups. Derived
/// from channelListProvider + groupListProvider (the existing server-state
/// reads), so it auto-refreshes when either invalidates. Empty when both
/// lists are loading/error/empty. Order is channels-first-then-groups,
/// matching React pendingOffers spread order.
final pendingDmOffersProvider = Provider<List<PendingDmOffer>>((ref) {
  final channels = ref.watch(channelListProvider).value?.channels ?? const [];
  final groups = ref.watch(groupListProvider).value?.groups ?? const [];
  return [
    for (final channel in channels)
      for (final offer in channel.dmOffers)
        PendingDmOffer(
            offer: offer, kind: PendingDmOfferKind.channel, host: channel.name),
    for (final group in groups)
      for (final offer in group.dmOffers)
        PendingDmOffer(
            offer: offer, kind: PendingDmOfferKind.group, host: group.groupId),
  ];
});
