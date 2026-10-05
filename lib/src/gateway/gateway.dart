import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/message_deletion/types.dart';
import 'package:mosh/src/rust/attachment_runtime.dart' show VoiceMeta;

/// Abstraction over the conversation seam.
///
/// Implementations: `RealBridgeGateway` (delegates to the generated frb
/// functions) in the app, and `ScriptableGateway` (test/support/) in tests.
/// Widgets consume this interface, never a concrete class, so the wired
/// backend is a single Riverpod provider swap.
abstract interface class Gateway {
  Future<DeleteMessagesResult> deleteMessages(AnyConversationTarget target,
      {required List<String> messageIds, required DeleteScope scope});
  Future<void> rename(AnyConversationTarget target, {required String name});
  Future<void> resetName(AnyConversationTarget target);

  /// Reads [target]'s current state. The snapshot type follows the kind:
  /// a DM polls back a [SessionSnapshot], a channel a [ChannelSnapshot],
  /// a group a [GroupSnapshot].
  ///
  /// An implementation also implements [ConversationSnapshotReader] and hands
  /// itself to the target, which is what keeps the return type honest without
  /// a cast. The reader is not part of this interface: callers never see it.
  Future<S> poll<S>(ConversationTarget<S> target);

  /// Sends a text message to [target].
  ///
  /// The message's delivery status arrives with the next [poll], so the
  /// caller invalidates its snapshot after this returns instead of reading
  /// a result here.
  Future<void> send(AnyConversationTarget target, {required String body});

  /// Re-sends a failed outbound message of [target] by its id. Same
  /// delivery-status rule as [send]: read it from the next [poll].
  Future<void> retry(AnyConversationTarget target, {required String messageId});

  /// Sends a file to [target]. The caller reads the picked file into base64
  /// and adds a thumbnail or voice metadata when it has them. There is no
  /// result: the new attachment's id and hash arrive with the next [poll]
  /// (ADR 0024 drops the success payload).
  Future<void> sendAttachment(
    AnyConversationTarget target, {
    required String fileName,
    required String mime,
    required String dataBase64,
    String? thumbnailBase64,
    String? previewBase64,
    VoiceMeta? voice,
  });

  /// Starts the inbound transfer of one of [target]'s attachments. Progress
  /// surfaces in the next [poll] snapshot. Opening a finished file is
  /// client-side and has no Rust function.
  Future<void> downloadAttachment(AnyConversationTarget target,
      {required String attachmentId});

  /// Stops an in-flight transfer of one of [target]'s attachments.
  Future<void> cancelAttachment(AnyConversationTarget target,
      {required String attachmentId});

  /// Clears a DM offer from [target]'s offer list. The accept path dismisses
  /// the offer itself after acceptInvite; this is the decline path. A DM
  /// holds no offers, which is why the parameter is a [DmOfferHost].
  Future<void> dismissDmOffer(DmOfferHost<Object?> target,
      {required String offerId});

  /// Leaves [target]: closes the DM session, leaves the channel, or closes
  /// the group. The caller invalidates its snapshot and navigates away.
  Future<void> leave(AnyConversationTarget target);

  /// Tells the counterpart the local user is typing (DMs and groups; a
  /// channel has no counterpart to tell and this is a no-op for it).
  /// Fire-and-forget: the runtime throttles repeats to its own cadence, so
  /// the composer may call this on every keystroke.
  Future<void> typingSignal(AnyConversationTarget target);

  /// Reports the conversation is on screen, auto-triggering the DM read
  /// receipts for every not-yet-read counterpart message when the toggle
  /// is on. Groups and channels have no receipts in this slice, so this
  /// is a no-op for them.
  Future<void> markViewed(AnyConversationTarget target);
}
