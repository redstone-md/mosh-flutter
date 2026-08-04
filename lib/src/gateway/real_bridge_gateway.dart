// S5: the slice-one moment-of-truth backend (ADR 0013 close-out).
//
// RealBridgeGateway delegates every Gateway method to the corresponding
// flutter_rust_bridge-generated free function in `lib/src/rust/api/`. It is
// a thin pass-through: no caching, no logic, no shaping -- the same surface
// FakeGateway mocked, now backed by the real `mosh_core` runtime. Widgets
// keep consuming `Gateway` via `gatewayProvider`; this class only exists to
// be swapped in as the default by the provider's `MOSH_FAKE_GATEWAY` flag.
//
// Lifecycle note: every method assumes `RustLib.init()` has run (main.dart
// calls it on startup; the integration test calls it explicitly). Calling
// before init throws via the frb generated `RustLib.instance.api` indirection
// -- which is exactly the behaviour the Fake could not reproduce.

import 'dart:typed_data' show Uint8List;
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
// diagnostics.dart defines both the AppDiagnostics/NativeRuntimeStatus types
// and the appDiagnostics()/nativeRuntimeStatus() free functions. The function
// names collide with this class's own method names, so import the functions
// under the `api` prefix while pulling the types in unqualified.
import 'package:mosh/src/rust/api/diagnostics.dart'
    show AppDiagnostics, NativeRuntimeStatus;
import 'package:mosh/src/rust/api/diagnostics.dart' as api
    show appDiagnostics, nativeRuntimeStatus;
// private_dm.dart defines only free functions (no types); prefix them so
// they don't shadow the interface method names.
import 'package:mosh/src/rust/api/private_dm.dart' as api
    show
        acceptInvite,
        cancelAttachment,
        closeSession,
        createInvite,
        downloadAttachment,
        listSessions,
        pollSession,
        sendAttachment,
        sendMessage,
        retryMessage,
        callStart,
        callAccept,
        callDecline,
        callEnd,
        callSendFrame,
        callDrainFrames;
// channel.dart and private_group.dart each define a `poll` and a `list` free
// function, and each also defines a `send` free function (plus channel `leave`
// and group `close`), so the two imports MUST use distinct prefixes to avoid
// collision; the snapshot/result types come in unqualified from their
// *_runtime.dart modules.
import 'package:mosh/src/rust/api/channel.dart' as channel_api
    show
        join,
        poll,
        list,
        send,
        leave,
        dismissDmOffer,
        downloadAttachment,
        cancelAttachment,
        sendAttachment,
        retryMessage,
        sendDmOffer;
import 'package:mosh/src/rust/api/private_group.dart' as group_api
    show
        createGroup,
        joinGroup,
        poll,
        list,
        send,
        close,
        dismissDmOffer,
        downloadAttachment,
        cancelAttachment,
        sendAttachment,
        retryMessage,
        sendDmOffer;
import 'package:mosh/src/rust/api/org.dart' as org_api
    show
        acceptDmOffer,
        acceptGroupOffer,
        createGroup,
        dismissDmOffer,
        dismissGroupOffer,
        groupInviteMembers,
        joinOrg,
        leaveOrg,
        list,
        poll,
        sendDmOffer;
import 'package:mosh/src/rust/api/network.dart' as network_api
    show listInterfaces;
import 'package:mosh/src/rust/api/vpn.dart' as vpn_api
    show detectVpn, getBindInterface, getVpnBypassConsent, setVpnBypassConsent;
import 'package:mosh/src/rust/api/vpn.dart' show VpnDetection;
import 'package:mosh/src/rust/network_inventory.dart' show NetworkInterfaceInfo;
import 'package:mosh/src/rust/vpn_consent.dart' show VpnBypassConsent;
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/attachment_runtime.dart';
import 'package:mosh/src/rust/org_runtime.dart';

/// Real `mosh_core`-backed Gateway. See file doc for the lifecycle contract.
class RealBridgeGateway implements Gateway {
  @override
  Future<AppDiagnostics> appDiagnostics() => api.appDiagnostics();

  @override
  Future<NativeRuntimeStatus> nativeRuntimeStatus() =>
      api.nativeRuntimeStatus();

  @override
  Future<InviteCreated> createInvite({required StartSessionRequest request}) =>
      api.createInvite(request: request);

