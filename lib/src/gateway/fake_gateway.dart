// S4.1: In-Dart test double for the slice-one Gateway surface (ADR 0013).
//
// FakeGateway lets slice-one widget tests run without the Rust runtime. It
// implements the eight Gateway methods with canned data and keeps an in-memory
// session map so createInvite/acceptInvite/sendMessage/pollSession feel
// stateful. Widgets consume this via the gatewayProvider seam (S4.4 wires it
// in); S4.1 ships the class + a focused unit test only.

import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/rust/api/diagnostics.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';
import 'package:mosh/src/rust/org_runtime.dart';
import 'package:mosh/src/rust/outbound_delivery.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/rust/moss_runtime.dart';
import 'package:mosh/src/rust/openmls_crypto.dart';
import 'package:mosh/src/rust/persistence.dart';
import 'package:mosh/src/rust/secure_storage.dart';

/// Slice-one fake runtime: canned diagnostics + an in-memory session map.
///
/// Stateful by design (ADR 0013): each createInvite/acceptInvite inserts a
/// SessionSnapshot; sendMessage/pollSession/closeSession mutate or read it.
/// All methods complete synchronously via Future.value.
class FakeGateway implements Gateway {
  final Map<String, SessionSnapshot> _sessions = {};
  int _channelSendCount = 0;
  int _groupSendCount = 0;

  @override
  Future<AppDiagnostics> appDiagnostics() => Future.value(const AppDiagnostics(
        appName: 'Mosh',
        privacyModel: 'OpenMLS private messages over Moss transport',
        discoveryModel: 'default public Moss trackers',
        mossLinkMode: 'dynamic',
      ));

  // Now that the five NativeRuntimeStatus sub-structs are non-opaque across
  // flutter_rust_bridge, the generated Dart classes have real field
  // constructors, so the fake can synthesize a plausible runtime snapshot
  // without the Rust runtime. Values mirror the real `native_runtime_status()`
  // shape: moss dynamically available, secure storage on the OS keychain,
  // persistence not running in this fake, OpenMLS smoke + roundtrip succeeding.
  @override
  Future<NativeRuntimeStatus> nativeRuntimeStatus() => Future.value(
        NativeRuntimeStatus(
          moss: MossRuntimeStatus(
            linkMode: 'dynamic',
            libraryName: 'moss.dll',
            requiredSymbols: const [
              'Moss_Init',
              'Moss_Start',
              'Moss_Stop',
              'Moss_Subscribe',
              'Moss_Publish',
              'Moss_SetCallback',
              'Moss_SetKeyStore',
              'Moss_Free',
            ],
            available: true,
            checkedPaths: const ['moss.dll', 'moss-runtime/moss.dll'],
          ),
          secureStorage: SecureStorageStatus(
            backend: 'os-keychain',
            service: 'app.mosh.desktop',
            available: true,
          ),
          persistence: PersistenceRuntimeStatus(
            backend: 'redb+aes-256-gcm+os-keychain',
            database: 'unavailable',
            available: false,
            encryptedAtRest: false,
            error: 'no persistence instance running in this fake',
          ),
          openmlsSmoke: OpenMlsSmokeRuntimeStatus(
            ok: OpenMlsSmokeStatus(
              provider: 'openmls_rust_crypto',
              ciphersuite:
                  'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519',
              protectedMessageCreated: true,
            ),
            error: null,
          ),
          openmlsRoundtrip: OpenMlsRoundTripRuntimeStatus(
            ok: OpenMlsRoundTripStatus(
              provider: 'openmls_rust_crypto',
              ciphersuite:
                  'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519',
              welcomeJoined: true,
              plaintextRoundtrip: true,
            ),
            error: null,
          ),
        ),
      );

