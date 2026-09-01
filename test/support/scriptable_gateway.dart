// The one Gateway test double for the whole suite.
//
// Tests configure it; they never subclass it. Three things it does:
//
//   * records every call, so a test can assert what the UI asked for
//     (`gateway.callsTo(...)`, `countOf`, `lastCall`);
//   * seeds data, so a screen renders the sessions/channels/groups a test
//     wants (`seedSessions`, `seedChannel`, ...);
//   * scripts a call, so a test can make it fail (`failNext`, `failAlways`)
//     or hold it open to observe the pending state (`hold` / `release`).
//
// The file is long because the Gateway interface is wide: one flat method
// per Gateway method, no nesting (ADR 0013, "Size exception").
//
// Anything not seeded falls back to the canned snapshots in
// gateway_snapshots.dart. Session state is real in-memory state: createInvite
// and acceptInvite insert a session, a DM send appends a message, and
// leave removes it.

import 'dart:async';
import 'dart:typed_data' show Uint8List;

import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/rust/api/diagnostics.dart'
    show AppDiagnostics, NativeRuntimeStatus;
import 'package:mosh/src/rust/api/vpn.dart' show VpnDetection;
import 'package:mosh/src/rust/attachment_runtime.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/network_inventory.dart' show NetworkInterfaceInfo;
import 'package:mosh/src/rust/org_runtime.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/vpn_consent.dart' show VpnBypassConsent;

import 'gateway_snapshots.dart';

/// Every method on [Gateway]. Tests name a method through this enum, so a
/// typo is a compile error instead of a call that is never scripted.
enum GatewayMethod {
  appDiagnostics,
  nativeRuntimeStatus,
  createInvite,
  acceptInvite,
  listSessions,
  poll,
  send,
  retry,
  sendAttachment,
  downloadAttachment,
  cancelAttachment,
  dismissDmOffer,
  leave,
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

/// One recorded call: which method, and the named arguments it got.
class GatewayCall {
  GatewayCall(this.method, this.args);

  final GatewayMethod method;
  final Map<String, Object?> args;

  /// Read one argument. Throws if the argument is not there or has another
  /// type, so a renamed or retyped argument fails the test loudly instead of
  /// reading as null.
  T arg<T>(String name) {
    if (!args.containsKey(name)) {
      throw ArgumentError('${method.name} has no argument named "$name"');
    }
    return args[name] as T;
  }

  /// The conversation a call was for. Only the conversation methods record
  /// it -- reading it on any other call throws.
  AnyConversationTarget get target => arg<AnyConversationTarget>('target');

  @override
  String toString() => '${method.name}($args)';
}

/// A scripted failure: throw [error] for the next [remaining] calls
/// (`null` remaining means every call).
class _Failure {
  _Failure(this.error, this.remaining);

  final Object error;
  int? remaining;

  bool consume() {
    final left = remaining;
    if (left == null) return true;
    if (left <= 0) return false;
    remaining = left - 1;
    return true;
  }
}

/// See the file header. Construct it, seed it, script it, assert on [calls].
class ScriptableGateway implements Gateway, ConversationSnapshotReader {
  /// Every call the code under test made, in order.
  final List<GatewayCall> calls = [];

  final Map<GatewayMethod, _Failure> _failures = {};
  final Map<GatewayMethod, Completer<void>> _held = {};

  final Map<String, SessionSnapshot> _sessions = {};
  final Map<String, ChannelSnapshot> _channels = {};
  final Map<String, GroupSnapshot> _groups = {};
  final Map<String, OrgSnapshot> _orgs = {};

  InviteCreated? _invite;
  NativeRuntimeStatus? _nativeStatus;
  List<NetworkInterfaceInfo> _interfaces = const [];
  VpnDetection? _vpnDetection;
  String? _bindInterface;
  VpnBypassConsent? _vpnConsent;
  List<Uint8List> _callFrames = const [];

  // ---------------------------------------------------------------- asserts

  /// Every recorded call to [method].
  List<GatewayCall> callsTo(GatewayMethod method) =>
      calls.where((call) => call.method == method).toList();

