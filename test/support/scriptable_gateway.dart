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
// and acceptInvite insert a session, sendMessage appends a message,
// closeSession removes it.

import 'dart:async';
import 'dart:typed_data' show Uint8List;

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
  sendMessage,
  retryDmMessage,
  pollSession,
  listSessions,
  closeSession,
  downloadAttachment,
  cancelAttachment,
  pollChannel,
  listChannels,
  pollGroup,
  listGroups,
  joinChannel,
  sendChannel,
  leaveChannel,
  retryChannelMessage,
  sendGroup,
  retryGroupMessage,
  closeGroup,
  createGroup,
  joinGroup,
  dismissChannelDmOffer,
  dismissGroupDmOffer,
  sendChannelDmOffer,
  sendGroupDmOffer,
  downloadChannelAttachment,
  cancelChannelAttachment,
  downloadGroupAttachment,
  cancelGroupAttachment,
  sendChannelAttachment,
  sendPrivateAttachment,
  sendGroupAttachment,
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

  /// Read one argument. Throws if the type does not match, so a renamed or
  /// retyped argument fails the test instead of silently reading null.
  T arg<T>(String name) => args[name] as T;

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
class ScriptableGateway implements Gateway {
  /// Every call the code under test made, in order.
  final List<GatewayCall> calls = [];

  final Map<GatewayMethod, _Failure> _failures = {};
  final Map<GatewayMethod, Completer<void>> _held = {};

  final Map<String, SessionSnapshot> _sessions = {};
  final Map<String, ChannelSnapshot> _channels = {};
  final Map<String, GroupSnapshot> _groups = {};

  InviteCreated? _invite;
  NativeRuntimeStatus? _nativeStatus;
  List<NetworkInterfaceInfo> _interfaces = const [];
  VpnDetection? _vpnDetection;
  String? _bindInterface;
  VpnBypassConsent? _vpnConsent;
  List<Uint8List> _callFrames = const [];

  int _channelSendCount = 0;
  int _groupSendCount = 0;

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

  /// Seed the sessions `listSessions` and `pollSession` return. Replaces
  /// whatever was seeded before, so a test can seed again to change what the
  /// next poll sees.
  void seedSessions(Iterable<SessionSnapshot> sessions) {
    _sessions
      ..clear()
      ..addEntries(sessions.map((s) => MapEntry(s.sessionId, s)));
  }

  /// Seed the channels `listChannels` and `pollChannel` return.
  void seedChannels(Iterable<ChannelSnapshot> channels) {
    _channels
      ..clear()
      ..addEntries(channels.map((c) => MapEntry(c.name, c)));
  }

