// Shared builders for the conversation test suites, replacing the
// per-file private `_msg` / `_snapshot` helpers that were duplicated
// across test files. Each builder stamps the same nulls/defaults those
// private helpers did; tests override only what their assertions need.
//
// `TestMessages.*` produce bare message objects with every optional
// field defaulted to null, exactly like the old private `_msg` helpers.
// `TestSnapshots.*` produce fully-populated snapshots carrying benign
// defaults (`meshId: 'testmesh'`, empty attachments/events, etc.);
// every field a test varied in practice is an override-able named param.

import 'package:mosh/src/rust/channel_runtime.dart'
    show ChannelMessage, ChannelSnapshot;
import 'package:mosh/src/rust/conversation/attachments.dart'
    show AttachmentDescriptor;
import 'package:mosh/src/rust/outbound_delivery.dart'
    show MessageDeliveryStatus;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show
        ActiveCall,
        CallEvent,
        ChatMessage,
        ConnectOutcome,
        DmSessionState,
        OutgoingCall,
        PendingCall,
        SessionSnapshot;
import 'package:mosh/src/rust/private_dm_runtime/transport.dart'
    show PeerTransport;
import 'package:mosh/src/rust/private_group_runtime.dart'
    show GroupMessage, GroupSnapshot, TypingMember;

/// Bare message constructors; every optional field defaults to null.
class TestMessages {
  TestMessages._();

  /// Private-DM `ChatMessage` (all optional fields null).
  static ChatMessage dm({
    required String fromDevice,
    required String body,
    BigInt? sentAtMs,
    String? messageId,
    AttachmentDescriptor? attachment,
    CallEvent? callEvent,
    MessageDeliveryStatus? deliveryStatus,
    String? deliveryError,
    bool? retryable,
    int? retryCount,
    bool? read,
  }) =>
      ChatMessage(
        fromDevice: fromDevice,
        body: body,
        messageId: messageId,
        sentAtMs: sentAtMs,
        attachment: attachment,
        callEvent: callEvent,
        deliveryStatus: deliveryStatus,
        deliveryError: deliveryError,
        retryable: retryable,
        retryCount: retryCount,
        read: read,
      );

  /// Private-group `GroupMessage` (all optional fields null).
  static GroupMessage group({
    required String fromDevice,
    required String fromFingerprint,
    required String body,
    BigInt? sentAtMs,
    String? messageId,
    AttachmentDescriptor? attachment,
    MessageDeliveryStatus? deliveryStatus,
    String? deliveryError,
    bool? retryable,
    int? retryCount,
  }) =>
      GroupMessage(
        fromDevice: fromDevice,
        fromFingerprint: fromFingerprint,
        body: body,
        messageId: messageId,
        sentAtMs: sentAtMs,
        attachment: attachment,
        deliveryStatus: deliveryStatus,
        deliveryError: deliveryError,
        retryable: retryable,
        retryCount: retryCount,
      );

  /// Public-channel `ChannelMessage` (all optional fields null).
  static ChannelMessage channel({
    required String fromDevice,
    required String fromFingerprint,
    required String body,
    BigInt? sentAtMs,
    String? messageId,
    AttachmentDescriptor? attachment,
    MessageDeliveryStatus? deliveryStatus,
    String? deliveryError,
    bool? retryable,
    int? retryCount,
  }) =>
      ChannelMessage(
        fromDevice: fromDevice,
        fromFingerprint: fromFingerprint,
        body: body,
        messageId: messageId,
        sentAtMs: sentAtMs,
        attachment: attachment,
        deliveryStatus: deliveryStatus,
        deliveryError: deliveryError,
        retryable: retryable,
        retryCount: retryCount,
      );
}

/// Canned snapshots; benign defaults, override-able named params.
class TestSnapshots {
  TestSnapshots._();

