// The direct bridge facade: every call that only mirrors one generated
// frb function, with no seam around it (ADR 0025).
//
// `Gateway` is deliberately narrow -- the conversation seam, the surface
// widgets and controllers share and the only surface a test scripts. These
// 34 calls mirror one `mosh_core::api` function 1:1 and hide no decision:
// no target parameter, no kind branch, no shaping. Faking them wholesale
// in tests is what made the scripted double mirror 42 methods, so they
// moved out of the interface; a caller reaches this class through
// `bridgeFacadeProvider` instead. (The one argument alias happens here:
// the DM-offer sends take `peerFingerprint`, the generated function's
// `targetFingerprint` -- a parameter name, not behaviour.)
//
// Like the Gateway, every method assumes `RustLib.init()` has run
// (main.dart calls it on startup; the integration test calls it
// explicitly). The frb free functions come in prefixed because their
// names collide with the facade's method names.
//
// Size exception: 34 one-line mirrors over `type_max_loc: 200`; reason,
// scope and removal plan in ADR 0025.

import 'dart:typed_data' show Uint8List;

import 'package:mosh/src/rust/channel_runtime.dart'
    show ChannelListSnapshot, ChannelSnapshot, JoinChannelRequest;
import 'package:mosh/src/rust/private_group_runtime.dart'
    show
        CreateGroupRequest,
        GroupCreated,
        GroupListSnapshot,
        GroupSnapshot,
        JoinGroupRequest;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show
        AcceptInviteRequest,
        CallStarted,
        InviteCreated,
        SessionListSnapshot,
        SessionSnapshot,
        StartSessionRequest;
import 'package:mosh/src/rust/api/diagnostics.dart'
    show AppDiagnostics, MossLibraryInfo, NativeRuntimeStatus;
import 'package:mosh/src/rust/api/diagnostics.dart' as api
    show appDiagnostics, mossLibraryInfo, nativeRuntimeStatus;
import 'package:mosh/src/rust/api/private_dm.dart' as api
    show
        acceptInvite,
        callAccept,
        callDecline,
        callDrainFrames,
        callEnd,
        callSendFrame,
        callStart,
        createInvite,
        listSessions,
        readReceiptsEnabled,
        setReadReceiptsEnabled;
import 'package:mosh/src/rust/api/channel.dart' as channel_api
    show join, list, sendDmOffer;
import 'package:mosh/src/rust/api/private_group.dart' as group_api
    show createGroup, joinGroup, list, sendDmOffer;
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
import 'package:mosh/src/rust/org_runtime.dart'
    show JoinOrgRequest, OrgSnapshot;
import 'package:mosh/src/rust/vpn_consent.dart' show VpnBypassConsent;

/// The 1:1 bridge mirrors, outside the [Gateway] seam (ADR 0025).
///
/// One class, one responsibility: forward each call to the generated frb
/// function of the same name. Nothing here is worth scripting -- tests fake
/// it through `bridgeFacadeProvider` only where a screen needs canned data
/// or a scripted failure (test/support/scriptable_bridge.dart).
class BridgeFacade {
  // Diagnostics: app identity + native runtime readiness (S4.8).
  Future<AppDiagnostics> appDiagnostics() => api.appDiagnostics();

  Future<NativeRuntimeStatus> nativeRuntimeStatus() =>
      api.nativeRuntimeStatus();

  // Diagnostics: the loaded moss library's own version + the last measured
  // RTT to the active DM counterpart (spec #5). peerMossId is the snapshot's
  // peer id; null asks about the library alone.
  Future<MossLibraryInfo> mossLibraryInfo({String? peerMossId}) =>
      api.mossLibraryInfo(peerMossId: peerMossId);

  // Invite/session setup: mint an invite, accept one, read the DM list.
  // The DM list feeds the rail; the conversation's own state is a Gateway
  // poll.
  Future<InviteCreated> createInvite({required StartSessionRequest request}) =>
      api.createInvite(request: request);

  Future<SessionSnapshot> acceptInvite(
          {required AcceptInviteRequest request}) =>
      api.acceptInvite(request: request);

  Future<SessionListSnapshot> listSessions() => api.listSessions();

  // The app-level read-receipts answer (issue #2): one toggle covering
  // every DM, persisted on the Rust side. `readReceiptsEnabled` is a file
  // read, not a runtime action, so the settings screen can show it before
  // any session exists.
  Future<bool> readReceiptsEnabled() => api.readReceiptsEnabled();

  Future<void> setReadReceiptsEnabled({required bool enabled}) =>
      api.setReadReceiptsEnabled(enabled: enabled);

  // Channels/groups read seam (1:1 port of `channel_list`/
  // `private_group_list`). One conversation's own state comes from the
  // Gateway's typed poll, not from here.
  Future<ChannelListSnapshot> listChannels() => channel_api.list();

  Future<GroupListSnapshot> listGroups() => group_api.list();