  /// Seed the groups `listGroups` and `pollGroup` return.
  void seedGroups(Iterable<GroupSnapshot> groups) {
    _groups
      ..clear()
      ..addEntries(groups.map((g) => MapEntry(g.groupId, g)));
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
    T Function() result,
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

  @override
  Future<SendMessageResult> sendMessage({
    required String sessionId,
    required String body,
  }) =>
      _run(GatewayMethod.sendMessage, {'sessionId': sessionId, 'body': body},
          () {
        final existing = _sessions[sessionId];
        final messageId = 'msg-${(existing?.messages.length ?? 0) + 1}';
        if (existing != null) {
          _sessions[sessionId] = withMessage(existing, body, messageId,
              BigInt.from(DateTime.now().millisecondsSinceEpoch));
        }
        return cannedSendMessageResult(
          sessionId: sessionId,
          messageId: messageId,
          ciphertextBytes: BigInt.from(body.codeUnits.length),
        );
      });

  @override
  Future<SendMessageResult> retryDmMessage({
    required String sessionId,
    required String messageId,
  }) =>
      _run(
          GatewayMethod.retryDmMessage,
          {'sessionId': sessionId, 'messageId': messageId},
          () => cannedSendMessageResult(
                sessionId: sessionId,
                messageId: 'retry-$messageId',
                ciphertextBytes: BigInt.zero,
              ));

  @override
  Future<SessionSnapshot> pollSession({required String sessionId}) =>
      _run(GatewayMethod.pollSession, {'sessionId': sessionId}, () {
        final snapshot = _sessions[sessionId];
        if (snapshot == null) {
          throw Exception('pollSession: unknown sessionId "$sessionId"');
        }
        return snapshot;
      });

  @override
  Future<SessionListSnapshot> listSessions() => _run(
        GatewayMethod.listSessions,
        const {},
        () => SessionListSnapshot(sessions: _sessions.values.toList()),
      );

  @override
  Future<CloseSessionResult> closeSession({required String sessionId}) => _run(
      GatewayMethod.closeSession,
      {'sessionId': sessionId},
      () => CloseSessionResult(
            sessionId: sessionId,
            closed: _sessions.remove(sessionId) != null,
          ));

  @override
  Future<void> downloadAttachment({
    required String sessionId,
    required String attachmentId,
  }) =>
      _run(GatewayMethod.downloadAttachment,
          {'sessionId': sessionId, 'attachmentId': attachmentId}, () {});

  @override
  Future<void> cancelAttachment({
    required String sessionId,
    required String attachmentId,
  }) =>
      _run(GatewayMethod.cancelAttachment,
          {'sessionId': sessionId, 'attachmentId': attachmentId}, () {});

  // ------------------------------------------------------------- the channel

  @override
  Future<ChannelSnapshot> pollChannel({required String name}) => _run(
      GatewayMethod.pollChannel,
      {'name': name},
      () => _channels[name] ?? cannedChannelSnapshot(name: name));

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
  Future<ChannelSendResult> sendChannel({
    required String name,
    required String body,
  }) =>
      _run(
          GatewayMethod.sendChannel,
          {'name': name, 'body': body},
          () => cannedChannelSendResult(
                name: name,
                messageId: 'fake-channel-${_channelSendCount++}',
                bytes: BigInt.from(body.codeUnits.length),
              ));

  @override
  Future<ChannelSendResult> retryChannelMessage({
    required String name,
    required String messageId,
  }) =>
      _run(
          GatewayMethod.retryChannelMessage,
          {'name': name, 'messageId': messageId},
          () => cannedChannelSendResult(
                name: name,
                messageId: 'retry-$messageId',
                bytes: BigInt.zero,
              ));

  @override
  Future<ChannelLeaveResult> leaveChannel({required String name}) =>
      _run(GatewayMethod.leaveChannel, {'name': name}, () {
        _channels.remove(name);
        return ChannelLeaveResult(name: name, closed: true);
      });

  @override
  Future<void> dismissChannelDmOffer({
    required String name,
    required String offerId,
  }) =>
      _run(GatewayMethod.dismissChannelDmOffer,
          {'name': name, 'offerId': offerId}, () {});

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

  @override
  Future<void> downloadChannelAttachment({
    required String name,
    required String attachmentId,
  }) =>
      _run(GatewayMethod.downloadChannelAttachment,
          {'name': name, 'attachmentId': attachmentId}, () {});

  @override
  Future<void> cancelChannelAttachment({
    required String name,
    required String attachmentId,
  }) =>
      _run(GatewayMethod.cancelChannelAttachment,
          {'name': name, 'attachmentId': attachmentId}, () {});

  @override
  Future<AttachmentSendResult> sendChannelAttachment({
    required String name,
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  }) =>
      _run(
          GatewayMethod.sendChannelAttachment,
          {
            'name': name,
            'fileName': fileName,
            'mime': mime,
            'dataBase64': dataBase64,
            'thumbnailBase64': thumbnailBase64,
            'voice': voice,
          },
          () => cannedAttachmentSendResult(
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
      _run(
          GatewayMethod.sendPrivateAttachment,
          {
            'sessionId': sessionId,
            'fileName': fileName,
            'mime': mime,
            'dataBase64': dataBase64,
            'thumbnailBase64': thumbnailBase64,
            'voice': voice,
          },
          () => cannedAttachmentSendResult(
                sessionPrefix: 'fake-dm',
                id: sessionId,
                fileName: fileName,
                dataBase64: dataBase64,
              ));

  // --------------------------------------------------------------- the group

  @override
  Future<GroupSnapshot> pollGroup({required String groupId}) => _run(
      GatewayMethod.pollGroup,
      {'groupId': groupId},
      () => _groups[groupId] ?? cannedGroupSnapshot(groupId: groupId));

  @override
  Future<GroupListSnapshot> listGroups() => _run(
        GatewayMethod.listGroups,
        const {},
        () => GroupListSnapshot(groups: _groups.values.toList()),
      );

  @override
  Future<GroupSendResult> sendGroup({
    required String groupId,
    required String body,
  }) =>
      _run(
          GatewayMethod.sendGroup,
          {'groupId': groupId, 'body': body},
          () => cannedGroupSendResult(
                groupId: groupId,
                messageId: 'fake-group-${_groupSendCount++}',
                bytes: BigInt.from(body.codeUnits.length),
              ));

  @override
  Future<GroupSendResult> retryGroupMessage({
    required String groupId,
    required String messageId,
  }) =>
      _run(
          GatewayMethod.retryGroupMessage,
          {'groupId': groupId, 'messageId': messageId},
          () => cannedGroupSendResult(
                groupId: groupId,
                messageId: 'retry-$messageId',
                bytes: BigInt.zero,
              ));

  @override
  Future<GroupLeaveResult> closeGroup({required String groupId}) =>
      _run(GatewayMethod.closeGroup, {'groupId': groupId}, () {
        _groups.remove(groupId);
        return GroupLeaveResult(groupId: groupId, closed: true);
      });

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
  Future<void> dismissGroupDmOffer({
    required String groupId,
    required String offerId,
  }) =>
      _run(GatewayMethod.dismissGroupDmOffer,
          {'groupId': groupId, 'offerId': offerId}, () {});

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

  @override
  Future<void> downloadGroupAttachment({
    required String groupId,
    required String attachmentId,
  }) =>
      _run(GatewayMethod.downloadGroupAttachment,
          {'groupId': groupId, 'attachmentId': attachmentId}, () {});

  @override
  Future<void> cancelGroupAttachment({
    required String groupId,
    required String attachmentId,
  }) =>
      _run(GatewayMethod.cancelGroupAttachment,
          {'groupId': groupId, 'attachmentId': attachmentId}, () {});

  @override
  Future<AttachmentSendResult> sendGroupAttachment({
    required String groupId,
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  }) =>
      _run(
          GatewayMethod.sendGroupAttachment,
          {
            'groupId': groupId,
            'fileName': fileName,
            'mime': mime,
            'dataBase64': dataBase64,
            'thumbnailBase64': thumbnailBase64,
            'voice': voice,
          },
          () => cannedAttachmentSendResult(
                sessionPrefix: 'fake-group',
                id: groupId,
                fileName: fileName,
                dataBase64: dataBase64,
              ));

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
      _run(GatewayMethod.listOrgs, const {}, () => const <OrgSnapshot>[]);

  @override
  Future<OrgSnapshot> pollOrg({required String orgPubkey}) => _run(
      GatewayMethod.pollOrg,
      {'orgPubkey': orgPubkey},
      () => cannedOrgSnapshot(orgPubkey: orgPubkey));

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
