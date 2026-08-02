// In-Dart test double for the slice-one Gateway surface (ADR 0013).
// Lets widget tests run without the Rust runtime: implements the Gateway
// methods with canned data + an in-memory session map. Canned snapshots
// live in fake_gateway_snapshots.dart (extracted to keep this under 500 lines).

import 'dart:typed_data' show Uint8List;
import 'package:mosh/src/gateway/fake_gateway_snapshots.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/rust/api/diagnostics.dart'
    show AppDiagnostics, NativeRuntimeStatus;
import 'package:mosh/src/rust/api/vpn.dart' show VpnDetection;
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/network_inventory.dart' show NetworkInterfaceInfo;
import 'package:mosh/src/rust/org_runtime.dart';
import 'package:mosh/src/rust/attachment_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/vpn_consent.dart' show VpnBypassConsent;

/// Slice-one fake runtime: canned diagnostics + an in-memory session map.
///
/// Stateful by design (ADR 0013): createInvite/acceptInvite insert a
/// SessionSnapshot; sendMessage/pollSession/closeSession mutate or read it.
/// Canned snapshots come from fake_gateway_snapshots.dart (pure helpers).
class FakeGateway implements Gateway {
  final Map<String, SessionSnapshot> _sessions = {};
  int _channelSendCount = 0;
  int _groupSendCount = 0;

  @override
  Future<AppDiagnostics> appDiagnostics() =>
      Future.value(cannedAppDiagnostics());

  @override
  Future<NativeRuntimeStatus> nativeRuntimeStatus() =>
      Future.value(cannedNativeRuntimeStatus());

  @override
  Future<InviteCreated> createInvite({required StartSessionRequest request}) {
    final sessionId = 'fake-${_sessions.length + 1}';
    final fingerprint = fakeFingerprint(sessionId);
    final inviteUri =
        'mosh://invite?mesh=fakemesh&session=$sessionId#fp=$fingerprint';
    final created = InviteCreated(
      inviteUri: inviteUri,
      sessionId: sessionId,
      meshId: 'fakemesh',
      fingerprint: fingerprint,
      listenAddress: '127.0.0.1:${request.listenPort}',
    );
    _sessions[sessionId] = fakeSession(
      sessionId: sessionId,
      displayName: request.displayName,
      role: 'inviter',
      inviteUri: inviteUri,
      fingerprint: fingerprint,
    );
    return Future.value(created);
  }

  @override
  Future<SessionSnapshot> acceptInvite({required AcceptInviteRequest request}) {
    final sessionId = 'fake-accept-${_sessions.length + 1}';
    final fingerprint = fakeFingerprint(sessionId);
    final snapshot = fakeSession(
      sessionId: sessionId,
      displayName: request.displayName,
      role: 'invitee',
      inviteUri: request.inviteUri,
      fingerprint: fingerprint,
    );
    _sessions[sessionId] = snapshot;
    return Future.value(snapshot);
  }

  @override
  Future<SendMessageResult> sendMessage({
    required String sessionId,
    required String body,
  }) {
    final existing = _sessions[sessionId];
    if (existing == null) {
      return Future.error(
        Exception('FakeGateway.sendMessage: unknown sessionId "$sessionId"'),
      );
    }
    final sentAtMs = BigInt.from(DateTime.now().millisecondsSinceEpoch);
    final messageId = 'msg-${existing.messages.length + 1}';
    _sessions[sessionId] = withMessage(existing, body, messageId, sentAtMs);
    return Future.value(cannedSendMessageResult(
      sessionId: sessionId,
      messageId: messageId,
      ciphertextBytes: BigInt.from(body.codeUnits.length),
    ));
  }

  @override
  Future<SendMessageResult> retryDmMessage({
    required String sessionId,
    required String messageId,
  }) =>
      Future.value(cannedSendMessageResult(
        sessionId: sessionId,
        messageId: messageId,
        ciphertextBytes: BigInt.zero,
      ));

  @override
  Future<SessionSnapshot> pollSession({required String sessionId}) {
    final snapshot = _sessions[sessionId];
    if (snapshot == null) {
      return Future.error(
        Exception('FakeGateway.pollSession: unknown sessionId "$sessionId"'),
      );
    }
    return Future.value(snapshot);
  }

