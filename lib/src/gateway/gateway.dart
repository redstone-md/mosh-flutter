// Sealed seam between the flutter_rust_bridge surface and the Flutter UI.
//
// The app runs on `RealBridgeGateway`; tests run on the scriptable gateway in
// test/support/. Widgets depend on `Gateway`, never on a concrete impl, so
// swapping the wired runtime is one provider change (ADR 0013).
//
// The 57 methods below mirror the Rust `mosh_core::api` surface
// 1:1, poll-based (no streams). Signatures match the generated frb functions.
// The channels/groups read seam adds pollChannel/listChannels/pollGroup/
// listGroups; the channels/groups write seam adds joinChannel/sendChannel/
// leaveChannel/sendGroup/closeGroup/createGroup/joinGroup/
// dismissChannelDmOffer/dismissGroupDmOffer/downloadChannelAttachment/
// cancelChannelAttachment/downloadGroupAttachment/cancelGroupAttachment/
// sendChannelAttachment/sendGroupAttachment; the org write seam adds joinOrg.
// The remaining write halves (dm-offer SEND/listInterfaces/VPN) land in later
// atomics -- the frb functions for them already exist in `lib/src/rust/api/`;
// only the Gateway seam + UI wiring is missing.

import 'dart:typed_data' show Uint8List;
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
  Future<SendMessageResult> sendMessage(
      {required String sessionId, required String body});

  /// Retry a failed outbound DM message (1:1 port of React retryDmMessage ->
  /// Rust private_dm_retry_message). Re-sends a failed outbound message by
  /// its message id; returns the send result (new delivery status) the
  /// screen uses to invalidate its snapshot so the next poll re-renders the
  /// row's delivery status (mirrors retryChannelMessage/retryGroupMessage).
  Future<SendMessageResult> retryDmMessage(
      {required String sessionId, required String messageId});
  Future<SessionSnapshot> pollSession({required String sessionId});
  Future<SessionListSnapshot> listSessions();
  Future<CloseSessionResult> closeSession({required String sessionId});

  // Attachment transfer control (1:1 port of `download_attachment` /
  // `cancel_attachment`). Both drive the peer's inbound transfer; progress
  // surfaces in the next `pollSession` snapshot's `attachments`. The "open"