  @override
  Future<SessionSnapshot> acceptInvite(
          {required AcceptInviteRequest request}) =>
      api.acceptInvite(request: request);

  @override
  Future<SendMessageResult> sendMessage({
    required String sessionId,
    required String body,
  }) =>
      api.sendMessage(sessionId: sessionId, body: body);

  @override
  Future<SendMessageResult> retryDmMessage({
    required String sessionId,
    required String messageId,
  }) =>
      api.retryMessage(sessionId: sessionId, messageId: messageId);

  @override
  Future<SessionSnapshot> pollSession({required String sessionId}) =>
      api.pollSession(sessionId: sessionId);

  @override
  Future<SessionListSnapshot> listSessions() => api.listSessions();

  @override
  Future<CloseSessionResult> closeSession({required String sessionId}) =>
      api.closeSession(sessionId: sessionId);

  // Attachment transfer control delegates straight to the frb free
  // functions; both return Future<void> so no `await` is needed.
  @override
  Future<void> downloadAttachment({
    required String sessionId,
    required String attachmentId,
  }) =>
      api.downloadAttachment(sessionId: sessionId, attachmentId: attachmentId);

  @override
  Future<void> cancelAttachment({
    required String sessionId,
    required String attachmentId,
  }) =>
      api.cancelAttachment(sessionId: sessionId, attachmentId: attachmentId);

  // Channels/groups read seam delegates straight to the frb free functions.
  // channel_api / group_api keep the colliding `poll`/`list` names apart.
  @override
  Future<ChannelSnapshot> pollChannel({required String name}) =>
      channel_api.poll(name: name);

  @override
  Future<ChannelListSnapshot> listChannels() => channel_api.list();

  @override
  Future<GroupSnapshot> pollGroup({required String groupId}) =>
      group_api.poll(groupId: groupId);

  @override
  Future<GroupListSnapshot> listGroups() => group_api.list();

  // Channels/groups write seam delegates straight to the frb free functions.
  // The two `send` calls are disambiguated by the channel_api/group_api
  // prefixes; channel teardown is `leave`, group teardown is `close`.
  // The `joinChannel` seam (slice-3) delegates to channel_api.join; the
  // request carries name + displayName + listenPort + staticPeer (the same
  // fields InviteFlowState already sources for createInvite, ADR 0010).
  @override
  Future<ChannelSnapshot> joinChannel({required JoinChannelRequest request}) =>
      channel_api.join(request: request);

  @override
  Future<ChannelSendResult> sendChannel(
          {required String name, required String body}) =>
      channel_api.send(name: name, body: body);

  @override
  Future<ChannelSendResult> retryChannelMessage(
          {required String name, required String messageId}) =>
      channel_api.retryMessage(name: name, messageId: messageId);

  @override
  Future<ChannelLeaveResult> leaveChannel({required String name}) =>
      channel_api.leave(name: name);

  @override
  Future<GroupSendResult> sendGroup(
          {required String groupId, required String body}) =>
      group_api.send(groupId: groupId, body: body);

  @override
  Future<GroupSendResult> retryGroupMessage(
          {required String groupId, required String messageId}) =>
      group_api.retryMessage(groupId: groupId, messageId: messageId);