  @override
  Future<SessionListSnapshot> listSessions() =>
      Future.value(SessionListSnapshot(sessions: _sessions.values.toList()));

  @override
  Future<CloseSessionResult> closeSession({required String sessionId}) {
    final removed = _sessions.remove(sessionId) != null;
    return Future.value(
      CloseSessionResult(sessionId: sessionId, closed: removed),
    );
  }

  // Attachment transfer control: no-op in the fake (no transfer machinery);
  // both methods complete with Future.value (no state change).
  @override
  Future<void> downloadAttachment({
    required String sessionId,
    required String attachmentId,
  }) =>
      Future.value();

  @override
  Future<void> cancelAttachment({
    required String sessionId,
    required String attachmentId,
  }) =>
      Future.value();

  // Channels/groups read seam: the fake has no real channel/group runtime,
  // so each method returns a canned minimal-but-valid snapshot from
  // fake_gateway_snapshots.dart.
  @override
  Future<ChannelSnapshot> pollChannel({required String name}) =>
      Future.value(cannedChannelSnapshot(name: name));

  @override
  Future<ChannelListSnapshot> listChannels() =>
      Future.value(const ChannelListSnapshot(channels: []));

  @override
  Future<GroupSnapshot> pollGroup({required String groupId}) =>
      Future.value(cannedGroupSnapshot(groupId: groupId));

  @override
  Future<GroupListSnapshot> listGroups() =>
      Future.value(const GroupListSnapshot(groups: []));

  @override
  Future<ChannelSnapshot> joinChannel({required JoinChannelRequest request}) =>
      Future.value(cannedChannelSnapshot(
          name: request.name, displayName: request.displayName));

  @override
  Future<ChannelSendResult> sendChannel(
          {required String name, required String body}) =>
      Future.value(cannedChannelSendResult(
        name: name,
        messageId: 'fake-channel-${_channelSendCount++}',
        bytes: BigInt.from(body.codeUnits.length),
      ));
  @override
  Future<ChannelSendResult> retryChannelMessage(
          {required String name, required String messageId}) =>
      Future.value(cannedChannelSendResult(
        name: name,
        messageId: 'fake-channel-${_channelSendCount++}',
        bytes: BigInt.zero,
      ));

  @override
  Future<ChannelLeaveResult> leaveChannel({required String name}) =>
      Future.value(ChannelLeaveResult(name: name, closed: true));

 @override
 Future<GroupSendResult> sendGroup(
         {required String groupId, required String body}) =>
     Future.value(cannedGroupSendResult(
       groupId: groupId,
       messageId: 'fake-group-${_groupSendCount++}',
       bytes: BigInt.from(body.codeUnits.length),
     ));

 @override
 Future<GroupSendResult> retryGroupMessage(
         {required String groupId, required String messageId}) =>
     Future.value(cannedGroupSendResult(
       groupId: groupId,
       messageId: 'fake-group-${_groupSendCount++}',
       bytes: BigInt.zero,
     ));

  @override
  Future<GroupLeaveResult> closeGroup({required String groupId}) =>
      Future.value(GroupLeaveResult(groupId: groupId, closed: true));

  // createGroup: canned GroupCreated with a deterministic invite URI derived
  // from the label (GroupCreateScreen InviteResult branch has something to copy).
  @override
  Future<GroupCreated> createGroup({required CreateGroupRequest request}) {
    final label = request.label ?? '';
    final groupId = 'fake-group-${label.isEmpty ? 'untitled' : label}';
    return Future.value(GroupCreated(
      groupId: groupId,
      meshId: '',
      inviteUri: 'mosh://group/$groupId',
      fingerprint: '',
      label: request.label,
    ));
  }

  // joinGroup: canned snapshot; groupId parsed from the invite URI `group=`
  // param (same param detectInvite reads) so navigation is deterministic.
  @override
  Future<GroupSnapshot> joinGroup({required JoinGroupRequest request}) {
    final groupId = groupIdFromInviteUri(request.inviteUri);
    return Future.value(cannedGroupSnapshot(
      groupId: groupId,
      displayName: request.displayName,
      memberCount: BigInt.one,
      inviteUri: request.inviteUri,
      orgPubkey: request.orgPubkey,
    ));
  }