// action is client-side (opens `localPath` / streams) and has no Rust fn.
  Future<void> downloadAttachment(
      {required String sessionId, required String attachmentId});
  Future<void> cancelAttachment(
      {required String sessionId, required String attachmentId});

  // Channels/groups read seam (1:1 port of `channel_poll`/`channel_list`/
  // `private_group_poll`/`private_group_list`). Poll-based mirrors of the
  // React `pollChannel`/`listChannels`/`pollGroup`/`listGroups` shapes; the
  // write methods (create/join/send/close/...) land in a later atomic.
  Future<ChannelSnapshot> pollChannel({required String name});
  Future<ChannelListSnapshot> listChannels();
  Future<GroupSnapshot> pollGroup({required String groupId});
  Future<GroupListSnapshot> listGroups();

  // Channels/groups write seam (1:1 port of `channel_send`/`channel_leave`/
  // `private_group_send`/`private_group_close`) plus `channel_join` -- the
  // first slice-3 write seam. The minimal write surface a chat screen needs:
  // joining, posting a message, and closing the conversation. The frb channel
  // `leave` and group `close` both map here (channel's teardown is named
  // `leave`, group's is named `close`); `createGroup` is the second slice-3
  // write seam (creates a standalone private MLS group) and `joinGroup` the
  // third (joins a group from a paste/deep-link invite URI);
  // `dismissChannelDmOffer`/`dismissGroupDmOffer` clear a DM offer from a
  // channel/group's offer list (the accept path auto-dismisses after
  // acceptInvite, the dismiss path dismisses directly); attachment/dm-offer
  // SEND write methods stay deferred to a later atomic.
  Future<ChannelSnapshot> joinChannel({required JoinChannelRequest request});
  Future<ChannelSendResult> sendChannel(
      {required String name, required String body});
  Future<ChannelLeaveResult> leaveChannel({required String name});
  // Channel/group message RETRY (1:1 port of channel_retry_message +
  // private_group_retry_message). Re-sends a failed outbound message by
  // its messageId; returns the new send result (new messageId + delivery
  // status) the screen uses to invalidate the snapshot so the next poll
  // re-renders the row's status. Mirrors React's retryChannelMessage/
  // retryGroupMessage (native-messaging-gateway.ts) -- the FailedMessageRetry
  // row's onRetry calls this then invalidates.
  Future<ChannelSendResult> retryChannelMessage(
      {required String name, required String messageId});
  Future<GroupSendResult> sendGroup(
      {required String groupId, required String body});
  Future<GroupSendResult> retryGroupMessage(
      {required String groupId, required String messageId});
  Future<GroupLeaveResult> closeGroup({required String groupId});
  Future<GroupCreated> createGroup({required CreateGroupRequest request});
  Future<GroupSnapshot> joinGroup({required JoinGroupRequest request});
  Future<void> dismissChannelDmOffer(
      {required String name, required String offerId});
  Future<void> dismissGroupDmOffer(
      {required String groupId, required String offerId});
  /// Peer-DM-from-channel seam. Mirrors React `use-dm-offers.ts:54` `offerDm`:
  /// after `createInvite` (Flutter: `createInvite`), the popover sends the
  /// offer over the channel to the target peer. The dismiss pair
  /// `dismissChannelDmOffer` (above) clears a received offer; this is the
  /// outbound send side.
  Future<void> sendChannelDmOffer(
      {required String channelName, required String peerFingerprint, required String inviteUri});
  /// Peer-DM-from-group seam. Same as `sendChannelDmOffer` but for a private
  /// group -- `use-dm-offers.ts:54` branches on `target.type === "group"` and
  /// calls this with the group id. The dismiss pair `dismissGroupDmOffer`
  /// (above) is the inbound dismiss; this is the outbound send side.
  Future<void> sendGroupDmOffer(
      {required String groupId, required String peerFingerprint, required String inviteUri});
  // Channel/group attachment transfer control (1:1 port of channel +
  // private_group download_attachment / cancel_attachment). Both drive the
  // peer's inbound transfer; progress surfaces in the next pollChannel/
  // pollGroup snapshot's attachments. The "open" action is client-side
  // (opens localPath) and has no Rust fn -- the screen handles it.
  Future<void> downloadChannelAttachment(
      {required String name, required String attachmentId});
  Future<void> cancelChannelAttachment(
      {required String name, required String attachmentId});
  Future<void> downloadGroupAttachment(
      {required String groupId, required String attachmentId});
  Future<void> cancelGroupAttachment(
      {required String groupId, required String attachmentId});
  // Channel/group attachment SEND (1:1 port of channel_send_attachment +
  // private_group_send_attachment). The composer reads a picked file into
  // base64 (+ optional thumbnailBase64 / VoiceMeta for voice) and sends.
  // Returns an AttachmentSendResult (attachmentId + contentHash) the screen
  // uses to invalidate the snapshot so the next poll renders the new row.
  // All three conversation kinds (DM, channel, group) are wired -- the DM
  // seam (sendPrivateAttachment) frb-binds to private_dm_send_attachment,
  // which the slice-2 atomic added to mosh-core::api::private_dm.
  Future<AttachmentSendResult> sendChannelAttachment({
    required String name,
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  });

  /// DM attachment SEND (1:1 port of private_dm_send_attachment). Same shape
  /// as sendChannelAttachment/sendGroupAttachment; the only delta is the
  /// session id (the DM identity) instead of a channel name / group id.
  Future<AttachmentSendResult> sendPrivateAttachment({
    required String sessionId,
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  });
  Future<AttachmentSendResult> sendGroupAttachment({
    required String groupId,
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  });

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
