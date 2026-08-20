// Canned snapshots the test Gateway returns when a test seeds nothing.
// Every function here is pure: ScriptableGateway owns all mutable state.
// The shapes mirror the real runtime 1:1.

import 'package:mosh/src/rust/api/diagnostics.dart'
    show
        AppDiagnostics,
        NativeRuntimeStatus,
        OpenMlsRoundTripRuntimeStatus,
        OpenMlsSmokeRuntimeStatus;
import 'package:mosh/src/rust/api/vpn.dart' show VpnDetection;
import 'package:mosh/src/rust/channel_runtime.dart'
    show ChannelSendResult, ChannelSnapshot;
import 'package:mosh/src/rust/moss_runtime.dart' show MossRuntimeStatus;
import 'package:mosh/src/rust/openmls_crypto.dart'
    show OpenMlsRoundTripStatus, OpenMlsSmokeStatus;
import 'package:mosh/src/rust/org_runtime.dart' show OrgSnapshot;
import 'package:mosh/src/rust/outbound_delivery.dart'
    show MessageDeliveryStatus;
import 'package:mosh/src/rust/persistence.dart' show PersistenceRuntimeStatus;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show AttachmentSendResult, CallStarted, ChatMessage, SendMessageResult,
        SessionSnapshot;
import 'package:mosh/src/rust/private_group_runtime.dart'
    show GroupSendResult, GroupSnapshot;
import 'package:mosh/src/rust/secure_storage.dart' show SecureStorageStatus;

/// Canned [AppDiagnostics] for the test gateway appDiagnostics().
AppDiagnostics cannedAppDiagnostics() => const AppDiagnostics(
      appName: 'Mosh',
      privacyModel: 'OpenMLS private messages over Moss transport',
      discoveryModel: 'default public Moss trackers',
      mossLinkMode: 'dynamic',
    );

/// Canned [NativeRuntimeStatus] mirroring the real
/// `native_runtime_status()` shape: moss dynamically available, secure storage
/// on the OS keychain, persistence not running in the fake, OpenMLS smoke +
/// roundtrip succeeding.
NativeRuntimeStatus cannedNativeRuntimeStatus() => NativeRuntimeStatus(
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
          ciphersuite: 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519',
          protectedMessageCreated: true,
        ),
        error: null,
      ),
      openmlsRoundtrip: OpenMlsRoundTripRuntimeStatus(
        ok: OpenMlsRoundTripStatus(
          provider: 'openmls_rust_crypto',
          ciphersuite: 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519',
          welcomeJoined: true,
          plaintextRoundtrip: true,
        ),
        error: null,
      ),
    );

/// Canned empty [ChannelSnapshot] for pollChannel + joinChannel. Empty lists for
/// messages/attachments/dmOffers/events; required strings blanked.
ChannelSnapshot cannedChannelSnapshot({
  required String name,
  String displayName = '',
}) =>
    ChannelSnapshot(
      name: name,
      topic: '',
      meshId: '',
      displayName: displayName,
      deviceFingerprint: '',
      messages: const [],
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
    );

/// Canned [GroupSnapshot] for pollGroup + joinGroup + acceptOrgGroupOffer.
/// Defaults mirror pollGroup (empty/zero/null); callers override the fields
/// the request supplies.
GroupSnapshot cannedGroupSnapshot({
  required String groupId,
  String displayName = '',
  String deviceFingerprint = '',
  String creatorFingerprint = '',
  bool isAdmin = false,
  BigInt? memberCount,
  String? inviteUri,
  String? orgPubkey,
}) =>
    GroupSnapshot(
      groupId: groupId,
      meshId: '',
      label: null,
      displayName: displayName,
      deviceFingerprint: deviceFingerprint,
      creatorFingerprint: creatorFingerprint,
      isAdmin: isAdmin,
      state: 'ready',
      memberCount: memberCount ?? BigInt.zero,
      inviteUri: inviteUri,
      messages: const [],
      attachments: const [],
      dmOffers: const [],
      mesh: null,
      events: const [],
      needsRejoin: false,
      orgPubkey: orgPubkey,
      memberPeerIds: const [],
    );

/// Canned [OrgSnapshot] for joinOrg + pollOrg. Empty-but-valid members/offers/
/// links (the org has no other members in the fake).
OrgSnapshot cannedOrgSnapshot({required String orgPubkey}) => OrgSnapshot(
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
    );

/// Canned no-VPN [VpnDetection] for the test gateway detectVpn().
VpnDetection cannedVpnDetection() => const VpnDetection(
      vpnLikely: false,
      suspectInterfaces: [],
      vpnOwnsDefaultRoute: false,
    );