  @override
  Future<InviteCreated> createInvite({required StartSessionRequest request}) {
    final sessionId = 'fake-${_sessions.length + 1}';
    final fingerprint = _fakeFingerprint(sessionId);
    final inviteUri =
        'mosh://invite?mesh=fakemesh&session=$sessionId#fp=$fingerprint';
    final created = InviteCreated(
      inviteUri: inviteUri,
      sessionId: sessionId,
      meshId: 'fakemesh',
      fingerprint: fingerprint,
      listenAddress: '127.0.0.1:${request.listenPort}',
    );
    _sessions[sessionId] = _fakeSession(
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
    final fingerprint = _fakeFingerprint(sessionId);
    final snapshot = _fakeSession(
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
    _sessions[sessionId] = _withMessage(existing, body, messageId, sentAtMs);
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
  }) => Future.value();

  @override
  Future<void> cancelAttachment({
    required String sessionId,
    required String attachmentId,
  }) => Future.value();

  // Channels/groups read seam: the fake has no real channel/group runtime,
  // so each method returns a canned minimal-but-valid snapshot (empty lists
  // for messages/attachments/dmOffers/events; required strings blanked). This
  // matches the constructor field order/optionality in channel_runtime.dart
  // and private_group_runtime.dart.
  @override
  Future<ChannelSnapshot> pollChannel({required String name}) =>
      Future.value(ChannelSnapshot(
        name: name,
        topic: '',
        meshId: '',
        displayName: '',
        deviceFingerprint: '',
        messages: const [],
        attachments: const [],
        dmOffers: const [],
        mesh: null,
        events: const [],
      ));

  @override
  Future<ChannelListSnapshot> listChannels() =>
      Future.value(const ChannelListSnapshot(channels: []));

  @override
  Future<GroupSnapshot> pollGroup({required String groupId}) =>
      Future.value(GroupSnapshot(
        groupId: groupId,
        meshId: '',
        label: null,
        displayName: '',
        deviceFingerprint: '',
        creatorFingerprint: '',
        isAdmin: false,
        state: 'ready',
        memberCount: BigInt.zero,
        inviteUri: null,
        messages: const [],
        attachments: const [],
        dmOffers: const [],
        mesh: null,
        events: const [],
        needsRejoin: false,
        orgPubkey: null,
        memberPeerIds: const [],
      ));

  @override
  Future<GroupListSnapshot> listGroups() =>
      Future.value(const GroupListSnapshot(groups: []));

  // Channels/groups write seam: the fake has no real channel/group runtime, so
  // each method returns a canned minimal-but-valid result (zero bytes, a
  // placeholder messageId, `sent` delivery status for sends; `closed: true`
  // for leave/close). No state is mutated -- this fake has no message store for
  // channels/groups, so pollChannel/pollGroup keep returning their canned
  // snapshots. Mirrors the SendMessageResult shape used by sendMessage above.
  // The `joinChannel` seam (slice-3) mirrors pollChannel's canned snapshot --
  // joining in the fake is a no-op that returns a minimal-but-valid
  // ChannelSnapshot for the requested name (the real impl returns the post-join
  // snapshot from the runtime).
  @override
  Future<ChannelSnapshot> joinChannel({required JoinChannelRequest request}) =>
      Future.value(ChannelSnapshot(
        name: request.name,
        topic: '',
        meshId: '',
        displayName: request.displayName,
        deviceFingerprint: '',
        messages: const [],
        attachments: const [],
        dmOffers: const [],
        mesh: null,
        events: const [],
      ));

  @override
  Future<ChannelSendResult> sendChannel({required String name, required String body}) =>
      Future.value(ChannelSendResult(
        name: name,
        bytes: BigInt.from(body.codeUnits.length),
        messageId: 'fake-channel-${_channelSendCount++}',
        sentAtMs: BigInt.from(DateTime.now().millisecondsSinceEpoch),
        deliveryStatus: MessageDeliveryStatus.sent,
        deliveryError: null,
      ));

  @override
  Future<ChannelLeaveResult> leaveChannel({required String name}) =>
      Future.value(ChannelLeaveResult(name: name, closed: true));

  @override
  Future<GroupSendResult> sendGroup({required String groupId, required String body}) =>
      Future.value(GroupSendResult(
        groupId: groupId,
        bytes: BigInt.from(body.codeUnits.length),
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
    final groupId = _groupIdFromInviteUri(request.inviteUri);
    return Future.value(GroupSnapshot(
      groupId: groupId,
      meshId: '',
      label: null,
      displayName: request.displayName,
      deviceFingerprint: '',
      creatorFingerprint: '',
      isAdmin: false,
      state: 'ready',
      memberCount: BigInt.one,
      inviteUri: request.inviteUri,
      messages: const [],
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
      needsRejoin: false,
      orgPubkey: request.orgPubkey,
      memberPeerIds: const [],
    ));
  }

  // The `joinOrg` seam (slice-3) mirrors the React happy path: a canned
  // OrgSnapshot with empty-but-valid members/offers/links (the org has no
  // other members in the fake) + a deterministic orgPubkey derived from the
  // bundle URI. React's joinOrg does NOT navigate to a dedicated screen --
  // it just leaves setup + refreshes the orgs list -- so the caller
  // navigates to the sessions list, where the org appears after refresh.
  @override
  Future<OrgSnapshot> joinOrg({required JoinOrgRequest request}) {
    final orgPubkey = _orgPubkeyFromBundleUri(request.bundleUri);
    return Future.value(OrgSnapshot(
      orgPubkey: orgPubkey,
      orgName: '',
      meshId: '',
      ownPeerId: '',
      confirmationCode: '',
      inRoster: false,
      rosterVersion: null,
      members: const [],
      dmOffers: const [],
      groupOffers: const [],
      dmLinks: const [],
    ));
  }

  SessionSnapshot _fakeSession({
    required String sessionId,
    required String displayName,
    required String role,
    required String inviteUri,
    required String fingerprint,
  }) =>
      SessionSnapshot(
        sessionId: sessionId,
        meshId: 'fakemesh',
        role: role,
        displayName: displayName,
        peerDisplayName: '',
        state: 'connecting',
        path: 'connecting',
        relayReady: null,
        inviteUri: inviteUri,
        fingerprint: fingerprint,
        messages: const [],
        attachments: const [],
        mesh: null,
        events: const [],
        pendingCall: null,
        outgoingCall: null,
        activeCall: null,
      );

  SessionSnapshot _withMessage(
    SessionSnapshot base,
    String body,
    String messageId,
    BigInt sentAtMs,
  ) =>
      SessionSnapshot(
        sessionId: base.sessionId,
        meshId: base.meshId,
        role: base.role,
        displayName: base.displayName,
        peerDisplayName: base.peerDisplayName,
        state: base.state,
        path: base.path,
        relayReady: base.relayReady,
        inviteUri: base.inviteUri,
        fingerprint: base.fingerprint,
        messages: [
          ...base.messages,
          ChatMessage(
            fromDevice: base.displayName,
            body: body,
            messageId: messageId,
            sentAtMs: sentAtMs,
            deliveryStatus: MessageDeliveryStatus.sent,
            deliveryError: null,
            retryable: null,
            retryCount: null,
          ),
        ],
        attachments: base.attachments,
        mesh: base.mesh,
        events: base.events,
        pendingCall: base.pendingCall,
        outgoingCall: base.outgoingCall,
        activeCall: base.activeCall,
      );

  String _fakeFingerprint(String sessionId) {
    final hex = sessionId.codeUnits
        .map((c) => c.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    return (hex + '0' * 16).substring(0, 16);
  }
}

/// Parses the `group=` query param from a `mosh://group?...&group=<id>&...`
/// invite URI. Falls back to a stable `fake-group-joined` placeholder when
/// the param is absent so [FakeGateway.joinGroup] always returns a non-empty
/// groupId the screen can navigate to. Mirrors what `detectInvite` reads to
/// classify a group invite (lib/src/invite/invite_detection.dart).
String _groupIdFromInviteUri(String inviteUri) {
  final parsed = Uri.tryParse(inviteUri);
  final group = parsed?.queryParameters['group'];
  return (group == null || group.isEmpty) ? 'fake-group-joined' : group;
}

/// Derives a deterministic orgPubkey from a `mosh://org?...` bundle URI so
/// [FakeGateway.joinOrg] returns a non-empty pubkey the caller can use to
/// refresh the orgs list. Uses the `org=` query param when present (mirrors
/// `detectInvite`'s org classification); falls back to `fake-org-joined`.
String _orgPubkeyFromBundleUri(String bundleUri) {
  final parsed = Uri.tryParse(bundleUri);
  final org = parsed?.queryParameters['org'];
  return (org == null || org.isEmpty) ? 'fake-org-joined' : org;
}
