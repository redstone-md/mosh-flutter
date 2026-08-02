// ChatErrorBanner -- the 1-1 Flutter port of React's `ChatError`
// (mosh/src/features/private-dm/private-dm-screen.tsx L506-525), the inline
// error banner React renders at the top of the chat-pane when there is a
// send error AND the conversation is not on the welcome/empty state
// (private-dm-screen.tsx L337-341). React renders:
//   <div className="inline-error chat-error" role="alert">
//     <span>{message}</span>
//     {onRetry ? <button className="chat-error-retry" onClick={onRetry}>
//       <IconRefresh size={13} />Retry</button> : null}
//   </div>
// The Flutter port mirrors that single-row banner: an error-tinted
// Container, the message text, and an OPTIONAL Retry button (only when
// `onRetry` is non-null). The Retry label is localized via ARB
// (`chatErrorRetry`) -- not the React inline literal -- so the banner
// matches the rest of the localized UI.

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';

/// Inline chat error banner -- 1-1 with React `ChatError`. Renders an
/// `inline-error chat-error`-style row (error-container background + the
/// error message) plus an optional Retry button. The caller gates the
/// render: pass a non-null [onRetry] to show the retry button, matching
/// React's `{onRetry ? <button/> : null}`. This widget does NOT decide
/// when to appear -- the conversation screens construct it only when
/// `_chatError != null` (mirrors React's `{error ? <ChatError/> : null}`).
class ChatErrorBanner extends StatelessWidget {
  const ChatErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
  });

  /// The error text to show (React `ChatError` `message` prop).
  final String message;

  /// Optional retry callback. When non-null, a Retry button is shown
  /// (React: `onRetry ? <button/> : null`). Null hides the button, mirroring
  /// `canRetrySend ? retryFailedSend : undefined` from the screen.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    return Semantics(
      // React `role="alert"` on the banner root -- `liveRegion` is the
      // Flutter equivalent of the ARIA alert role: it announces the
      // message to assistive tech and re-announces when it changes.
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
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                // React's IconRefresh size 13 + the "Retry" label.
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
