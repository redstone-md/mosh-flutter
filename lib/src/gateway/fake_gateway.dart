// In-Dart test double for the slice-one Gateway surface (ADR 0013).
// Lets widget tests run without the Rust runtime: implements the Gateway
// methods with canned data + an in-memory session map. Canned snapshots
// live in fake_gateway_snapshots.dart (extracted to keep this under 500 lines).

import 'package:mosh/src/gateway/fake_gateway_snapshots.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/rust/api/diagnostics.dart'
    show AppDiagnostics, NativeRuntimeStatus;
import 'package:mosh/src/rust/api/vpn.dart' show VpnDetection;
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/network_inventory.dart' show NetworkInterfaceInfo;
import 'package:mosh/src/rust/org_runtime.dart';
import 'package:mosh/src/rust/attachment_runtime.dart';
import 'package:mosh/src/rust/outbound_delivery.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/vpn_consent.dart' show VpnBypassConsent;

/// Slice-one fake runtime: canned diagnostics + an in-memory session map.
///
/// Stateful by design (ADR 0013): each createInvite/acceptInvite inserts a
/// SessionSnapshot; sendMessage/pollSession/closeSession mutate or read it.
/// All canned snapshots come from fake_gateway_snapshots.dart (pure helpers).
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
    return Future.value(SendMessageResult(
      sessionId: sessionId,
      state: 'connecting',
      ciphertextBytes: BigInt.from(body.codeUnits.length),
      messageId: messageId,
      sentAtMs: sentAtMs,
      deliveryStatus: MessageDeliveryStatus.sent,
      deliveryError: null,
    ));
  }

  @override
  Future<SendMessageResult> retryDmMessage({
    required String sessionId,
    required String messageId,
  }) =>
      Future.value(SendMessageResult(
        sessionId: sessionId,
        state: 'connecting',
        ciphertextBytes: BigInt.zero,
        messageId: messageId,
        sentAtMs: BigInt.from(DateTime.now().millisecondsSinceEpoch),
        deliveryStatus: MessageDeliveryStatus.sent,
        deliveryError: null,
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

  // Attachment transfer control is a no-op in the fake: the real runtime
  // drives progress through pump_attachment_requests + relay jobs, and this
  // fake has no transfer machinery, so pollSession keeps returning its canned
  // snapshot. Both methods complete with Future.value (no state change).
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
      Future.value(ChannelSendResult(
        name: name,
        bytes: BigInt.from(body.codeUnits.length),
        messageId: 'fake-channel-${_channelSendCount++}',
        sentAtMs: BigInt.from(DateTime.now().millisecondsSinceEpoch),
        deliveryStatus: MessageDeliveryStatus.sent,
        deliveryError: null,
      ));

  @override
  Future<ChannelSendResult> retryChannelMessage(
          {required String name, required String messageId}) =>
      Future.value(ChannelSendResult(
        name: name,
        bytes: BigInt.zero,
        messageId: 'fake-channel-${_channelSendCount++}',
        sentAtMs: BigInt.from(DateTime.now().millisecondsSinceEpoch),
        deliveryStatus: MessageDeliveryStatus.sent,
        deliveryError: null,
      ));

  @override
  Future<ChannelLeaveResult> leaveChannel({required String name}) =>
      Future.value(ChannelLeaveResult(name: name, closed: true));

  @override
  Future<GroupSendResult> sendGroup(
          {required String groupId, required String body}) =>
      Future.value(GroupSendResult(
        groupId: groupId,
        bytes: BigInt.from(body.codeUnits.length),
        messageId: 'fake-group-${_groupSendCount++}',
        sentAtMs: BigInt.from(DateTime.now().millisecondsSinceEpoch),
        deliveryStatus: MessageDeliveryStatus.sent,
        deliveryError: null,
      ));

  @override
  Future<GroupSendResult> retryGroupMessage(
          {required String groupId, required String messageId}) =>
      Future.value(GroupSendResult(
        groupId: groupId,
        bytes: BigInt.zero,
        messageId: 'fake-group-${_groupSendCount++}',
        sentAtMs: BigInt.from(DateTime.now().millisecondsSinceEpoch),
        deliveryStatus: MessageDeliveryStatus.sent,
        deliveryError: null,
      ));

  @override
  Future<GroupLeaveResult> closeGroup({required String groupId}) =>
      Future.value(GroupLeaveResult(groupId: groupId, closed: true));

  // The `createGroup` seam (slice-3) mirrors the React happy path: a canned
  // GroupCreated with a deterministic invite URI derived from the requested
  // label so the GroupCreateScreen InviteResult branch has something to
  // render + copy (the real impl returns the runtime-minted invite URI).
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

  // The `joinGroup` seam (slice-3) mirrors pollGroup's canned snapshot shape;
  // the groupId is parsed from the invite URI's `group=` query param (the
  // same param `detectInvite` reads) so the screen navigates to
  // `groupFor(groupId)` with a deterministic value the test can assert.
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

  // DM-offer dismiss seams (slice-3): the fake has no real offer store, so
  // both are no-ops that complete synchronously (the screen refreshes its
  // channel/group snapshot after the call, which still has the offer until
  // a real runtime is wired). Mirrors the Future<void> shape of the real impls.
  @override
  Future<void> dismissChannelDmOffer(
          {required String name, required String offerId}) =>
      Future.value();
  @override
  Future<void> dismissGroupDmOffer(
          {required String groupId, required String offerId}) =>
      Future.value();

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
      Future.value(AttachmentSendResult(
        sessionId: 'fake-channel:$name',
        attachmentId: 'fake-channel-attachment:${fileName.hashCode}',
        contentHash: 'fake-hash:${dataBase64.hashCode}',
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
      Future.value(AttachmentSendResult(
        sessionId: 'fake-dm:$sessionId',
        attachmentId: 'fake-dm-attachment:${fileName.hashCode}',
        contentHash: 'fake-hash:${dataBase64.hashCode}',
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
      Future.value(AttachmentSendResult(
        sessionId: 'fake-group:$groupId',
        attachmentId: 'fake-group-attachment:${fileName.hashCode}',
        contentHash: 'fake-hash:${dataBase64.hashCode}',
      ));

  // The `joinOrg` seam (slice-3) mirrors the React happy path: a canned
  // OrgSnapshot with empty-but-valid members/offers/links. React's joinOrg
  // does NOT navigate to a dedicated screen -- it just leaves setup +
  // refreshes the orgs list -- so the caller navigates to the sessions list,
  // where the org appears after refresh.
  @override
  Future<OrgSnapshot> joinOrg({required JoinOrgRequest request}) =>
      Future.value(cannedOrgSnapshot(
          orgPubkey: orgPubkeyFromBundleUri(request.bundleUri)));

  // Org surface (the rest). The fake has no real org runtime, so each
  // method returns a canned minimal-but-valid result: read methods
  // (listOrgs/pollOrg) return empty/canned snapshots; write methods
  // (leaveOrg/dismiss*) return void; the cross-runtime offer methods return
  // canned InviteCreated/SessionSnapshot/GroupCreated/GroupSnapshot. No
  // state is mutated except acceptOrgDmOffer (inserts the accepted session
  // into the in-memory session map, mirroring acceptInvite).
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
}