/// Fake [SessionSnapshot] for createInvite/acceptInvite/acceptOrgDmOffer.
/// State `connecting`, no messages/attachments, no calls.
SessionSnapshot fakeSession({
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

/// Append one [ChatMessage] to a session snapshot (sendMessage helper).
/// Copies every base field, spreads the existing messages, appends the new one.
SessionSnapshot withMessage(
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

/// Deterministic 16-char hex fingerprint derived from the session id, so
/// createInvite/acceptInvite return a stable value the screen can render +
/// the fingerprint-confirm flow can assert against.
String fakeFingerprint(String sessionId) {
  final hex = sessionId.codeUnits
      .map((c) => c.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
  return (hex + '0' * 16).substring(0, 16);
}

/// Parse the `group=` query param from a `mosh://group?...&group=<id>&...`
/// invite URI. Falls back to `fake-group-joined` when absent so joinGroup
/// always returns a non-empty groupId. Mirrors `detectInvite`
/// (lib/src/invite/invite_detection.dart).
String groupIdFromInviteUri(String inviteUri) {
  final parsed = Uri.tryParse(inviteUri);
  final group = parsed?.queryParameters['group'];
  return (group == null || group.isEmpty) ? 'fake-group-joined' : group;
}

/// Derive a deterministic orgPubkey from a `mosh://org?...` bundle URI via the
/// `org=` query param (mirrors `detectInvite`'s org classification). Falls back
/// to `fake-org-joined`.
String orgPubkeyFromBundleUri(String bundleUri) {
  final parsed = Uri.tryParse(bundleUri);
  final org = parsed?.queryParameters['org'];
  return (org == null || org.isEmpty) ? 'fake-org-joined' : org;
}

/// Canned [CallStarted] for the test gateway callStart (1:1 with React demo
/// gateway). Deterministic call id + dummy key/nonce so a future call-UI
/// test can assert against the canned value without the runtime.
CallStarted cannedCallStarted(String sessionId) => CallStarted(
      sessionId: sessionId,
      callId: 'fake-call',
      keyB64: 'fake-key',
      noncePrefixB64: 'fake-nonce',
    );

/// Canned [AttachmentSendResult] for the three send*Attachment seams
/// (channel/DM/group). The id prefix + the id value differ per kind; the
/// attachmentId/contentHash derive from the file name + payload hash so the
/// screen can invalidate + the next poll renders a distinct row.
AttachmentSendResult cannedAttachmentSendResult({
  required String sessionPrefix,
  required String id,
  required String fileName,
  required String dataBase64,
}) =>
    AttachmentSendResult(
      sessionId: '$sessionPrefix:$id',
      attachmentId: 'fake-$sessionPrefix-attachment:${fileName.hashCode}',
      contentHash: 'fake-hash:${dataBase64.hashCode}',
    );

/// Canned [SendMessageResult] for the test gateway sendMessage + retryDmMessage.
/// `state` is `connecting`, `deliveryStatus.sent`, `deliveryError` null;
/// `ciphertextBytes` is the caller-supplied payload length (or zero for a
/// retry), `sentAtMs` is now.
SendMessageResult cannedSendMessageResult({
  required String sessionId,
  required String messageId,
  required BigInt ciphertextBytes,
}) =>
    SendMessageResult(
      sessionId: sessionId,
      state: 'connecting',
      ciphertextBytes: ciphertextBytes,
      messageId: messageId,
      sentAtMs: BigInt.from(DateTime.now().millisecondsSinceEpoch),
      deliveryStatus: MessageDeliveryStatus.sent,
      deliveryError: null,
    );

/// Canned [ChannelSendResult] for the test gateway sendChannel + retryChannelMessage.
ChannelSendResult cannedChannelSendResult({
  required String name,
  required String messageId,
  required BigInt bytes,
}) =>
    ChannelSendResult(
      name: name,
      bytes: bytes,
      messageId: messageId,
      sentAtMs: BigInt.from(DateTime.now().millisecondsSinceEpoch),
      deliveryStatus: MessageDeliveryStatus.sent,
      deliveryError: null,
    );

/// Canned [GroupSendResult] for the test gateway sendGroup + retryGroupMessage.
GroupSendResult cannedGroupSendResult({
  required String groupId,
  required String messageId,
  required BigInt bytes,
}) =>
    GroupSendResult(
      groupId: groupId,
      bytes: bytes,
      messageId: messageId,
      sentAtMs: BigInt.from(DateTime.now().millisecondsSinceEpoch),
      deliveryStatus: MessageDeliveryStatus.sent,
      deliveryError: null,
    );
