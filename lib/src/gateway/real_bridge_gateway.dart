// S5: the slice-one moment-of-truth backend (ADR 0013 close-out).
//
// RealBridgeGateway delegates every Gateway method to the corresponding
// flutter_rust_bridge-generated free function in `lib/src/rust/api/`. It is
// a thin pass-through: no caching, no logic, no shaping. The one conversion
// it makes is the conversation ref: the six shared conversation actions go
// over the bridge as a typed `BridgeConversationRef`, and the bridge
// function picks the runtime (ADR 0024). `dismissDmOffer` keeps its switch
// -- a DM has no offer list, so only two kinds answer it (ADR 0017).
//
// Lifecycle: every method assumes `RustLib.init()` has run (main.dart calls
// it on startup; the integration test calls it explicitly). Calling before
// init throws via the generated `RustLib.instance.api` indirection -- the
// behaviour a Dart double cannot reproduce.

import 'dart:typed_data' show Uint8List;
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
// diagnostics.dart's function names collide with this class's method names,
// so its functions come in under the `api` prefix, its types unqualified.
import 'package:mosh/src/rust/api/diagnostics.dart'
    show AppDiagnostics, NativeRuntimeStatus;
import 'package:mosh/src/rust/api/diagnostics.dart' as api
    show appDiagnostics, nativeRuntimeStatus;
// private_dm.dart defines only free functions (no types); prefix them so
// they don't shadow the interface method names.
import 'package:mosh/src/rust/api/private_dm.dart' as api
    show
        acceptInvite,
        createInvite,
        listSessions,
        pollSession,
        callStart,
        callAccept,
        callDecline,
        callEnd,
        callSendFrame,
        callDrainFrames;
// The six shared conversation actions (ADR 0024): functions are prefixed
// (they collide with the interface method names); the ref/payload types
// come in unqualified, like the diagnostics types.
import 'package:mosh/src/rust/api/conversation.dart'
    show BridgeAttachmentPayload, BridgeConversationKind, BridgeConversationRef;
import 'package:mosh/src/rust/api/conversation.dart' as conversation_api
    show
        cancelAttachment,
        downloadAttachment,
        leave,
        retry,
        send,
        sendAttachment;
// channel.dart and private_group.dart each define a `poll` and a `list` free
// function, so the two imports MUST use distinct prefixes to avoid collision;
// the snapshot types come in unqualified from their *_runtime.dart modules.
import 'package:mosh/src/rust/api/channel.dart' as channel_api
    show join, poll, list, dismissDmOffer, sendDmOffer;
import 'package:mosh/src/rust/api/private_group.dart' as group_api
    show createGroup, joinGroup, poll, list, dismissDmOffer, sendDmOffer;
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
class RealBridgeGateway implements Gateway, ConversationSnapshotReader {
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
  Future<SessionListSnapshot> listSessions() => api.listSessions();

  // --------------------------------------------------------------------
  // The conversation seam. Typed polls keep one read per kind; the six
  // shared actions convert the target to a typed ref once and call the one
  // shared bridge function (ADR 0024) -- the kind dispatch lives in the
  // bridge, beside the runtime handles it picks between.
  // --------------------------------------------------------------------

  /// The conversation a shared action addresses, as the bridge names it:
  /// kind + id in one typed value. The adapter's whole kind decision; the
  /// bridge function owns the dispatch from here (ADR 0024).
  static BridgeConversationRef _bridgeRef(AnyConversationTarget target) =>
      BridgeConversationRef(
        kind: switch (target.kind) {
          ConversationKind.dm => BridgeConversationKind.dm,
          ConversationKind.channel => BridgeConversationKind.channel,
          ConversationKind.group => BridgeConversationKind.group,
        },
        id: target.id,
      );

  @override
  Future<S> poll<S>(ConversationTarget<S> target) => target.readSnapshot(this);

