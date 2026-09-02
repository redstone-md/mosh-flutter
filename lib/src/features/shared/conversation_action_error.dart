/// What a screen shows after a bridge action fails: the one classifier for a
/// caught [ConversationBridgeError], wherever it is caught. The callers are
/// listed once, in `docs/Architecture.md`.
///
/// A [ConversationBridgeError] from the seam is kept as its `kind`, and the
/// screen picks the wording from that kind alone: the runtime's `message` is
/// diagnostic text the UI never parses. Anything else that reaches the
/// screen -- the call module's own sentences, a non-bridge exception -- is
/// carried as ready-made text.
library;

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/rust/api/conversation_bridge.dart';
import 'package:mosh/src/util/format.dart' show readableError;

class ConversationActionError {
  const ConversationActionError.bridge(
      ConversationBridgeErrorKind this.kind, this.message);

  const ConversationActionError.text(this.message) : kind = null;

  /// Classifies whatever a Gateway call threw.
  factory ConversationActionError.of(Object error) =>
      error is ConversationBridgeError
          ? ConversationActionError.bridge(error.kind, error.message)
          : ConversationActionError.text(readableError(error));

  /// Null when the error did not come from the bridge.
  final ConversationBridgeErrorKind? kind;

  /// The runtime's diagnostic sentence, or the ready-made text. Shown only
  /// where the kind has nothing better to say.
  final String message;

  /// The sentence the screen shows. Exhaustive over the bridge taxonomy, so a
  /// new kind is a compile error here rather than a silent fallback.
  String describe(AppLocalizations l) => switch (kind) {
        null => message,
        ConversationBridgeErrorKind.invalidInput =>
          l.chatActionErrorInvalidInput(message),
        ConversationBridgeErrorKind.unavailable => l.chatActionErrorUnavailable,
        ConversationBridgeErrorKind.notReady => l.chatActionErrorNotReady,
        ConversationBridgeErrorKind.missingConversation =>
          l.chatActionErrorMissingConversation,
        ConversationBridgeErrorKind.missingMessage =>
          l.chatActionErrorMissingMessage,
        ConversationBridgeErrorKind.missingAttachment =>
          l.chatActionErrorMissingAttachment,
        ConversationBridgeErrorKind.transfer => l.chatActionErrorTransfer,
        ConversationBridgeErrorKind.persistence => l.chatActionErrorPersistence,
        ConversationBridgeErrorKind.needsRejoin => l.chatActionErrorNeedsRejoin,
        ConversationBridgeErrorKind.revoked => l.chatActionErrorRevoked,
        ConversationBridgeErrorKind.internal =>
          l.chatActionErrorInternal(message),
      };
}
