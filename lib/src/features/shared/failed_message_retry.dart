// Shared FailedMessageRetry row -- the 1-в-1 port of React's
// `FailedMessageRetry` (src/features/private-dm/MessageLists.tsx L434-468).
// React renders this row BELOW the message body (and below the
// AttachmentCard) inside `message-body`, ONLY when the message is an
// outbound (`outbound === message.from_fingerprint === ownFingerprint`)
// failed+retryable message with a non-null `message_id`. The channel +
// group message rows (`ChannelMessageRow` / `GroupMessageRow`) gate it with
// that same condition in their build methods and pass the localized strings
// + a `onRetry` callback; the DM row will reuse the same widget later
// (deferred to a DM-side atomic).
//
// The `onRetry` callback is wired by the row screens to the Gateway retry
// seam: React `retryChannelMessage` / `retryGroupMessage` (native-messaging-
// gateway.ts L494/500) -> Rust `channel_retry_message` /
// `private_group_retry_message` (src-tauri/src/lib.rs L780/922) -> frb
// `channel_api.retryMessage` / `group_api.retryMessage` -> Gateway
// `retryChannelMessage` / `retryGroupMessage`. Tapping Retry fires the
// seam then invalidates the conversation snapshot so the next poll
// re-renders the row delivery status (mirrors the AttachmentCard
// download/cancel wiring).

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';

/// The render-side retry row for an outbound failed+retryable message
/// (1-в-1 with React `FailedMessageRetry`). Renders an error line + a
/// compact Retry button. The caller gates the render condition
/// (`own && deliveryStatus == failed && retryable && messageId != null`)
/// and only constructs this widget when it holds -- this widget does NOT
/// re-check those conditions (it has no `message` reference, only the
/// `deliveryError` + `onRetry` + localized strings), matching React where
/// `FailedMessageRetry` is the gate itself but here the row already gated.
///
/// Accessibility: the whole row is a `Semantics` status node labeled by
/// `messageFailedWithError(deliveryError)` (or `messageFailedToSend` when
/// `deliveryError` is null/empty), mirroring React's `role=status
/// aria-label`. The Retry button carries its own `Retry failed message`
/// semantics label (React's `aria-label`).
class FailedMessageRetry extends StatelessWidget {
  const FailedMessageRetry({
    super.key,
    required this.deliveryError,
    required this.onRetry,
    required this.l,
  });

  /// The server-reported failure detail (React `message.delivery_error`).
  /// Trimmed before display (`deliveryError?.trim()`); null/empty falls
  /// back to the localized "Failed to send".
  final String? deliveryError;

  /// Retry callback. The row screens wire this to the Gateway retry seam
  /// (`retryChannelMessage` / `retryGroupMessage`); fire-and-forget then
  /// invalidate the conversation snapshot so the next poll re-renders.
  final VoidCallback onRetry;

  /// Localized strings (the React component inlined the literals "Failed
  /// to send" / "Retry" / "Retry failed message"; the Flutter port
  /// localizes them via ARB). Built from `AppLocalizations.of(context)!`
  /// via the [toFailedMessageRetryL10n] extension at the call site.
  final FailedMessageRetryL10n l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = deliveryError?.trim();
    final hasError = trimmed != null && trimmed.isNotEmpty;
    // React: `deliveryError?.trim() || "Failed to send"`.
    final errorText = hasError ? trimmed : l.messageFailedToSend;
    // React aria-label: `deliveryError ? "Failed: {error}" : "Failed to send"`.
    final statusLabel =
        hasError ? l.messageFailedWithError(trimmed) : l.messageFailedToSend;
    return Semantics(
      label: statusLabel,
      container: true,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                errorText,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                // React's `.chat-error-retry` is a small error-tinted
                // button; mirror with error foreground + dense padding.
                foregroundColor: theme.colorScheme.error,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Semantics(
                label: l.retryFailedMessage,
                button: true,
                excludeSemantics: true,
                child: Text(l.retry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Localized strings for [FailedMessageRetry]. An indirection rather than a
/// direct `AppLocalizations` dependency so the widget's surface is minimal
/// + testable without the full l10n delegate, and so the DM row (later
/// atomic) can reuse the widget with the same narrow interface. The row
/// screens build this from `AppLocalizations.of(context)!` via the
/// [toFailedMessageRetryL10n] extension.
class FailedMessageRetryL10n {
  const FailedMessageRetryL10n({
    required this.messageFailedToSend,
    required this.messageFailedWithError,
    required this.retryFailedMessage,
    required this.retry,
  });

  /// "Failed to send" (React inline literal, the `<span>` fallback text).
  final String messageFailedToSend;

  /// "Failed: {error}" (React aria-label when `deliveryError` is present).
  /// The `{error}` placeholder is the trimmed delivery error.
  final String Function(String error) messageFailedWithError;

  /// "Retry failed message" (React button `aria-label`).
  final String retryFailedMessage;

  /// "Retry" (React button text).
  final String retry;
}

/// Builds a [FailedMessageRetryL10n] from the resolved [AppLocalizations].
/// Keeps the call sites terse: `l.toFailedMessageRetryL10n()`.
extension FailedMessageRetryL10nX on AppLocalizations {
  FailedMessageRetryL10n toFailedMessageRetryL10n() => FailedMessageRetryL10n(
        messageFailedToSend: messageFailedToSend,
        messageFailedWithError: messageFailedWithError,
        retryFailedMessage: retryFailedMessage,
        retry: messageRetry,
      );
}
