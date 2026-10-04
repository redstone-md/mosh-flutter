import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';

/// Inline chat error banner. Renders an error-container background row
/// with the error message plus an optional Retry button. The caller gates
/// the render: pass a non-null [onRetry] to show the retry button.
/// This widget does NOT decide when to appear -- the conversation screens
/// construct it only when `_chatError != null`.
class ChatErrorBanner extends StatelessWidget {
  const ChatErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
  });

  /// The error text to show.
  final String message;

  /// Optional retry callback. When non-null, a Retry button is shown;
  /// null hides the button.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    return Semantics(
      // `liveRegion` announces the
      // message to assistive tech and re-announces when it changes (the
      // ARIA alert role equivalent).
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        color: theme.colorScheme.errorContainer,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onErrorContainer),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onErrorContainer,
                  minimumSize: const Size(0, 40),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                // Refresh icon size 13 + the "Retry" label.
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh, size: 13),
                    const SizedBox(width: 4),
                    Text(l.chatErrorRetry),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