  @override
  Future<GroupLeaveResult> closeGroup({required String groupId}) =>
      group_api.close(groupId: groupId);
  // The `createGroup` seam (slice-3) delegates to group_api.createGroup; the
  // request carries label? + displayName + listenPort + staticPeer? +
  // orgPubkey? (standalone group -- the org-bound variant in org.dart is a
  // different frb function the onboarding Group tile does not use).
  @override
  Future<GroupCreated> createGroup({required CreateGroupRequest request}) =>
      group_api.createGroup(request: request);
  // The `joinGroup` seam (slice-3) delegates to group_api.joinGroup; the
  // request carries inviteUri + displayName + listenPort + staticPeer? +
  // orgPubkey? (null for direct paste/deep-link join; only set when the
  // invite arrived as an org group-offer).
  @override
  Future<GroupSnapshot> joinGroup({required JoinGroupRequest request}) =>
      group_api.joinGroup(request: request);
  // DM-offer dismiss seams (slice-3): channel_api/group_api both name the
  // frb free function `dismissDmOffer` -- disambiguated by the prefixes. The
  // accept path auto-dismisses after acceptInvite; the dismiss path calls
  // these directly. Both return Future<void> (no `await` needed).
  @override
  Future<void> dismissChannelDmOffer(
          {required String name, required String offerId}) =>
      channel_api.dismissDmOffer(name: name, offerId: offerId);
  @override
  Future<void> dismissGroupDmOffer(
          {required String groupId, required String offerId}) =>
      group_api.dismissDmOffer(groupId: groupId, offerId: offerId);
  // Peer-DM-offer SEND seams: channel is wired to the generated Rust facade;
  // group remains a separate atomic for independent review.
  @override
  Future<void> sendChannelDmOffer({required String channelName, required String peerFingerprint, required String inviteUri}) =>
      channel_api.sendDmOffer(name: channelName, targetFingerprint: peerFingerprint, inviteUri: inviteUri);
  @override
  Future<void> sendGroupDmOffer({required String groupId, required String peerFingerprint, required String inviteUri}) =>
      group_api.sendDmOffer(
          groupId: groupId,
          targetFingerprint: peerFingerprint,
          inviteUri: inviteUri);
  // Channel/group attachment transfer seams (slice-3): channel_api/group_api
  // both name the frb free functions `downloadAttachment`/`cancelAttachment`
  // -- disambiguated by the prefixes. Both return Future<void> (no `await`
  // needed). Drive the peer's inbound transfer; progress surfaces in the
  // next pollChannel/pollGroup snapshot's attachments.
  @override
  Future<void> downloadChannelAttachment(
          {required String name, required String attachmentId}) =>
      channel_api.downloadAttachment(name: name, attachmentId: attachmentId);
  @override
  Future<void> cancelChannelAttachment(
          {required String name, required String attachmentId}) =>
      channel_api.cancelAttachment(name: name, attachmentId: attachmentId);
  @override
  Future<void> downloadGroupAttachment(
          {required String groupId, required String attachmentId}) =>
      group_api.downloadAttachment(
          groupId: groupId, attachmentId: attachmentId);
  @override
  Future<void> cancelGroupAttachment(
          {required String groupId, required String attachmentId}) =>
      group_api.cancelAttachment(groupId: groupId, attachmentId: attachmentId);
  // Channel/group attachment SEND seams (slice-3): channel_api/group_api
  // both name the frb free function `sendAttachment` -- disambiguated by the
  // prefixes. The composer passes fileName/mime/dataBase64 (+ optional
  // thumbnailBase64 / VoiceMeta for voice); the result carries attachmentId
  // + contentHash the screen uses to invalidate the snapshot.
  @override
  Future<AttachmentSendResult> sendChannelAttachment({
    required String name,
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  }) =>
      channel_api.sendAttachment(
        name: name,
        fileName: fileName,
        mime: mime,
        dataBase64: dataBase64,
        thumbnailBase64: thumbnailBase64,
        voice: voice,
      );
  @override
  Future<AttachmentSendResult> sendPrivateAttachment({
    required String sessionId,
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  }) =>
      api.sendAttachment(
        sessionId: sessionId,
        fileName: fileName,
        mime: mime,
        dataBase64: dataBase64,
        thumbnailBase64: thumbnailBase64,
        voice: voice,
      );
  @override
  Future<AttachmentSendResult> sendGroupAttachment({
    required String groupId,
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  }) =>
      group_api.sendAttachment(
        groupId: groupId,
        fileName: fileName,
        mime: mime,
        dataBase64: dataBase64,
        thumbnailBase64: thumbnailBase64,
        voice: voice,
      );
  // Org surface (1:1 port of the org_* Tauri commands). Each delegates to
  // org_api (the frb bindings for mosh_core::api::org). The cross-runtime
  // methods (sendOrgDmOffer/acceptOrgDmOffer/createOrgGroup/
  // acceptOrgGroupOffer/orgGroupInviteMembers/leaveOrg) drive the DM/group
  // singletons from inside the org facade on the Rust side, so the Dart
  // call is one method per command (ADR 0010 1:1 rule).
  @override
  Future<OrgSnapshot> joinOrg({required JoinOrgRequest request}) =>
      org_api.joinOrg(request: request);

  @override
  Future<void> leaveOrg({required String orgPubkey}) =>
      org_api.leaveOrg(orgPubkey: orgPubkey);

  @override
  Future<List<OrgSnapshot>> listOrgs() => org_api.list();

  @override
  Future<OrgSnapshot> pollOrg({required String orgPubkey}) =>
      org_api.poll(orgPubkey: orgPubkey);