  // Channels/groups write seam (1:1 port of `channel_join`,
  // `private_group_create` and `private_group_join`) -- the parts of
  // joining and creating a conversation that are not shared with the other
  // kinds. Sending, retrying, leaving and the DM-offer dismiss live in the
  // Gateway conversation seam.
  Future<ChannelSnapshot> joinChannel({required JoinChannelRequest request}) =>
      channel_api.join(request: request);

  // createGroup makes the standalone group; the org-bound variant in
  // org.dart is a different frb function the onboarding Group tile does not
  // use.
  Future<GroupCreated> createGroup({required CreateGroupRequest request}) =>
      group_api.createGroup(request: request);

  // joinGroup's orgPubkey stays null for direct paste/deep-link joins; it
  // is set only when the invite arrived as an org group-offer.
  Future<GroupSnapshot> joinGroup({required JoinGroupRequest request}) =>
      group_api.joinGroup(request: request);

  // Peer-DM-offer SEND seams: the outbound counterpart of the Gateway's
  // dismissDmOffer. Mirrors React `use-dm-offers.ts:54` `offerDm` -- after
  // createInvite, the popover sends the offer over the channel or group to
  // the target peer.
  Future<void> sendChannelDmOffer(
          {required String channelName,
          required String peerFingerprint,
          required String inviteUri}) =>
      channel_api.sendDmOffer(
          name: channelName,
          targetFingerprint: peerFingerprint,
          inviteUri: inviteUri);

  Future<void> sendGroupDmOffer(
          {required String groupId,
          required String peerFingerprint,
          required String inviteUri}) =>
      group_api.sendDmOffer(
          groupId: groupId,
          targetFingerprint: peerFingerprint,
          inviteUri: inviteUri);

  // Org surface (1:1 port of the org_* Tauri commands). The org runtime is
  // a container (members + DM/group offers), not a chat: joinOrg is the
  // onboarding invite-paste join; leaveOrg closes the org + its bound
  // private groups; listOrgs/pollOrg read; sendOrgDmOffer/acceptOrgDmOffer/
  // dismissOrgDmOffer drive the DM-offer flow; createOrgGroup/
  // acceptOrgGroupOffer/dismissOrgGroupOffer/orgGroupInviteMembers drive
  // the group-offer flow.
  Future<OrgSnapshot> joinOrg({required JoinOrgRequest request}) =>
      org_api.joinOrg(request: request);

  Future<void> leaveOrg({required String orgPubkey}) =>
      org_api.leaveOrg(orgPubkey: orgPubkey);

  Future<List<OrgSnapshot>> listOrgs() => org_api.list();

  Future<OrgSnapshot> pollOrg({required String orgPubkey}) =>
      org_api.poll(orgPubkey: orgPubkey);

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

  Future<void> dismissOrgDmOffer(
          {required String orgPubkey, required String offerId}) =>
      org_api.dismissDmOffer(orgPubkey: orgPubkey, offerId: offerId);

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

  Future<void> dismissOrgGroupOffer(
          {required String orgPubkey, required String offerId}) =>
      org_api.dismissGroupOffer(orgPubkey: orgPubkey, offerId: offerId);

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

  // Network + VPN surface (1:1 port of the list_network_interfaces /
  // detect_vpn / get_bind_interface / get+set_vpn_bypass_consent Tauri
  // commands).
  Future<List<NetworkInterfaceInfo>> listInterfaces() =>
      network_api.listInterfaces();

  Future<VpnDetection> detectVpn() => vpn_api.detectVpn();

  Future<String?> getBindInterface() => vpn_api.getBindInterface();

  Future<VpnBypassConsent?> getVpnBypassConsent() =>
      vpn_api.getVpnBypassConsent();

  Future<void> setVpnBypassConsent({String? interfaceName}) =>
      vpn_api.setVpnBypassConsent(interface_: interfaceName);

  // Voice-call surface (1:1 port of the private_dm_call_* Tauri commands).
  // DM-only -- channels/groups have no call path. callStart mints the call
  // id + key + nonce prefix and moves the session to outgoing-ringing;
  // callAccept/callDecline/callEnd drive the control state; callSendFrame/
  // callDrainFrames are the 20ms audio-frame transport the Dart capture/
  // playback loops drive.
  Future<CallStarted> callStart({required String sessionId}) =>
      api.callStart(sessionId: sessionId);

  Future<void> callAccept({
    required String sessionId,
    required String callId,
  }) =>
      api.callAccept(sessionId: sessionId, callId: callId);

  Future<void> callDecline({
    required String sessionId,
    required String callId,
    required String reason,
  }) =>
      api.callDecline(sessionId: sessionId, callId: callId, reason: reason);

  Future<void> callEnd({
    required String sessionId,
    required String callId,
    required String reason,
  }) =>
      api.callEnd(sessionId: sessionId, callId: callId, reason: reason);

  Future<void> callSendFrame({
    required String sessionId,
    required String callId,
    required Uint8List frame,
  }) =>
      api.callSendFrame(sessionId: sessionId, callId: callId, frame: frame);

  Future<List<Uint8List>> callDrainFrames({
    required String sessionId,
    required String callId,
  }) =>
      api.callDrainFrames(sessionId: sessionId, callId: callId);
}
