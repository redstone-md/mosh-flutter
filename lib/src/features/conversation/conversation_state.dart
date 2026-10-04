import 'package:mosh/src/features/shared/conversation_action_error.dart';
import 'package:mosh/src/rust/conversation/attachments.dart'
    show AttachmentDescriptor;

/// What one conversation screen is busy with.
class ConversationControllerState {
  const ConversationControllerState({
    this.sending = false,
    this.transferOperations = 0,
    this.offerBusy = false,
    this.offeredFingerprints = const <String>{},
    this.chatError,
    this.pendingOpen,
  });

  /// A file or voice send is in flight. Text admission has its own queue.
  final bool sending;

  /// How many attachment transfers are running.
  final int transferOperations;

  /// A DM invite to a peer is in flight.
  final bool offerBusy;

  /// Peers already invited to a DM from here, so the popover can say so.
  final Set<String> offeredFingerprints;

  /// The failure shown in the error banner above the conversation.
  final ConversationActionError? chatError;

  /// An attachment the user asked to open before its download finished.
  final AttachmentDescriptor? pendingOpen;

  bool get transferBusy => transferOperations > 0;

  ConversationControllerState copyWith({
    bool? sending,
    int? transferOperations,
    bool? offerBusy,
    Set<String>? offeredFingerprints,
    Object? chatError = _keep,
    Object? pendingOpen = _keep,
  }) =>
      ConversationControllerState(
        sending: sending ?? this.sending,
        transferOperations: transferOperations ?? this.transferOperations,
        offerBusy: offerBusy ?? this.offerBusy,
        offeredFingerprints: offeredFingerprints ?? this.offeredFingerprints,
        chatError: identical(chatError, _keep)
            ? this.chatError
            : chatError as ConversationActionError?,
        pendingOpen: identical(pendingOpen, _keep)
            ? this.pendingOpen
            : pendingOpen as AttachmentDescriptor?,
      );

  /// Marks "this argument was not passed", so copyWith can also set a
  /// nullable field back to null.
  static const _keep = Object();
}

/// The result of native admission. A refused send may restore an untouched
/// empty draft; successful completion never clears a later draft.
class ConversationSendOutcome {
  const ConversationSendOutcome({required this.sent, required this.body});

  final bool sent;
  final String body;

  static const nothingToSend = ConversationSendOutcome(sent: false, body: '');
}

/// The result of inviting a peer to a DM. [sessionId] is the new DM to open,
/// or null when the peer had already been invited.
class ConversationPeerDmResult {
  const ConversationPeerDmResult(this.sessionId);

  final String? sessionId;

  static const none = ConversationPeerDmResult(null);
}

/// What to do with an attachment the user opened before it had downloaded.
sealed class ConversationPendingOpen {
  const ConversationPendingOpen();
}

/// The file arrived: show it.
final class ConversationPendingShow extends ConversationPendingOpen {
  const ConversationPendingShow(this.descriptor, this.src);

  final AttachmentDescriptor descriptor;
  final String src;
}

/// The transfer failed or was cancelled: there is nothing to show.
final class ConversationPendingDropped extends ConversationPendingOpen {
  const ConversationPendingDropped();
}

/// Nothing was waiting, or it is still downloading.
final class ConversationPendingNone extends ConversationPendingOpen {
  const ConversationPendingNone();
}
