// Invite-result card, 1-в-1 with the React `InviteResult`
// (src/features/private-dm/NewSessionPanel.parts.tsx): a "ready" note row
// (check icon + note), the invite URI in a monospace `code` block (so the
// user can select + copy manually too -- matching React's `<code>`), and a
// Copy button whose label + icon flip with the [copied] flag.
//
// Extracted as its own widget so the chat-create step AND the future
// group-create step render the invite the same way (DRY: one result card).
// Stateless by design -- the parent owns the `copied` flag and the
// clipboard call (so the parent can reset `copied` when a new invite is
// created), exactly like React where `createState.copied` lives on the
// step component, not on `InviteResult`.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';

/// Renders an invite URI plus a Copy affordance, mirroring React
/// `InviteResult`.
///
/// The [note] is the localized "ready" line (e.g. `onboardInviteReady`).
/// The [uri] is shown in a monospace `SelectableText` so the user can
/// select it manually as well as use the Copy button. [copied] flips the
/// button label + icon between `onboardCopyLink` / `Icons.copy_outline`
/// and `onboardCopied` / `Icons.check`.
class InviteResult extends StatelessWidget {
  const InviteResult({
    super.key,
    required this.note,
    required this.uri,
    required this.copied,
    required this.onCopy,
  });

  /// Localized "ready" note (1-в-1 with React's `note` prop).
  final String note;

  /// The invite URI to display + copy (1-в-1 with React's `uri` prop).
  final String uri;

  /// Whether the URI was just copied -- flips the Copy button label/icon.
  final bool copied;

  /// Copy callback (1-в-1 with React's `onCopy`).
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
        color: theme.colorScheme.surfaceContainerLowest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(note, style: theme.textTheme.bodySmall),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: SelectableText(
              uri,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onCopy,
            icon: Icon(copied ? Icons.check : Icons.copy, size: 16),
            label: Text(copied ? l.onboardCopied : l.onboardCopyLink),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ],
      ),
    );
  }
}