  // DM-offer dismiss seams: no-ops (no offer store); the screen refreshes its
  // snapshot after the call.
  @override
  Future<void> dismissChannelDmOffer(
          {required String name, required String offerId}) =>
      Future.value();
  @override
  Future<void> dismissGroupDmOffer(
          {required String groupId, required String offerId}) =>
      Future.value();

  // Peer-DM-offer SEND seams (channel/group): no-ops (no real peer to deliver to; matches the dismiss pair above). The real Rust runtime delivers over Moss transport (slice-3 wiring pending; see RealBridgeGateway).
  @override
  Future<void> sendChannelDmOffer({required String channelName, required String peerFingerprint, required String inviteUri}) => Future.value();
  @override
  Future<void> sendGroupDmOffer({required String groupId, required String peerFingerprint, required String inviteUri}) => Future.value();

  // Channel/group attachment transfer seams (slice-3): the fake has no real
  // transfer runtime, so all four are no-ops that complete synchronously.
  @override
  Future<void> downloadChannelAttachment(
          {required String name, required String attachmentId}) =>
      Future.value();
  @override
  Future<void> cancelChannelAttachment(
          {required String name, required String attachmentId}) =>
      Future.value();
  @override
  Future<void> downloadGroupAttachment(
          {required String groupId, required String attachmentId}) =>
      Future.value();
  @override
  Future<void> cancelGroupAttachment(
          {required String groupId, required String attachmentId}) =>
      Future.value();

  // Channel/group attachment SEND seams (slice-3): canned AttachmentSendResult
  // with a deterministic attachmentId derived from the file name.
  @override
  Future<AttachmentSendResult> sendChannelAttachment({
    required String name,
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  }) =>
      Future.value(cannedAttachmentSendResult(
        sessionPrefix: 'fake-channel',
        id: name,
        fileName: fileName,
        dataBase64: dataBase64,
      ));
  @override
  Future<AttachmentSendResult> sendPrivateAttachment({
    required String sessionId,
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  }) =>
      Future.value(cannedAttachmentSendResult(
        sessionPrefix: 'fake-dm',
        id: sessionId,
        fileName: fileName,
        dataBase64: dataBase64,
      ));
  @override
  Future<AttachmentSendResult> sendGroupAttachment({
    required String groupId,
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  }) =>
      Future.value(cannedAttachmentSendResult(
        sessionPrefix: 'fake-group',
        id: groupId,
        fileName: fileName,
        dataBase64: dataBase64,
      ));

  // joinOrg: canned OrgSnapshot (empty-but-valid). React does NOT navigate to
  // a dedicated screen -- the caller leaves setup + the org appears on refresh.
  @override
  Future<OrgSnapshot> joinOrg({required JoinOrgRequest request}) =>
      Future.value(cannedOrgSnapshot(
          orgPubkey: orgPubkeyFromBundleUri(request.bundleUri)));

  // Org surface (the rest): canned minimal-but-valid results (no real org
  // runtime). acceptOrgDmOffer inserts into the session map (mirrors
  // acceptInvite); the rest mutate no state.
  @override
  Future<void> leaveOrg({required String orgPubkey}) => Future.value();

  @override
  Future<List<OrgSnapshot>> listOrgs() => Future.value(const []);

  @override
  Future<OrgSnapshot> pollOrg({required String orgPubkey}) =>
      Future.value(cannedOrgSnapshot(orgPubkey: orgPubkey));

  @override
  Future<InviteCreated> sendOrgDmOffer({
    required String orgPubkey,
    required String targetPeerId,
    required String displayName,
    required int listenPort,
    String? staticPeer,
  }) =>
      Future.value(InviteCreated(
        inviteUri: 'mosh://invite?session=fake-org-dm&fp=00#fp=00',
        sessionId: 'fake-org-dm-${DateTime.now().millisecondsSinceEpoch}',
        meshId: '',
        fingerprint: '00',
        listenAddress: '',
      ));