  /// Private-DM `SessionSnapshot`. Defaults mirror the DM tests' old
  /// private `_snapshot` helper (connected direct session, `inviter`
  /// role, placeholder fingerprint).
  static SessionSnapshot dm({
    required String sessionId,
    String displayName = 'me',
    List<ChatMessage> messages = const [],
    String meshId = 'testmesh',
    String role = 'inviter',
    String peerDisplayName = '',
    DmSessionState state = DmSessionState.connected,
    PeerTransport transport = PeerTransport.direct,
    String? peerMossId,
    ConnectOutcome? lastConnectOutcome,
    String? inviteUri,
    String fingerprint = '0123456789abcdef',
    PendingCall? pendingCall,
    BigInt? peerTypingUntilMs,
    OutgoingCall? outgoingCall,
    ActiveCall? activeCall,
  }) =>
      SessionSnapshot(
        sessionId: sessionId,
        meshId: meshId,
        role: role,
        displayName: displayName,
        peerDisplayName: peerDisplayName,
        state: state,
        transport: transport,
        peerMossId: peerMossId,
        lastConnectOutcome: lastConnectOutcome,
        inviteUri: inviteUri,
        fingerprint: fingerprint,
        messages: messages,
        attachments: const [],
        mesh: null,
        events: const [],
        pendingCall: pendingCall,
        peerTypingUntilMs: peerTypingUntilMs,
        outgoingCall: outgoingCall,
        activeCall: activeCall,
      );

  /// Private-group `GroupSnapshot`. Defaults mirror the group tests'
  /// old private `_snapshot` helpers (ready 2-member group, `me` as
  /// display name and creator, no rejoin needed).
  static GroupSnapshot group({
    required String groupId,
    required String deviceFingerprint,
    required List<GroupMessage> messages,
    bool isAdmin = true,
    String state = 'ready',
    BigInt? memberCount,
    String? inviteUri,
    String? creatorFingerprint,
    bool needsRejoin = false,
    String meshId = 'testmesh',
    String? label,
    String displayName = 'me',
    String? orgPubkey,
    List<String> memberPeerIds = const [],
    List<TypingMember> typingMembers = const [],
  }) =>
      GroupSnapshot(
        groupId: groupId,
        meshId: meshId,
        label: label,
        displayName: displayName,
        deviceFingerprint: deviceFingerprint,
        creatorFingerprint: creatorFingerprint ?? deviceFingerprint,
        isAdmin: isAdmin,
        state: state,
        memberCount: memberCount ?? BigInt.two,
        inviteUri: inviteUri,
        messages: messages,
        attachments: const [],
        dmOffers: const [],
        mesh: null,
        events: const [],
        needsRejoin: needsRejoin,
        orgPubkey: orgPubkey,
        memberPeerIds: memberPeerIds,
        typingMembers: typingMembers,
      );

  /// Public-channel `ChannelSnapshot`. Defaults mirror the channel
  /// tests' old private `_snapshot` helper (empty topic, `me` display
  /// name).
  static ChannelSnapshot channel({
    required String name,
    required String deviceFingerprint,
    required List<ChannelMessage> messages,
    String topic = '',
    String meshId = 'testmesh',
    String displayName = 'me',
  }) =>
      ChannelSnapshot(
        name: name,
        topic: topic,
        meshId: meshId,
        displayName: displayName,
        deviceFingerprint: deviceFingerprint,
        messages: messages,
        attachments: const [],
        dmOffers: const [],
        mesh: null,
        events: const [],
      );
}

/// Voice-call builders. The `active` call stamps a valid 32-byte base64
/// key and 8-byte nonce prefix so the orchestrator's `importCallKey`
/// succeeds when it auto-attaches (invalid key material would fail the
/// crypto import and sink the call).
class TestCalls {
  TestCalls._();

  /// Valid 32-byte zero key, base64-encoded (44 chars, decoded length 32).
  static const String keyB64 = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';

  /// Valid 8-byte zero nonce prefix, base64-encoded.
  static const String noncePrefixB64 = 'AAAAAAAAAAA=';

  /// An active, connected call.
  static ActiveCall active({
    required String callId,
    String direction = 'caller',
    BigInt? startedAtMs,
  }) =>
      ActiveCall(
        callId: callId,
        direction: direction,
        keyB64: keyB64,
        noncePrefixB64: noncePrefixB64,
        startedAtMs: startedAtMs ?? BigInt.zero,
      );
}
