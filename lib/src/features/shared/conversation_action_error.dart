import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/toasts/toaster.dart';
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
        ConversationBridgeErrorKind.payloadTooLarge =>
          l.chatActionErrorPayloadTooLarge,
        ConversationBridgeErrorKind.persistence => l.chatActionErrorPersistence,
        ConversationBridgeErrorKind.needsRejoin => l.chatActionErrorNeedsRejoin,
        ConversationBridgeErrorKind.revoked => l.chatActionErrorRevoked,
        ConversationBridgeErrorKind.permissionDenied =>
          l.chatNamePermissionDenied,
        ConversationBridgeErrorKind.internal =>
          l.chatActionErrorInternal(message),
      };
}

/// Reports a failed action as an error toast, for a screen that has no
/// error banner of its own. Resolve it before the action's first await:
/// it holds the app's toaster and strings rather than [context], so a
/// failure that lands after the screen closed still reaches the user.
void Function(Object error) actionErrorReporter(BuildContext context) {
  final l = AppLocalizations.of(context)!;
  final toaster = context.toaster;
  return (error) => toaster.show(ConversationActionError.of(error).describe(l),
      kind: ToastKind.error);
}