  /// How many times [method] was called.
  int countOf(GatewayMethod method) => callsTo(method).length;

  /// The last call to [method], or null if it was never called.
  GatewayCall? lastCall(GatewayMethod method) {
    final matching = callsTo(method);
    return matching.isEmpty ? null : matching.last;
  }

  /// One named argument from every call to [method], in call order.
  List<T> argValues<T>(GatewayMethod method, String name) =>
      callsTo(method).map((call) => call.arg<T>(name)).toList();

  // --------------------------------------------------------------- scripting

  /// Make the next [times] calls to [method] throw. [error] defaults to an
  /// [Exception]; pass a bare String where the screen renders the raw value.
  void failNext(GatewayMethod method, {Object? error, int times = 1}) {
    _failures[method] = _Failure(error ?? _defaultError(method), times);
  }

  /// Make every call to [method] throw.
  void failAlways(GatewayMethod method, {Object? error}) {
    _failures[method] = _Failure(error ?? _defaultError(method), null);
  }

  /// Hold calls to [method] open so a test can observe the pending UI.
  /// [release] lets them finish; without it they stay pending.
  void hold(GatewayMethod method) =>
      _held.putIfAbsent(method, () => Completer<void>());

  /// Let held calls to [method] finish and return their normal result.
  void release(GatewayMethod method) {
    final gate = _held.remove(method);
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  Object _defaultError(GatewayMethod method) =>
      Exception('ScriptableGateway: scripted failure of ${method.name}');

  // ----------------------------------------------------------------- seeding

  /// Seed the sessions `listSessions` and `poll` return. Replaces
  /// whatever was seeded before, so a test can seed again to change what the
  /// next poll sees.
  void seedSessions(Iterable<SessionSnapshot> sessions) {
    _sessions
      ..clear()
      ..addEntries(sessions.map((s) => MapEntry(s.sessionId, s)));
  }

  /// Seed the channels `listChannels` and `poll` return.
  void seedChannels(Iterable<ChannelSnapshot> channels) {
    _channels
      ..clear()
      ..addEntries(channels.map((c) => MapEntry(c.name, c)));
  }

  /// Seed the groups `listGroups` and `poll` return.
  void seedGroups(Iterable<GroupSnapshot> groups) {
    _groups
      ..clear()
      ..addEntries(groups.map((g) => MapEntry(g.groupId, g)));
  }

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

  /// Seed the NICs `listInterfaces` returns.
  void seedInterfaces(List<NetworkInterfaceInfo> interfaces) =>
      _interfaces = interfaces;

  /// Seed what `detectVpn` returns.
  void seedVpnDetection(VpnDetection detection) => _vpnDetection = detection;

  /// Seed what `getBindInterface` returns.
  void seedBindInterface(String? name) => _bindInterface = name;

  /// Seed what `getVpnBypassConsent` returns. `setVpnBypassConsent` overwrites
  /// it, so a test can set then read without touching the filesystem.
  void seedVpnConsent(VpnBypassConsent? consent) => _vpnConsent = consent;

  /// Seed the frames `callDrainFrames` returns.
  void seedCallFrames(List<Uint8List> frames) => _callFrames = frames;

  // ------------------------------------------------------------------ engine

  /// Record the call, apply any script, then produce the result.
  Future<T> _run<T>(
    GatewayMethod method,
    Map<String, Object?> args,
    FutureOr<T> Function() result,
  ) async {
    calls.add(GatewayCall(method, args));
    final failure = _failures[method];
    if (failure != null && failure.consume()) throw failure.error;
    final gate = _held[method];
    if (gate != null) await gate.future;
    return result();
  }

  // ------------------------------------------------------------- diagnostics

  @override
  Future<AppDiagnostics> appDiagnostics() =>
      _run(GatewayMethod.appDiagnostics, const {}, cannedAppDiagnostics);

  @override
  Future<NativeRuntimeStatus> nativeRuntimeStatus() => _run(
      GatewayMethod.nativeRuntimeStatus,
      const {},
      () => _nativeStatus ?? cannedNativeRuntimeStatus());

  // ------------------------------------------------------------------ the DM

  @override
  Future<InviteCreated> createInvite({required StartSessionRequest request}) =>
      _run(GatewayMethod.createInvite, {'request': request}, () {
        final seeded = _invite;
        final sessionId = seeded?.sessionId ?? 'fake-${_sessions.length + 1}';
        final fingerprint = seeded?.fingerprint ?? fakeFingerprint(sessionId);
        final inviteUri = seeded?.inviteUri ??
            'mosh://invite?mesh=fakemesh&session=$sessionId#fp=$fingerprint';
        _sessions[sessionId] = fakeSession(
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
      _run(GatewayMethod.acceptInvite, {'request': request}, () {
        final sessionId = 'fake-accept-${_sessions.length + 1}';
        final snapshot = fakeSession(
          sessionId: sessionId,
          displayName: request.displayName,
          role: 'invitee',
          inviteUri: request.inviteUri,
          fingerprint: fakeFingerprint(sessionId),
        );
        _sessions[sessionId] = snapshot;
        return snapshot;
      });

  // ------------------------------------------------- the conversation seam

  @override
  Future<S> poll<S>(ConversationTarget<S> target) => _run(
        GatewayMethod.poll,
        {'target': target},
        () => target.readSnapshot(this),
      );

  @override
  Future<SessionSnapshot> dmSnapshot(String sessionId) async {
    final snapshot = _sessions[sessionId];
    if (snapshot == null) {
      throw Exception('poll: unknown sessionId "$sessionId"');
    }
    return snapshot;
  }

  @override
  Future<ChannelSnapshot> channelSnapshot(String name) async =>
      _channels[name] ?? cannedChannelSnapshot(name: name);

  @override
  Future<GroupSnapshot> groupSnapshot(String groupId) async =>
      _groups[groupId] ?? cannedGroupSnapshot(groupId: groupId);

  /// A DM send appends to the seeded session, so a screen that re-polls sees
  /// the new row. A channel or group send only records the call -- their
  /// snapshots stay whatever the test seeded.
  @override
  Future<void> send(AnyConversationTarget target, {required String body}) =>
      _run(GatewayMethod.send, {'target': target, 'body': body}, () {
        if (target is! DmTarget) return;
        final existing = _sessions[target.id];
        if (existing == null) return;
        _sessions[target.id] = withMessage(
          existing,
          body,
          'msg-${existing.messages.length + 1}',
          BigInt.from(DateTime.now().millisecondsSinceEpoch),
        );
      });

  @override
  Future<void> retry(AnyConversationTarget target,
          {required String messageId}) =>
      _run(GatewayMethod.retry, {'target': target, 'messageId': messageId},
          () {});

  @override
  Future<void> sendAttachment(
    AnyConversationTarget target, {
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  }) =>
      _run(
          GatewayMethod.sendAttachment,
          {
            'target': target,
            'fileName': fileName,
            'mime': mime,
            'dataBase64': dataBase64,
            'thumbnailBase64': thumbnailBase64,
            'voice': voice,
          },
          () {});

  @override
  Future<void> downloadAttachment(AnyConversationTarget target,
          {required String attachmentId}) =>
      _run(GatewayMethod.downloadAttachment,
          {'target': target, 'attachmentId': attachmentId}, () {});

  @override
  Future<void> cancelAttachment(AnyConversationTarget target,
          {required String attachmentId}) =>
      _run(GatewayMethod.cancelAttachment,
          {'target': target, 'attachmentId': attachmentId}, () {});

  @override
  Future<void> dismissDmOffer(DmOfferHost<Object?> target,
          {required String offerId}) =>
      _run(GatewayMethod.dismissDmOffer, {'target': target, 'offerId': offerId},
          () {});

  /// Leaving drops the conversation from the seeded state, so the next list
  /// call no longer returns it.
  @override
  Future<void> leave(AnyConversationTarget target) =>
      _run(GatewayMethod.leave, {'target': target}, () {
        switch (target) {
          case DmTarget():
            _sessions.remove(target.id);
          case ChannelTarget():
            _channels.remove(target.id);
          case GroupTarget():
            _groups.remove(target.id);
        }
      });

  @override
  Future<SessionListSnapshot> listSessions() => _run(
        GatewayMethod.listSessions,
        const {},
        () => SessionListSnapshot(sessions: _sessions.values.toList()),
      );

  @override
  Future<ChannelListSnapshot> listChannels() => _run(
        GatewayMethod.listChannels,
        const {},
        () => ChannelListSnapshot(channels: _channels.values.toList()),
      );

  @override
  Future<ChannelSnapshot> joinChannel({required JoinChannelRequest request}) =>
      _run(
          GatewayMethod.joinChannel,
          {'request': request},
          () =>
              _channels[request.name] ??
              cannedChannelSnapshot(
                  name: request.name, displayName: request.displayName));

  @override
  Future<void> sendChannelDmOffer({
    required String channelName,
    required String peerFingerprint,
    required String inviteUri,
  }) =>
      _run(
          GatewayMethod.sendChannelDmOffer,
          {
            'channelName': channelName,
            'peerFingerprint': peerFingerprint,
            'inviteUri': inviteUri,
          },
          () {});

  // ----------------------------------------------------------- the group

  @override
  Future<GroupListSnapshot> listGroups() => _run(
        GatewayMethod.listGroups,
        const {},
        () => GroupListSnapshot(groups: _groups.values.toList()),
      );

  @override
  Future<GroupCreated> createGroup({required CreateGroupRequest request}) =>
      _run(GatewayMethod.createGroup, {'request': request}, () {
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
      _run(GatewayMethod.joinGroup, {'request': request}, () {
        final groupId = groupIdFromInviteUri(request.inviteUri);
        return _groups[groupId] ??
            cannedGroupSnapshot(
              groupId: groupId,
              displayName: request.displayName,
              memberCount: BigInt.one,
              inviteUri: request.inviteUri,
              orgPubkey: request.orgPubkey,
            );
      });

  @override
  Future<void> sendGroupDmOffer({
    required String groupId,
    required String peerFingerprint,
    required String inviteUri,
  }) =>
      _run(
          GatewayMethod.sendGroupDmOffer,
          {
            'groupId': groupId,
            'peerFingerprint': peerFingerprint,
            'inviteUri': inviteUri,
          },
          () {});

  // ----------------------------------------------------------------- the org

  @override
  Future<OrgSnapshot> joinOrg({required JoinOrgRequest request}) => _run(
        GatewayMethod.joinOrg,
        {'request': request},
        () => cannedOrgSnapshot(
          orgPubkey: orgPubkeyFromBundleUri(request.bundleUri),
        ),
      );

  @override
  Future<void> leaveOrg({required String orgPubkey}) =>
      _run(GatewayMethod.leaveOrg, {'orgPubkey': orgPubkey}, () {});

  @override
  Future<List<OrgSnapshot>> listOrgs() =>
      _run(GatewayMethod.listOrgs, const {}, () => _orgs.values.toList());

  @override
  Future<OrgSnapshot> pollOrg({required String orgPubkey}) => _run(
      GatewayMethod.pollOrg,
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
      _run(
          GatewayMethod.sendOrgDmOffer,
          {
            'orgPubkey': orgPubkey,
            'targetPeerId': targetPeerId,
            'displayName': displayName,
            'listenPort': listenPort,
            'staticPeer': staticPeer,
          },
          () => InviteCreated(
                inviteUri: 'mosh://invite?session=fake-org-dm&fp=00#fp=00',
                sessionId: 'fake-org-dm-${_sessions.length + 1}',
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
      _run(GatewayMethod.acceptOrgDmOffer, {
        'orgPubkey': orgPubkey,
        'offerId': offerId,
        'displayName': displayName,
        'listenPort': listenPort,
        'staticPeer': staticPeer,
      }, () {
        final sessionId = 'fake-org-accept-${_sessions.length + 1}';
        final snapshot = fakeSession(
          sessionId: sessionId,
          displayName: displayName,
          role: 'invitee',
          inviteUri: 'mosh://invite?session=$sessionId&fp=00#fp=00',
          fingerprint: '00',
        );
        _sessions[sessionId] = snapshot;
        return snapshot;
      });

  @override
  Future<void> dismissOrgDmOffer({
    required String orgPubkey,
    required String offerId,
  }) =>
      _run(GatewayMethod.dismissOrgDmOffer,
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
      _run(
          GatewayMethod.createOrgGroup,
          {
            'orgPubkey': orgPubkey,
            'label': label,
            'memberPeerIds': memberPeerIds,
            'displayName': displayName,
            'listenPort': listenPort,
            'staticPeer': staticPeer,
          },
          () => GroupCreated(
                groupId: 'fake-org-group-${_groups.length + 1}',
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
      _run(
          GatewayMethod.acceptOrgGroupOffer,
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
      _run(GatewayMethod.dismissOrgGroupOffer,
          {'orgPubkey': orgPubkey, 'offerId': offerId}, () {});

  @override
  Future<void> orgGroupInviteMembers({
    required String orgPubkey,
    required String groupId,
    required List<String> memberPeerIds,
  }) =>
      _run(
          GatewayMethod.orgGroupInviteMembers,
          {
            'orgPubkey': orgPubkey,
            'groupId': groupId,
            'memberPeerIds': memberPeerIds,
          },
          () {});

  // ----------------------------------------------------------- network + VPN

  @override
  Future<List<NetworkInterfaceInfo>> listInterfaces() =>
      _run(GatewayMethod.listInterfaces, const {}, () => _interfaces);

  @override
  Future<VpnDetection> detectVpn() => _run(GatewayMethod.detectVpn, const {},
      () => _vpnDetection ?? cannedVpnDetection());

  @override
  Future<String?> getBindInterface() =>
      _run(GatewayMethod.getBindInterface, const {}, () => _bindInterface);

  @override
  Future<VpnBypassConsent?> getVpnBypassConsent() =>
      _run(GatewayMethod.getVpnBypassConsent, const {}, () => _vpnConsent);

  @override
  Future<void> setVpnBypassConsent({String? interfaceName}) =>
      _run(GatewayMethod.setVpnBypassConsent, {'interfaceName': interfaceName},
          () {
        final name = interfaceName;
        _vpnConsent = (name == null || name.isEmpty)
            ? null
            : VpnBypassConsent(interface_: name, index: 0);
      });

  // --------------------------------------------------------------- the calls

  @override
  Future<CallStarted> callStart({required String sessionId}) => _run(
      GatewayMethod.callStart,
      {'sessionId': sessionId},
      () => cannedCallStarted(sessionId));

  @override
  Future<void> callAccept({
    required String sessionId,
    required String callId,
  }) =>
      _run(GatewayMethod.callAccept, {'sessionId': sessionId, 'callId': callId},
          () {});

  @override
  Future<void> callDecline({
    required String sessionId,
    required String callId,
    required String reason,
  }) =>
      _run(GatewayMethod.callDecline,
          {'sessionId': sessionId, 'callId': callId, 'reason': reason}, () {});

  @override
  Future<void> callEnd({
    required String sessionId,
    required String callId,
    required String reason,
  }) =>
      _run(GatewayMethod.callEnd,
          {'sessionId': sessionId, 'callId': callId, 'reason': reason}, () {});

  @override
  Future<void> callSendFrame({
    required String sessionId,
    required String callId,
    required Uint8List frame,
  }) =>
      _run(GatewayMethod.callSendFrame,
          {'sessionId': sessionId, 'callId': callId, 'frame': frame}, () {});

  @override
  Future<List<Uint8List>> callDrainFrames({
    required String sessionId,
    required String callId,
  }) =>
      _run(GatewayMethod.callDrainFrames,
          {'sessionId': sessionId, 'callId': callId}, () => _callFrames);
}
