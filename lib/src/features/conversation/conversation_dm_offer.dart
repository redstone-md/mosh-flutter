import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show InviteCreated, StartSessionRequest;

/// Owns a newly created invitation until its conversation offer is published.
Future<InviteCreated> createAndOfferDm({
  required BridgeFacade bridge,
  required Gateway gateway,
  required DmOfferHost<Object?> host,
  required String peerFingerprint,
  required StartSessionRequest request,
}) async {
  final invite = await bridge.createInvite(request: request);
  try {
    await switch (host) {
      ChannelTarget() => bridge.sendChannelDmOffer(
          channelName: host.id,
          peerFingerprint: peerFingerprint,
          inviteUri: invite.inviteUri,
        ),
      GroupTarget() => bridge.sendGroupDmOffer(
          groupId: host.id,
          peerFingerprint: peerFingerprint,
          inviteUri: invite.inviteUri,
        ),
    };
  } catch (_) {
    try {
      await gateway.leave(DmTarget(invite.sessionId));
    } catch (_) {
      // Keep the publication error when cleanup also fails.
    }
    rethrow;
  }
  return invite;
}
