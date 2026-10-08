part of 'sessions_screen_test.dart';

/// The pair of doubles the rail flow crosses: the bridge serves the lists
/// and the accept; the gateway answers the dismiss and the DM poll. Both see
/// one conversation state.
(ScriptableGateway, ScriptableBridge) _scriptedPair() {
  final gateway = ScriptableGateway();
  final bridge = ScriptableBridge(conversations: gateway.conversations);
  return (gateway, bridge);
}

/// A bridge holding one channel that carries a DM offer, so the sessions
/// rail renders an offer row (pendingDmOffersProvider derives from
/// channel.dmOffers). Returns the pair so the dismiss (seam) and the accept
/// + lists (facade) both have a double.
(ScriptableGateway, ScriptableBridge) _channelOfferBridge() {
  final (gateway, bridge) = _scriptedPair();
  bridge.seedChannels([
    ChannelSnapshot(
      name: 'drift-room',
      topic: '',
      meshId: 'm',
      displayName: '',
      deviceFingerprint: 'SELF',
      messages: const [],
      attachments: const [],
      dmOffers: [
        DmOffer(
          offerId: 'offer-1',
          fromDevice: 'alpha-peer',
          fromFingerprint: 'PEERFP',
          targetFingerprint: 'SELF',
          inviteUri: 'mosh://invite?mesh=m&session=drift-41#fp=91A4-D2C8-77B0',
        ),
      ],
      mesh: null,
      events: const [],
    ),
  ]);

  return (gateway, bridge);
}

SessionSnapshot _session({
  required String sessionId,
  required String displayName,
  required String peerDisplayName,
  required DmSessionState state,
}) =>
    SessionSnapshot(
      inviteAvailable: false,
      sessionId: sessionId,
      meshId: 'm',
      role: 'inviter',
      displayName: displayName,
      peerDisplayName: peerDisplayName,
      state: state,
      transport: PeerTransport.none,
      inviteUri: null,
      fingerprint: 'AABB',
      messages: const [],
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: null,
      outgoingCall: null,
      activeCall: null,
    );
