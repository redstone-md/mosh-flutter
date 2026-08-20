// Sealed seam between the flutter_rust_bridge surface and the Flutter UI.
//
// The app runs on `RealBridgeGateway`; tests run on the scriptable gateway in
// test/support/. Widgets depend on `Gateway`, never on a concrete impl, so
// swapping the wired runtime is one provider change (ADR 0013).
//
// The methods below are poll-based (no streams). Most mirror one Rust
// `mosh_core::api` function 1:1 and match its generated frb signature.
//
// The conversation methods are the exception: send, retry, poll, attachment
// send/download/cancel, DM-offer dismiss and leave each take a
// [ConversationTarget] instead of coming in a DM, a channel and a group
// flavour. The adapter picks the frb function for the kind, so callers stop
// dispatching on it (ADR 0017). The frb facade itself stays 1:1 with Rust.

import 'dart:typed_data' show Uint8List;
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/api/diagnostics.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/attachment_runtime.dart';
import 'package:mosh/src/rust/org_runtime.dart';
import 'package:mosh/src/rust/api/vpn.dart';
import 'package:mosh/src/rust/network_inventory.dart';
import 'package:mosh/src/rust/vpn_consent.dart';

/// Abstraction over the slice-one private-DM + diagnostics API.
///
/// Implementations: `RealBridgeGateway` (delegates to the generated frb
/// functions) in the app, and `ScriptableGateway` (test/support/) in tests.
/// Widgets consume this interface, never a concrete class, so the wired
/// backend is a single Riverpod provider swap.
abstract interface class Gateway {
  Future<AppDiagnostics> appDiagnostics();
  Future<NativeRuntimeStatus> nativeRuntimeStatus();
  Future<InviteCreated> createInvite({required StartSessionRequest request});
  Future<SessionSnapshot> acceptInvite({required AcceptInviteRequest request});
  Future<SessionListSnapshot> listSessions();

  // ------------------------------------------------------------------------
  // The conversation seam. One method per action, for all three kinds.
  // ------------------------------------------------------------------------

  /// Reads [target]'s current state. The snapshot type follows the kind:
  /// a DM polls back a [SessionSnapshot], a channel a [ChannelSnapshot],
  /// a group a [GroupSnapshot].
  ///
  /// An implementation also implements [ConversationSnapshotReader] and hands
  /// itself to the target, which is what keeps the return type honest without
  /// a cast. The reader is not part of this interface: callers never see it.
  Future<S> poll<S>(ConversationTarget<S> target);

  /// Sends a text message to [target].
  ///
  /// The message's delivery status arrives with the next [poll], so the
  /// caller invalidates its snapshot after this returns instead of reading
  /// a result here.
  Future<void> send(AnyConversationTarget target, {required String body});

  /// Re-sends a failed outbound message of [target] by its id. Same
  /// delivery-status rule as [send]: read it from the next [poll].
  Future<void> retry(AnyConversationTarget target, {required String messageId});

  /// Sends a file to [target]. The caller reads the picked file into base64
  /// and adds a thumbnail or voice metadata when it has them. The result
  /// carries the attachment id and content hash of the new row.
  Future<AttachmentSendResult> sendAttachment(
    AnyConversationTarget target, {
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  });

  /// Starts the inbound transfer of one of [target]'s attachments. Progress
  /// surfaces in the next [poll] snapshot. Opening a finished file is
  /// client-side and has no Rust function.
  Future<void> downloadAttachment(AnyConversationTarget target,
      {required String attachmentId});

  /// Stops an in-flight transfer of one of [target]'s attachments.
  Future<void> cancelAttachment(AnyConversationTarget target,
      {required String attachmentId});

  /// Clears a DM offer from [target]'s offer list. The accept path dismisses
  /// the offer itself after acceptInvite; this is the decline path. A DM
  /// holds no offers, which is why the parameter is a [DmOfferHost].
  Future<void> dismissDmOffer(DmOfferHost<Object?> target,
      {required String offerId});

  /// Leaves [target]: closes the DM session, leaves the channel, or closes
  /// the group. The caller invalidates its snapshot and navigates away.
  Future<void> leave(AnyConversationTarget target);

  // ------------------------------------------------------------------------

  // Channels/groups read seam (1:1 port of `channel_list`/
  // `private_group_list`). Poll-based mirrors of the React `listChannels`/
  // `listGroups` shapes; one conversation's own state comes from [poll].
  Future<ChannelListSnapshot> listChannels();
  Future<GroupListSnapshot> listGroups();

