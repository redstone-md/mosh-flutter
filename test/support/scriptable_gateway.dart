// The one test double for the Gateway conversation seam (ADR 0025).
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
// The Gateway interface is deliberately narrow -- the eight conversation
// methods widgets and controllers share -- so this double is too. The 1:1
// bridge mirrors (org, VPN, call, diagnostics, session setup, the joins and
// lists) live on the facade and are faked by `scriptable_bridge.dart`,
// which can share this double's conversation state.
//
// Anything not seeded falls back to the canned snapshots in
// gateway_snapshots.dart. Session state is real in-memory state: a DM send
// appends a message, and leave removes the conversation.

import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/gateway/gateway.dart';
import 'package:mosh/src/rust/attachment_runtime.dart' show VoiceMeta;
import 'package:mosh/src/rust/channel_runtime.dart' show ChannelSnapshot;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show SessionSnapshot;
import 'package:mosh/src/rust/private_group_runtime.dart' show GroupSnapshot;

import 'gateway_snapshots.dart';
import 'scripted_calls.dart';
import 'scripted_conversations.dart';

/// Every method on [Gateway]. Tests name a method through this enum, so a
/// typo is a compile error instead of a call that is never scripted.
enum GatewayMethod {
  poll,
  send,
  retry,
  sendAttachment,
  downloadAttachment,
  cancelAttachment,
  dismissDmOffer,
  leave,
  typingSignal,
  markViewed,
}

/// One recorded call to the conversation seam.
typedef GatewayCall = ScriptedCall<GatewayMethod>;

/// See the file header. Construct it, seed it, script it, assert on [calls].
class ScriptableGateway
    with ScriptedEngine<GatewayMethod>
    implements Gateway, ConversationSnapshotReader {
  ScriptableGateway({ScriptedConversations? conversations})
      : conversations = conversations ?? ScriptedConversations();

  /// The seeded conversations this double polls and mutates. Hand the same
  /// instance to a [ScriptableBridge] when a test wires both doubles, so the
  /// two surfaces see one runtime's state.
  final ScriptedConversations conversations;

  // ----------------------------------------------------------------- seeding

  /// Seed the DM sessions. Both surfaces read this state: the gateway's
  /// `poll` and, when a bridge double shares it, `listSessions`.
  void seedSessions(Iterable<SessionSnapshot> seeded) =>
      conversations.seedSessions(seeded);

  /// Seed the channels (the gateway's `poll`, and a shared bridge's
  /// `listChannels`).
  void seedChannels(Iterable<ChannelSnapshot> seeded) =>
      conversations.seedChannels(seeded);

  /// Seed the groups (the gateway's `poll`, and a shared bridge's
  /// `listGroups`).
  void seedGroups(Iterable<GroupSnapshot> seeded) =>
      conversations.seedGroups(seeded);

  // ------------------------------------------------- the conversation seam

  @override
  Future<S> poll<S>(ConversationTarget<S> target) => runScripted(
        GatewayMethod.poll,
        {'target': target},
        () => target.readSnapshot(this),
      );

  @override
  Future<SessionSnapshot> dmSnapshot(String sessionId) async {
    final snapshot = conversations.sessions[sessionId];
    if (snapshot == null) {
      throw Exception('poll: unknown sessionId "$sessionId"');
    }
    return snapshot;
  }

  @override
  Future<ChannelSnapshot> channelSnapshot(String name) async =>
      conversations.channels[name] ?? cannedChannelSnapshot(name: name);

  @override
  Future<GroupSnapshot> groupSnapshot(String groupId) async =>
      conversations.groups[groupId] ?? cannedGroupSnapshot(groupId: groupId);

  /// A DM send appends to the seeded session, so a screen that re-polls sees
  /// the new row. A channel or group send only records the call -- their
  /// snapshots stay whatever the test seeded.
  @override
  Future<void> send(AnyConversationTarget target, {required String body}) =>
      runScripted(GatewayMethod.send, {'target': target, 'body': body}, () {
        if (target is! DmTarget) return;
        final existing = conversations.sessions[target.id];
        if (existing == null) return;
        conversations.sessions[target.id] = withMessage(
          existing,
          body,
          'msg-${existing.messages.length + 1}',
          BigInt.from(DateTime.now().millisecondsSinceEpoch),
        );
      });

  @override
  Future<void> retry(AnyConversationTarget target,
          {required String messageId}) =>
      runScripted(GatewayMethod.retry,
          {'target': target, 'messageId': messageId}, () {});

  @override
  Future<void> sendAttachment(
    AnyConversationTarget target, {
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  }) =>
      runScripted(
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
      runScripted(GatewayMethod.downloadAttachment,
          {'target': target, 'attachmentId': attachmentId}, () {});

  @override
  Future<void> cancelAttachment(AnyConversationTarget target,
          {required String attachmentId}) =>
      runScripted(GatewayMethod.cancelAttachment,
          {'target': target, 'attachmentId': attachmentId}, () {});

  @override
  Future<void> dismissDmOffer(DmOfferHost<Object?> target,
          {required String offerId}) =>
      runScripted(GatewayMethod.dismissDmOffer,
          {'target': target, 'offerId': offerId}, () {});

  /// Leaving drops the conversation from the seeded state, so the next list
  /// call no longer returns it.
  @override
  Future<void> leave(AnyConversationTarget target) =>
      runScripted(GatewayMethod.leave, {'target': target}, () {
        switch (target) {
          case DmTarget():
            conversations.sessions.remove(target.id);
          case ChannelTarget():
            conversations.channels.remove(target.id);
          case GroupTarget():
            conversations.groups.remove(target.id);
        }
      });

  /// Records the typing signal; no seeded state changes (the counterpart's
  /// hint lives on the other side, which a test seeds directly).
  @override
  Future<void> typingSignal(AnyConversationTarget target) =>
      runScripted(GatewayMethod.typingSignal, {'target': target}, () {});

  /// Records the view mark; no seeded state changes (the receipts live on
  /// the other side, which a test seeds directly).
  @override
  Future<void> markViewed(AnyConversationTarget target) =>
      runScripted(GatewayMethod.markViewed, {'target': target}, () {});
}
