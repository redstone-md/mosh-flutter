// The test double for the bridge facade (ADR 0025).
//
// The facade's 34 methods mirror one generated bridge call each and hide no
// decision, but screens still need canned data and scripted failures to test
// the flows around them -- so the facade gets its own double with the same
// contract as `ScriptableGateway`: record, seed, script. The two doubles are
// two views over one runtime: hand this one the gateway's
// [ScriptedConversations] when a test wires both, so an accepted invite
// inserts the session the pushed screen then polls through the gateway.
//
// Session state is real in-memory state: createInvite and acceptInvite
// insert a session. Anything not seeded falls back to the canned snapshots
// in gateway_snapshots.dart.
//
// Size exception: one flat scripted method per facade call, over the AGENTS.md
// file/type budgets; the reason, scope and removal plan are documented in
// ADR 0025.

import 'dart:typed_data' show Uint8List;

import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/rust/api/diagnostics.dart'
    show AppDiagnostics, MossLibraryInfo, NativeRuntimeStatus;
import 'package:mosh/src/rust/api/vpn.dart' show VpnDetection;
import 'package:mosh/src/rust/channel_runtime.dart'
    show ChannelListSnapshot, ChannelSnapshot, JoinChannelRequest;
import 'package:mosh/src/rust/network_inventory.dart' show NetworkInterfaceInfo;
import 'package:mosh/src/rust/org_runtime.dart'
    show JoinOrgRequest, OrgSnapshot;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show
        AcceptInviteRequest,
        CallStarted,
        InviteCreated,
        SessionListSnapshot,
        SessionSnapshot,
        StartSessionRequest;
import 'package:mosh/src/rust/private_group_runtime.dart'
    show
        CreateGroupRequest,
        GroupCreated,
        GroupListSnapshot,
        GroupSnapshot,
        JoinGroupRequest;
import 'package:mosh/src/rust/vpn_consent.dart' show VpnBypassConsent;

import 'gateway_snapshots.dart';
import 'scripted_calls.dart';
import 'scripted_conversations.dart';

/// Every method on [BridgeFacade]. Tests name a method through this enum, so
/// a typo is a compile error instead of a call that is never scripted.
enum BridgeMethod {
  appDiagnostics,
  mossLibraryInfo,
  nativeRuntimeStatus,
  createInvite,
  acceptInvite,
  listSessions,
  readReceiptsEnabled,
  setReadReceiptsEnabled,
  listChannels,
  listGroups,
  joinChannel,
  createGroup,
  joinGroup,
  sendChannelDmOffer,
  sendGroupDmOffer,
  joinOrg,
  leaveOrg,
  listOrgs,
  pollOrg,
  sendOrgDmOffer,
  acceptOrgDmOffer,
  dismissOrgDmOffer,
  createOrgGroup,
  acceptOrgGroupOffer,
  dismissOrgGroupOffer,
  orgGroupInviteMembers,
  listInterfaces,
  detectVpn,
  getBindInterface,
  getVpnBypassConsent,
  setVpnBypassConsent,
  callStart,
  callAccept,
  callDecline,
  callEnd,
  callSendFrame,
  callDrainFrames,
}

/// One recorded call to the bridge facade.
typedef BridgeCall = ScriptedCall<BridgeMethod>;