  // Channels/groups write seam (1:1 port of `channel_join`,
  // `private_group_create` and `private_group_join`) -- the parts of joining
  // and creating a conversation that are not shared with the other kinds.
  // Sending, retrying, leaving and the DM-offer dismiss all live in the
  // conversation seam above.
  Future<ChannelSnapshot> joinChannel({required JoinChannelRequest request});
  Future<GroupCreated> createGroup({required CreateGroupRequest request});
  Future<GroupSnapshot> joinGroup({required JoinGroupRequest request});

  /// Peer-DM-from-channel seam. Mirrors React `use-dm-offers.ts:54` `offerDm`:
  /// after `createInvite`, the popover sends the offer over the channel to the
  /// target peer. [dismissDmOffer] clears a received offer; this is the
  /// outbound send side.
  Future<void> sendChannelDmOffer(
      {required String channelName, required String peerFingerprint, required String inviteUri});

  /// Peer-DM-from-group seam. Same as `sendChannelDmOffer` but for a private
  /// group -- `use-dm-offers.ts:54` branches on `target.type === "group"` and
  /// calls this with the group id.
  Future<void> sendGroupDmOffer(
      {required String groupId, required String peerFingerprint, required String inviteUri});

  // Org surface (1:1 port of the org_* Tauri commands). The org runtime
  // is a container (members + DM/group offers), not a chat. joinOrg is the
  // only method a UI calls directly today (the invite-paste onboarding);
  // the rest are surfaced so a future org screen can drive the real runtime
  // through the Gateway seam (ADR 0013 -- widgets depend on Gateway, never
  // on a concrete impl). leaveOrg closes the org + its bound private groups;
  // listOrgs/pollOrg read; sendOrgDmOffer/acceptOrgDmOffer/dismissOrgDmOffer
  // drive the DM-offer flow (mint/accept via the private-DM runtime,
  // record/link in the org runtime); createOrgGroup/acceptOrgGroupOffer/
  // dismissOrgGroupOffer/orgGroupInviteMembers drive the group-offer flow.
  Future<OrgSnapshot> joinOrg({required JoinOrgRequest request});
  Future<void> leaveOrg({required String orgPubkey});
  Future<List<OrgSnapshot>> listOrgs();
  Future<OrgSnapshot> pollOrg({required String orgPubkey});
  Future<InviteCreated> sendOrgDmOffer({
    required String orgPubkey,
    required String targetPeerId,
    required String displayName,
    required int listenPort,
    String? staticPeer,
  });
  Future<SessionSnapshot> acceptOrgDmOffer({
    required String orgPubkey,
    required String offerId,
    required String displayName,
    required int listenPort,
    String? staticPeer,
  });
  Future<void> dismissOrgDmOffer(
      {required String orgPubkey, required String offerId});
  Future<GroupCreated> createOrgGroup({
    required String orgPubkey,
    String? label,
    required List<String> memberPeerIds,
    required String displayName,
    required int listenPort,
    String? staticPeer,
  });
  Future<GroupSnapshot> acceptOrgGroupOffer({
    required String orgPubkey,
    required String offerId,
    required String displayName,
    required int listenPort,
    String? staticPeer,
  });
  Future<void> dismissOrgGroupOffer(
      {required String orgPubkey, required String offerId});
  Future<void> orgGroupInviteMembers({
    required String orgPubkey,
    required String groupId,
    required List<String> memberPeerIds,
  });

  // Network + VPN surface (1:1 port of the list_network_interfaces /
  // detect_vpn / get_bind_interface / get+set_vpn_bypass_consent Tauri
  // commands). Surfaced for a future VPN-consent screen + diagnostics (ADR 0013).
  Future<List<NetworkInterfaceInfo>> listInterfaces();
  Future<VpnDetection> detectVpn();
  Future<String?> getBindInterface();
  Future<VpnBypassConsent?> getVpnBypassConsent();
  Future<void> setVpnBypassConsent({String? interfaceName});
  // Voice-call surface (1:1 port of the private_dm_call_* Tauri commands).
  // DM-only -- channels/groups have no call path. callStart mints the call id
  // + key + nonce prefix and moves the session to outgoing-ringing;
  // callAccept/callDecline/callEnd drive the control state; callSendFrame/
  // callDrainFrames are the 20ms audio-frame transport the Dart capture/
  // playback loops drive. Surfaced for the IncomingCallModal/OutgoingCall
  // Modal/CallOverlay UI (ADR 0013).
  Future<CallStarted> callStart({required String sessionId});
  Future<void> callAccept({required String sessionId, required String callId});
  Future<void> callDecline({
    required String sessionId,
    required String callId,
    required String reason,
  });
  Future<void> callEnd({
    required String sessionId,
    required String callId,
    required String reason,
  });
  Future<void> callSendFrame({
    required String sessionId,
    required String callId,
    required Uint8List frame,
  });
  Future<List<Uint8List>> callDrainFrames({
    required String sessionId,
    required String callId,
  });
}