  @override
  Future<InviteCreated> sendOrgDmOffer({
    required String orgPubkey,
    required String targetPeerId,
    required String displayName,
    required int listenPort,
    String? staticPeer,
  }) =>
      org_api.sendDmOffer(
        orgPubkey: orgPubkey,
        targetPeerId: targetPeerId,
        displayName: displayName,
        listenPort: listenPort,
        staticPeer: staticPeer,
      );

  @override
  Future<SessionSnapshot> acceptOrgDmOffer({
    required String orgPubkey,
    required String offerId,
    required String displayName,
    required int listenPort,
    String? staticPeer,
  }) =>
      org_api.acceptDmOffer(
        orgPubkey: orgPubkey,
        offerId: offerId,
        displayName: displayName,
        listenPort: listenPort,
        staticPeer: staticPeer,
      );

  @override
  Future<void> dismissOrgDmOffer(
          {required String orgPubkey, required String offerId}) =>
      org_api.dismissDmOffer(orgPubkey: orgPubkey, offerId: offerId);

  @override
  Future<GroupCreated> createOrgGroup({
    required String orgPubkey,
    String? label,
    required List<String> memberPeerIds,
    required String displayName,
    required int listenPort,
    String? staticPeer,
  }) =>
      org_api.createGroup(
        orgPubkey: orgPubkey,
        label: label,
        memberPeerIds: memberPeerIds,
        displayName: displayName,
        listenPort: listenPort,
        staticPeer: staticPeer,
      );

  @override
  Future<GroupSnapshot> acceptOrgGroupOffer({
    required String orgPubkey,
    required String offerId,
    required String displayName,
    required int listenPort,
    String? staticPeer,
  }) =>
      org_api.acceptGroupOffer(
        orgPubkey: orgPubkey,
        offerId: offerId,
        displayName: displayName,
        listenPort: listenPort,
        staticPeer: staticPeer,
      );

  @override
  Future<void> dismissOrgGroupOffer(
          {required String orgPubkey, required String offerId}) =>
      org_api.dismissGroupOffer(orgPubkey: orgPubkey, offerId: offerId);

  @override
  Future<void> orgGroupInviteMembers({
    required String orgPubkey,
    required String groupId,
    required List<String> memberPeerIds,
  }) =>
      org_api.groupInviteMembers(
        orgPubkey: orgPubkey,
        groupId: groupId,
        memberPeerIds: memberPeerIds,
      );

  // Network + VPN surface: delegates to network_api / vpn_api (frb
  // bindings for api::network + api::vpn, implemented in 75a2880).
  @override
  Future<List<NetworkInterfaceInfo>> listInterfaces() =>
      network_api.listInterfaces();

  @override
  Future<VpnDetection> detectVpn() => vpn_api.detectVpn();

  @override
  Future<String?> getBindInterface() => vpn_api.getBindInterface();

  @override
  Future<VpnBypassConsent?> getVpnBypassConsent() =>
      vpn_api.getVpnBypassConsent();

  @override
  Future<void> setVpnBypassConsent({String? interfaceName}) =>
      vpn_api.setVpnBypassConsent(interface_: interfaceName);
  // Voice-call surface: delegates to api (frb bindings for api::private_dm
  // call_*, implemented in c86b712). DM-only.
  @override
  Future<CallStarted> callStart({required String sessionId}) =>
      api.callStart(sessionId: sessionId);

  @override
  Future<void> callAccept({
    required String sessionId,
    required String callId,
  }) =>
      api.callAccept(sessionId: sessionId, callId: callId);

  @override
  Future<void> callDecline({
    required String sessionId,
    required String callId,
    required String reason,
  }) =>
      api.callDecline(sessionId: sessionId, callId: callId, reason: reason);

  @override
  Future<void> callEnd({
    required String sessionId,
    required String callId,
    required String reason,
  }) =>
      api.callEnd(sessionId: sessionId, callId: callId, reason: reason);

  @override
  Future<void> callSendFrame({
    required String sessionId,
    required String callId,
    required Uint8List frame,
  }) =>
      api.callSendFrame(sessionId: sessionId, callId: callId, frame: frame);

  @override
  Future<List<Uint8List>> callDrainFrames({
    required String sessionId,
    required String callId,
  }) =>
      api.callDrainFrames(sessionId: sessionId, callId: callId);
}
