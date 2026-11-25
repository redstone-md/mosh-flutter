import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';

/// The notice and the way out under a message that was not sent: "Not sent"
/// in the error colour and, where the message can be sent again, a Retry
/// button in the feed's own ink. The caller renders it only under a failed
/// message of the user's own.
///
/// The reason the network gave is not part of the line. It is the notice's
/// tooltip and its screen-reader label, `messageFailedWithError`; with no
/// reason both fall back to the notice itself. The Retry button carries its
/// own `Retry failed message` label.
class FailedMessageRetry extends StatelessWidget {
  const FailedMessageRetry({
    super.key,
    required this.deliveryError,
    required this.onRetry,
    required this.l,
    this.noticeColor,
  });

  /// The notice's ink where the error colour reads too faintly, such as on
  /// the band of a picked row; the error colour when left out.
  final Color? noticeColor;

  /// The failure detail the network reported, trimmed before use.
  final String? deliveryError;

  /// Sends the message again; null when it cannot be sent again, which
  /// leaves the notice alone.
  final VoidCallback? onRetry;

  /// Localized strings, built from `AppLocalizations.of(context)!` via the
  /// [toFailedMessageRetryL10n] extension at the call site.
  final FailedMessageRetryL10n l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = deliveryError?.trim();
    final reason = trimmed == null || trimmed.isEmpty ? null : trimmed;
    final notice = Text(
      l.messageFailedToSend,
      style: theme.textTheme.labelMedium!
          .copyWith(color: noticeColor ?? theme.colorScheme.error),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: MoshSpace.s1,
      children: [
        Flexible(
          child: Semantics(
            label: reason == null
                ? l.messageFailedToSend
                : l.messageFailedWithError(reason),
            container: true,
            excludeSemantics: true,
            child: reason == null
                ? notice
                : Tooltip(message: reason, child: notice),
          ),
        ),
        if (onRetry != null)
          TextButton(
            onPressed: onRetry,
            // Only the failure is red; the way out is in the feed's ink.
            style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurface),
            child: Semantics(
              label: l.retryFailedMessage,
              button: true,
              excludeSemantics: true,
              child: Text(l.retry),
            ),
          ),
      ],
    );
  }
}

class FailedMessageRetryL10n {
  const FailedMessageRetryL10n({
    required this.messageFailedToSend,
    required this.messageFailedWithError,
    required this.retryFailedMessage,
    required this.retry,
  });

  /// "Not sent" -- the notice.
  final String messageFailedToSend;

  /// "Failed: {error}" -- the status label when `deliveryError` is present.
  /// The `{error}` placeholder is the trimmed delivery error.
  final String Function(String error) messageFailedWithError;

  /// "Retry failed message" -- the retry button's semantics label.
  final String retryFailedMessage;

  /// "Retry" -- the retry button text.
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