  @override
  Future<SessionSnapshot> acceptOrgDmOffer({
    required String orgPubkey,
    required String offerId,
    required String displayName,
    required int listenPort,
    String? staticPeer,
  }) {
    final sessionId = 'fake-org-accept-${_sessions.length + 1}';
    final snapshot = fakeSession(
      sessionId: sessionId,
      displayName: displayName,
      role: 'invitee',
      inviteUri: 'mosh://invite?session=$sessionId&fp=00#fp=00',
      fingerprint: '00',
    );
    _sessions[sessionId] = snapshot;
    return Future.value(snapshot);
  }

  @override
  Future<void> dismissOrgDmOffer(
          {required String orgPubkey, required String offerId}) =>
      Future.value();

  @override
  Future<GroupCreated> createOrgGroup({
    required String orgPubkey,
    String? label,
    required List<String> memberPeerIds,
    required String displayName,
    required int listenPort,
    String? staticPeer,
  }) =>
      Future.value(GroupCreated(
        groupId: 'fake-org-group-${DateTime.now().millisecondsSinceEpoch}',
        meshId: '',
        inviteUri: 'mosh://group?session=fake-org-group&fp=00#fp=00',
        fingerprint: '00',
        label: label,
      ));

  @override
  Future<GroupSnapshot> acceptOrgGroupOffer({
    required String orgPubkey,
    required String offerId,
    required String displayName,
    required int listenPort,
    String? staticPeer,
  }) =>
      Future.value(cannedGroupSnapshot(
        groupId: 'fake-org-group-accept',
        displayName: displayName,
        deviceFingerprint: '00',
        creatorFingerprint: '00',
        memberCount: BigInt.one,
        inviteUri: 'mosh://group?session=fake-org-group-accept&fp=00#fp=00',
        orgPubkey: orgPubkey,
      ));

  @override
  Future<void> dismissOrgGroupOffer(
          {required String orgPubkey, required String offerId}) =>
      Future.value();

  @override
  Future<void> orgGroupInviteMembers({
    required String orgPubkey,
    required String groupId,
    required List<String> memberPeerIds,
  }) =>
      Future.value();

  // Network + VPN surface. Canned minimal-but-valid results (no NICs /
  // no VPN / null bind); the consent pair round-trips an in-memory field
  // so a VPN-consent screen test can set + read without the filesystem.
  VpnBypassConsent? _vpnBypassConsent;

  @override
  Future<List<NetworkInterfaceInfo>> listInterfaces() => Future.value(const []);

  @override
  Future<VpnDetection> detectVpn() => Future.value(cannedVpnDetection());

  @override
  Future<String?> getBindInterface() => Future.value(null);

  @override
  Future<VpnBypassConsent?> getVpnBypassConsent() =>
      Future.value(_vpnBypassConsent);

  @override
  Future<void> setVpnBypassConsent({String? interfaceName}) {
    final name = interfaceName;
    if (name == null || name.isEmpty) {
      _vpnBypassConsent = null;
      return Future.value();
    }
    _vpnBypassConsent = VpnBypassConsent(
      interface_: name,
      index: 0,
    );
    return Future.value();
  }
  // Voice-call surface (DM-only). The fake has no call runtime, so the control
  // methods are no-ops; callStart returns a canned CallStarted (from
  // fake_gateway_snapshots) so a call-UI test can drive the modal.
  @override
  Future<CallStarted> callStart({required String sessionId}) =>
      Future.value(cannedCallStarted(sessionId));

  @override
  Future<void> callAccept({required String sessionId, required String callId}) =>
      Future.value();
  @override
  Future<void> callDecline({
    required String sessionId,
    required String callId,
    required String reason,
  }) =>
      Future.value();
  @override
  Future<void> callEnd({
    required String sessionId,
    required String callId,
    required String reason,
  }) =>
      Future.value();
  @override
  Future<void> callSendFrame({
    required String sessionId,
    required String callId,
    required Uint8List frame,
  }) =>
      Future.value();

  @override
  Future<List<Uint8List>> callDrainFrames({
    required String sessionId,
    required String callId,
  }) =>
      Future.value(const <Uint8List>[]);
}