/// See the file header. Construct it, seed it, script it, assert on [calls].
class ScriptableBridge
    with ScriptedEngine<BridgeMethod>
    implements BridgeFacade {
  ScriptableBridge({ScriptedConversations? conversations})
      : conversations = conversations ?? ScriptedConversations();

  /// The seeded conversations `listSessions`/`listChannels`/`listGroups`
  /// serve and the invite paths insert into. Share the gateway double's
  /// instance so both surfaces see one runtime's state.
  final ScriptedConversations conversations;

  final Map<String, OrgSnapshot> _orgs = {};

  InviteCreated? _invite;
  NativeRuntimeStatus? _nativeStatus;
  MossLibraryInfo? _mossLibraryInfo;
  List<NetworkInterfaceInfo> _interfaces = const [];
  VpnDetection? _vpnDetection;
  String? _bindInterface;
  VpnBypassConsent? _vpnConsent;
  List<Uint8List> _callFrames = const [];
  bool _readReceiptsEnabled = false;

  // ----------------------------------------------------------------- seeding

  /// Seed the conversations the list reads serve. Convenience over the
  /// shared state; a gateway double seeding the same instance sees the
  /// same data in its polls.
  void seedSessions(Iterable<SessionSnapshot> seeded) =>
      conversations.seedSessions(seeded);

  void seedChannels(Iterable<ChannelSnapshot> seeded) =>
      conversations.seedChannels(seeded);

  void seedGroups(Iterable<GroupSnapshot> seeded) =>
      conversations.seedGroups(seeded);

  /// Seed the orgs `listOrgs` and `pollOrg` return.
  void seedOrgs(Iterable<OrgSnapshot> orgs) {
    _orgs
      ..clear()
      ..addEntries(orgs.map((o) => MapEntry(o.orgPubkey, o)));
  }

  /// Seed what `createInvite` returns (invite URI, session id, fingerprint).
  void seedInvite(InviteCreated invite) => _invite = invite;

  /// Seed what `nativeRuntimeStatus` returns.
  void seedNativeRuntimeStatus(NativeRuntimeStatus status) =>
      _nativeStatus = status;

  /// Seed what `mossLibraryInfo` returns.
  void seedMossLibraryInfo(MossLibraryInfo info) => _mossLibraryInfo = info;

  /// Seed the NICs `listInterfaces` returns.
  void seedInterfaces(List<NetworkInterfaceInfo> interfaces) =>
      _interfaces = interfaces;

  /// Seed what `detectVpn` returns.
  void seedVpnDetection(VpnDetection detection) => _vpnDetection = detection;

  /// Seed what `getBindInterface` returns.
  void seedBindInterface(String? name) => _bindInterface = name;

  /// Seed what `getVpnBypassConsent` returns. `setVpnBypassConsent`
  /// overwrites it, so a test can set then read without touching the
  /// filesystem.
  void seedVpnConsent(VpnBypassConsent? consent) => _vpnConsent = consent;

  /// Seed the frames `callDrainFrames` returns.
  void seedCallFrames(List<Uint8List> frames) => _callFrames = frames;

  /// Seed the read-receipts answer. `setReadReceiptsEnabled` overwrites it,
  /// so a test can set then read without touching the filesystem.
  void seedReadReceiptsEnabled(bool enabled) => _readReceiptsEnabled = enabled;

  // -------------------------------------------------------------- diagnostics

  @override
  Future<AppDiagnostics> appDiagnostics() =>
      runScripted(BridgeMethod.appDiagnostics, const {}, cannedAppDiagnostics);

  @override
  Future<NativeRuntimeStatus> nativeRuntimeStatus() => runScripted(
      BridgeMethod.nativeRuntimeStatus,
      const {},
      () => _nativeStatus ?? cannedNativeRuntimeStatus());

  @override
  Future<MossLibraryInfo> mossLibraryInfo({String? peerMossId}) => runScripted(
      BridgeMethod.mossLibraryInfo,
      {'peerMossId': peerMossId},
      () => _mossLibraryInfo ?? cannedMossLibraryInfo());

  // ------------------------------------------------------------ invite + DM

  @override
  Future<InviteCreated> createInvite({required StartSessionRequest request}) =>
      runScripted(BridgeMethod.createInvite, {'request': request}, () {
        final seeded = _invite;
        final sessionId =
            seeded?.sessionId ?? 'fake-${conversations.sessions.length + 1}';
        final fingerprint = seeded?.fingerprint ?? fakeFingerprint(sessionId);
        final inviteUri = seeded?.inviteUri ??
            'mosh://invite?mesh=fakemesh&session=$sessionId#fp=$fingerprint';
        conversations.sessions[sessionId] = fakeSession(
          sessionId: sessionId,
          displayName: request.displayName,
          role: 'inviter',
          inviteUri: inviteUri,
          fingerprint: fingerprint,
        );
        return seeded ??
            InviteCreated(
              inviteUri: inviteUri,
              sessionId: sessionId,
              meshId: 'fakemesh',
              fingerprint: fingerprint,
              listenAddress: '127.0.0.1:${request.listenPort}',
            );
      });

  @override
  Future<SessionSnapshot> acceptInvite(
          {required AcceptInviteRequest request}) =>
      runScripted(BridgeMethod.acceptInvite, {'request': request}, () {
        final sessionId = 'fake-accept-${conversations.sessions.length + 1}';
        final snapshot = fakeSession(
          sessionId: sessionId,
          displayName: request.displayName,
          role: 'invitee',
          inviteUri: request.inviteUri,
          fingerprint: fakeFingerprint(sessionId),
        );
        conversations.sessions[sessionId] = snapshot;
        return snapshot;
      });

  @override
  Future<SessionListSnapshot> listSessions() => runScripted(
        BridgeMethod.listSessions,
        const {},
        () => SessionListSnapshot(
            sessions: conversations.sessions.values.toList()),
      );

  @override
  Future<bool> readReceiptsEnabled() => runScripted(
      BridgeMethod.readReceiptsEnabled, const {}, () => _readReceiptsEnabled);

  @override
  Future<void> setReadReceiptsEnabled({required bool enabled}) =>
      runScripted(BridgeMethod.setReadReceiptsEnabled, {'enabled': enabled},
          () {
        _readReceiptsEnabled = enabled;
      });

  // -------------------------------------------------------- channels/groups

  @override
  Future<ChannelListSnapshot> listChannels() => runScripted(
        BridgeMethod.listChannels,
        const {},
        () => ChannelListSnapshot(
            channels: conversations.channels.values.toList()),
      );

  @override
  Future<GroupListSnapshot> listGroups() => runScripted(
        BridgeMethod.listGroups,
        const {},
        () => GroupListSnapshot(groups: conversations.groups.values.toList()),
      );

  @override
  Future<ChannelSnapshot> joinChannel({required JoinChannelRequest request}) =>
      runScripted(
          BridgeMethod.joinChannel,
          {'request': request},
          () =>
              conversations.channels[request.name] ??
              cannedChannelSnapshot(
                  name: request.name, displayName: request.displayName));

  @override
  Future<GroupCreated> createGroup({required CreateGroupRequest request}) =>
      runScripted(BridgeMethod.createGroup, {'request': request}, () {
        final label = request.label ?? '';
        final groupId = 'fake-group-${label.isEmpty ? 'untitled' : label}';
        return GroupCreated(
          groupId: groupId,
          meshId: '',
          inviteUri: 'mosh://group/$groupId',
          fingerprint: '',
          label: request.label,
        );
      });

  @override
  Future<GroupSnapshot> joinGroup({required JoinGroupRequest request}) =>
      runScripted(BridgeMethod.joinGroup, {'request': request}, () {
        final groupId = groupIdFromInviteUri(request.inviteUri);
        return conversations.groups[groupId] ??
            cannedGroupSnapshot(
              groupId: groupId,
              displayName: request.displayName,
              memberCount: BigInt.one,
              inviteUri: request.inviteUri,
              orgPubkey: request.orgPubkey,
            );
      });

  // The outbound DM-offer sends no-op: there is no real peer to deliver to,
  // matching the dismiss pair on the seam. Both must complete normally so
  // the popover UI resolves.
  @override
  Future<void> sendChannelDmOffer({
    required String channelName,
    required String peerFingerprint,
    required String inviteUri,
  }) =>
      runScripted(
          BridgeMethod.sendChannelDmOffer,
          {
            'channelName': channelName,
            'peerFingerprint': peerFingerprint,
            'inviteUri': inviteUri,
          },
          () {});

  @override
  Future<void> sendGroupDmOffer({
    required String groupId,
    required String peerFingerprint,
    required String inviteUri,
  }) =>
      runScripted(
          BridgeMethod.sendGroupDmOffer,
          {
            'groupId': groupId,
            'peerFingerprint': peerFingerprint,
            'inviteUri': inviteUri,
          },
          () {});

  // ----------------------------------------------------------------- the org

  @override
  Future<OrgSnapshot> joinOrg({required JoinOrgRequest request}) => runScripted(
        BridgeMethod.joinOrg,
        {'request': request},
        () => cannedOrgSnapshot(
          orgPubkey: orgPubkeyFromBundleUri(request.bundleUri),
        ),
      );

  @override
  Future<void> leaveOrg({required String orgPubkey}) =>
      runScripted(BridgeMethod.leaveOrg, {'orgPubkey': orgPubkey}, () {});

  @override
  Future<List<OrgSnapshot>> listOrgs() =>
      runScripted(BridgeMethod.listOrgs, const {}, () => _orgs.values.toList());

  @override
  Future<OrgSnapshot> pollOrg({required String orgPubkey}) => runScripted(
      BridgeMethod.pollOrg,
      {'orgPubkey': orgPubkey},
      () => _orgs[orgPubkey] ?? cannedOrgSnapshot(orgPubkey: orgPubkey));

  @override
  Future<InviteCreated> sendOrgDmOffer({
    required String orgPubkey,
    required String targetPeerId,
    required String displayName,
    required int listenPort,
    String? staticPeer,
  }) =>
      runScripted(
          BridgeMethod.sendOrgDmOffer,
          {
            'orgPubkey': orgPubkey,
            'targetPeerId': targetPeerId,
            'displayName': displayName,
            'listenPort': listenPort,
            'staticPeer': staticPeer,
          },
          () => InviteCreated(
                inviteUri: 'mosh://invite?session=fake-org-dm&fp=00#fp=00',
                sessionId: 'fake-org-dm-${conversations.sessions.length + 1}',
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
  }) =>
      runScripted(BridgeMethod.acceptOrgDmOffer, {
        'orgPubkey': orgPubkey,
        'offerId': offerId,
        'displayName': displayName,
        'listenPort': listenPort,
        'staticPeer': staticPeer,
      }, () {
        final sessionId =
            'fake-org-accept-${conversations.sessions.length + 1}';
        final snapshot = fakeSession(
          sessionId: sessionId,
          displayName: displayName,
          role: 'invitee',
          inviteUri: 'mosh://invite?session=$sessionId&fp=00#fp=00',
          fingerprint: '00',
        );
        conversations.sessions[sessionId] = snapshot;
        return snapshot;
      });

  @override
  Future<void> dismissOrgDmOffer({
    required String orgPubkey,
    required String offerId,
  }) =>
      runScripted(BridgeMethod.dismissOrgDmOffer,
          {'orgPubkey': orgPubkey, 'offerId': offerId}, () {});

  @override
  Future<GroupCreated> createOrgGroup({
    required String orgPubkey,
    String? label,
    required List<String> memberPeerIds,
    required String displayName,
    required int listenPort,
    String? staticPeer,
  }) =>
      runScripted(
          BridgeMethod.createOrgGroup,
          {
            'orgPubkey': orgPubkey,
            'label': label,
            'memberPeerIds': memberPeerIds,
            'displayName': displayName,
            'listenPort': listenPort,
            'staticPeer': staticPeer,
          },
          () => GroupCreated(
                groupId: 'fake-org-group-${conversations.groups.length + 1}',
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
      runScripted(
          BridgeMethod.acceptOrgGroupOffer,
          {
            'orgPubkey': orgPubkey,
            'offerId': offerId,
            'displayName': displayName,
            'listenPort': listenPort,
            'staticPeer': staticPeer,
          },
          () => cannedGroupSnapshot(
                groupId: 'fake-org-group-accept',
                displayName: displayName,
                deviceFingerprint: '00',
                creatorFingerprint: '00',
                memberCount: BigInt.one,
                inviteUri:
                    'mosh://group?session=fake-org-group-accept&fp=00#fp=00',
                orgPubkey: orgPubkey,
              ));

  @override
  Future<void> dismissOrgGroupOffer({
    required String orgPubkey,
    required String offerId,
  }) =>
      runScripted(BridgeMethod.dismissOrgGroupOffer,
          {'orgPubkey': orgPubkey, 'offerId': offerId}, () {});

  @override
  Future<void> orgGroupInviteMembers({
    required String orgPubkey,
    required String groupId,
    required List<String> memberPeerIds,
  }) =>
      runScripted(
          BridgeMethod.orgGroupInviteMembers,
          {
            'orgPubkey': orgPubkey,
            'groupId': groupId,
            'memberPeerIds': memberPeerIds,
          },
          () {});

  // -------------------------------------------------------- network + VPN

  @override
  Future<List<NetworkInterfaceInfo>> listInterfaces() =>
      runScripted(BridgeMethod.listInterfaces, const {}, () => _interfaces);

  @override
  Future<VpnDetection> detectVpn() => runScripted(BridgeMethod.detectVpn,
      const {}, () => _vpnDetection ?? cannedVpnDetection());

  @override
  Future<String?> getBindInterface() => runScripted(
      BridgeMethod.getBindInterface, const {}, () => _bindInterface);

  @override
  Future<VpnBypassConsent?> getVpnBypassConsent() => runScripted(
      BridgeMethod.getVpnBypassConsent, const {}, () => _vpnConsent);

  @override
  Future<void> setVpnBypassConsent({String? interfaceName}) => runScripted(
          BridgeMethod.setVpnBypassConsent, {'interfaceName': interfaceName},
          () {
        final name = interfaceName;
        _vpnConsent = (name == null || name.isEmpty)
            ? null
            : VpnBypassConsent(interface_: name, index: 0);
      });

  // --------------------------------------------------------------- the calls

  @override
  Future<CallStarted> callStart({required String sessionId}) => runScripted(
      BridgeMethod.callStart,
      {'sessionId': sessionId},
      () => cannedCallStarted(sessionId));

  @override
  Future<void> callAccept({
    required String sessionId,
    required String callId,
  }) =>
      runScripted(BridgeMethod.callAccept,
          {'sessionId': sessionId, 'callId': callId}, () {});

  @override
  Future<void> callDecline({
    required String sessionId,
    required String callId,
    required String reason,
  }) =>
      runScripted(BridgeMethod.callDecline,
          {'sessionId': sessionId, 'callId': callId, 'reason': reason}, () {});

  @override
  Future<void> callEnd({
    required String sessionId,
    required String callId,
    required String reason,
  }) =>
      runScripted(BridgeMethod.callEnd,
          {'sessionId': sessionId, 'callId': callId, 'reason': reason}, () {});

  @override
  Future<void> callSendFrame({
    required String sessionId,
    required String callId,
    required Uint8List frame,
  }) =>
      runScripted(BridgeMethod.callSendFrame,
          {'sessionId': sessionId, 'callId': callId, 'frame': frame}, () {});

  @override
  Future<List<Uint8List>> callDrainFrames({
    required String sessionId,
    required String callId,
  }) =>
      runScripted(BridgeMethod.callDrainFrames,
          {'sessionId': sessionId, 'callId': callId}, () => _callFrames);
}
