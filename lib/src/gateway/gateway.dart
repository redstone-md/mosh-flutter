// Sealed seam between the flutter_rust_bridge surface and the Flutter UI.
//
// `FakeGateway` (S4) and `RealBridgeGateway` (S5) both implement this interface;
// widgets depend on `Gateway`, never on a concrete impl, so swapping the
// wired runtime is one provider change (ADR 0013).
//
// The thirty methods below mirror the slice-one Rust `mosh_core::api` surface
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

import 'package:mosh/src/rust/api/diagnostics.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/attachment_runtime.dart';
import 'package:mosh/src/rust/org_runtime.dart';

/// Abstraction over the slice-one private-DM + diagnostics API.
///
/// Implementations: `FakeGateway` (in-Dart, first slice only, ADR 0013) and
/// `RealBridgeGateway` (delegates to the generated frb functions, S5). Widgets
/// consume this interface, never a concrete class, so the wired backend is a
/// single Riverpod provider swap.
abstract interface class Gateway {
  Future<AppDiagnostics> appDiagnostics();
  Future<NativeRuntimeStatus> nativeRuntimeStatus();
  Future<InviteCreated> createInvite({required StartSessionRequest request});
  Future<SessionSnapshot> acceptInvite({required AcceptInviteRequest request});
  Future<SendMessageResult> sendMessage(
      {required String sessionId, required String body});
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

  // Org write seam (1:1 port of `org_join`). `joinOrg` is the fourth slice-3
  // write seam -- joins an org from a `mosh://org` bundle URI. Unlike the
  // channel/group flows, the org runtime is a container (members + DM/group
  // offers), not a chat, so the result is an OrgSnapshot the caller uses to
  // refresh the orgs list (no dedicated org screen yet).
  Future<OrgSnapshot> joinOrg({required JoinOrgRequest request});
}