  @override
  Future<SessionSnapshot> dmSnapshot(String sessionId) =>
      api.pollSession(sessionId: sessionId);

  @override
  Future<ChannelSnapshot> channelSnapshot(String name) =>
      channel_api.poll(name: name);

  @override
  Future<GroupSnapshot> groupSnapshot(String groupId) =>
      group_api.poll(groupId: groupId);

  @override
  Future<void> send(AnyConversationTarget target, {required String body}) =>
      conversation_api.send(reference: _bridgeRef(target), body: body);

  @override
  Future<void> retry(AnyConversationTarget target,
          {required String messageId}) =>
      conversation_api.retry(
          reference: _bridgeRef(target), messageId: messageId);

  @override
  Future<void> sendAttachment(
    AnyConversationTarget target, {
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  }) =>
      conversation_api.sendAttachment(
        reference: _bridgeRef(target),
        payload: BridgeAttachmentPayload(
          fileName: fileName,
          mime: mime,
          dataBase64: dataBase64,
          thumbnailBase64: thumbnailBase64,
          voice: voice,
        ),
      );

  @override
  Future<void> downloadAttachment(AnyConversationTarget target,
          {required String attachmentId}) =>
      conversation_api.downloadAttachment(
          reference: _bridgeRef(target), attachmentId: attachmentId);

  @override
  Future<void> cancelAttachment(AnyConversationTarget target,
          {required String attachmentId}) =>
      conversation_api.cancelAttachment(
          reference: _bridgeRef(target), attachmentId: attachmentId);

  @override
  Future<void> dismissDmOffer(DmOfferHost<Object?> target,
          {required String offerId}) =>
      switch (target) {
        ChannelTarget(:final id) =>
          channel_api.dismissDmOffer(name: id, offerId: offerId),
        GroupTarget(:final id) =>
          group_api.dismissDmOffer(groupId: id, offerId: offerId),
      };

  @override
  Future<void> leave(AnyConversationTarget target) =>
      conversation_api.leave(reference: _bridgeRef(target));

  // --------------------------------------------------------------------

  // Channels/groups read seam delegates straight to the frb free functions.
  @override
  Future<ChannelListSnapshot> listChannels() => channel_api.list();

  @override
  Future<GroupListSnapshot> listGroups() => group_api.list();

  // Channels/groups write seam delegates straight to the frb free functions;
  // the request types carry the fields (ADR 0010).
  @override
  Future<ChannelSnapshot> joinChannel({required JoinChannelRequest request}) =>
      channel_api.join(request: request);

  // createGroup makes the standalone group; the org-bound variant in
  // org.dart is a different frb function the onboarding Group tile does not
  // use.
  @override
  Future<GroupCreated> createGroup({required CreateGroupRequest request}) =>
      group_api.createGroup(request: request);
  // joinGroup's orgPubkey stays null for direct paste/deep-link joins; it is
  // set only when the invite arrived as an org group-offer.
  @override
  Future<GroupSnapshot> joinGroup({required JoinGroupRequest request}) =>
      group_api.joinGroup(request: request);
  // Peer-DM-offer SEND seams: the outbound counterpart of dismissDmOffer.
  @override
  Future<void> sendChannelDmOffer(
          {required String channelName,
          required String peerFingerprint,
          required String inviteUri}) =>
      channel_api.sendDmOffer(
          name: channelName,
          targetFingerprint: peerFingerprint,
          inviteUri: inviteUri);
  @override
  Future<void> sendGroupDmOffer(
          {required String groupId,
          required String peerFingerprint,
          required String inviteUri}) =>
      group_api.sendDmOffer(
          groupId: groupId,
          targetFingerprint: peerFingerprint,
          inviteUri: inviteUri);
  // Org surface: each delegates to org_api (frb bindings for
  // mosh_core::api::org). The cross-runtime methods drive the DM/group
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

  // Network + VPN surface: delegates to network_api / vpn_api.
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
  // call_*). DM-only.
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
