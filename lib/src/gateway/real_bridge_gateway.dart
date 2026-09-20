// S5: the slice-one moment-of-truth backend (ADR 0013 close-out).
//
// RealBridgeGateway implements the conversation seam (the narrowed
// `Gateway`, ADR 0025): it is a thin pass-through with one conversion --
// the six shared conversation actions go over the bridge as a typed
// `BridgeConversationRef`, and the bridge function picks the runtime
// (ADR 0024). `dismissDmOffer` keeps its switch -- a DM has no offer list,
// so only two kinds answer it (ADR 0017). The 1:1 mirrors that used to
// share this class now live in `bridge_facade.dart`.
//
// Lifecycle: every method assumes `RustLib.init()` has run (main.dart calls
// it on startup; the integration test calls it explicitly). Calling before
// init throws via the generated `RustLib.instance.api` indirection -- the
// behaviour a Dart double cannot reproduce.

import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/gateway/gateway.dart';
// The six shared conversation actions (ADR 0024): functions are prefixed
// (they collide with the interface method names); the ref/payload types
// come in unqualified, like the diagnostics types.
import 'package:mosh/src/rust/api/conversation.dart'
    show BridgeAttachmentPayload, BridgeConversationKind, BridgeConversationRef;
import 'package:mosh/src/rust/api/conversation.dart' as conversation_api
    show
        cancelAttachment,
        downloadAttachment,
        leave,
        markViewed,
        retry,
        send,
        sendAttachment,
        typingSignal;
// channel.dart and private_group.dart each define a `poll` free function, so
// the two imports MUST use distinct prefixes to avoid collision; the
// snapshot types come in unqualified from their *_runtime.dart modules.
import 'package:mosh/src/rust/api/channel.dart' as channel_api
    show dismissDmOffer, poll;
import 'package:mosh/src/rust/api/private_group.dart' as group_api
    show dismissDmOffer, poll;
import 'package:mosh/src/rust/api/private_dm.dart' as api show pollSession;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart'
    show SessionSnapshot;
import 'package:mosh/src/rust/attachment_runtime.dart';
import 'package:mosh/src/rust/channel_runtime.dart';
import 'package:mosh/src/rust/private_group_runtime.dart';

/// Real `mosh_core`-backed conversation seam. See file doc for the lifecycle
/// contract.
class RealBridgeGateway implements Gateway, ConversationSnapshotReader {
  // --------------------------------------------------------------------
  // The conversation seam. Typed polls keep one read per kind; the six
  // shared actions convert the target to a typed ref once and call the one
  // shared bridge function (ADR 0024) -- the kind dispatch lives in the
  // bridge, beside the runtime handles it picks between.
  // --------------------------------------------------------------------

  /// The conversation a shared action addresses, as the bridge names it:
  /// kind + id in one typed value. The adapter's whole kind decision; the
  /// bridge function owns the dispatch from here (ADR 0024).
  static BridgeConversationRef _bridgeRef(AnyConversationTarget target) =>
      BridgeConversationRef(
        kind: switch (target.kind) {
          ConversationKind.dm => BridgeConversationKind.dm,
          ConversationKind.channel => BridgeConversationKind.channel,
          ConversationKind.group => BridgeConversationKind.group,
        },
        id: target.id,
      );

  @override
  Future<S> poll<S>(ConversationTarget<S> target) => target.readSnapshot(this);

  @override
  Future<SessionSnapshot> dmSnapshot(String sessionId) =>
      api.pollSession(sessionId: sessionId);

  @override
  Future<ChannelSnapshot> channelSnapshot(String name) =>
      channel_api.poll(name: name);

  @override
  Future<GroupSnapshot> groupSnapshot(String groupId) =>
      group_api.poll(groupId: groupId);

  @override
  Future<void> send(AnyConversationTarget target, {required String body}) =>
      conversation_api.send(reference: _bridgeRef(target), body: body);

  @override
  Future<void> retry(AnyConversationTarget target,
          {required String messageId}) =>
      conversation_api.retry(
          reference: _bridgeRef(target), messageId: messageId);

  @override
  Future<void> sendAttachment(
    AnyConversationTarget target, {
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    VoiceMeta? voice,
  }) =>
      conversation_api.sendAttachment(
        reference: _bridgeRef(target),
        payload: BridgeAttachmentPayload(
          fileName: fileName,
          mime: mime,
          dataBase64: dataBase64,
          thumbnailBase64: thumbnailBase64,
          voice: voice,
        ),
      );

  @override
  Future<void> downloadAttachment(AnyConversationTarget target,
          {required String attachmentId}) =>
      conversation_api.downloadAttachment(
          reference: _bridgeRef(target), attachmentId: attachmentId);

  @override
  Future<void> cancelAttachment(AnyConversationTarget target,
          {required String attachmentId}) =>
      conversation_api.cancelAttachment(
          reference: _bridgeRef(target), attachmentId: attachmentId);

  @override
  Future<void> dismissDmOffer(DmOfferHost<Object?> target,
          {required String offerId}) =>
      switch (target) {
        ChannelTarget(:final id) =>
          channel_api.dismissDmOffer(name: id, offerId: offerId),
        GroupTarget(:final id) =>
          group_api.dismissDmOffer(groupId: id, offerId: offerId),
      };

  @override
  Future<void> leave(AnyConversationTarget target) =>
      conversation_api.leave(reference: _bridgeRef(target));

  @override
  Future<void> typingSignal(AnyConversationTarget target) =>
      conversation_api.typingSignal(reference: _bridgeRef(target));

  @override
  Future<void> markViewed(AnyConversationTarget target) =>
      conversation_api.markViewed(reference: _bridgeRef(target));
}
