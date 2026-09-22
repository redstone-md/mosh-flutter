// Invite-result card: a "ready" note row (check icon + note), the invite
// URI in a monospace selectable block (so the user can select + copy
// manually too), and a Copy button whose label + icon flip with the
// [copied] flag. An Open button lands in the conversation just created,
// so sharing the link and entering the chat do not need a detour via the
// rail.
//
// Extracted as its own widget so the chat-create step AND the future
// group-create step render the invite the same way (DRY: one result
// card). Stateless by design -- the parent owns the `copied` flag and the
// clipboard call, so the parent can reset `copied` when a new invite is
// created.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// Renders an invite URI plus a Copy affordance.
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
    required this.openLabel,
    required this.onOpen,
  });

  /// Localized "ready" note.
  final String note;

  /// The invite URI to display + copy.
  final String uri;

  /// Whether the URI was just copied -- flips the Copy button label/icon.
  final bool copied;

  /// Copy callback.
  final VoidCallback onCopy;

  /// Localized label of the Open button ("Open chat" / "Open group").
  final String openLabel;

  /// Opens the conversation this invite created.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    // Moss-tinted success block for the whole result card.
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MoshColors.moss.withValues(alpha: 0.3)),
        color: MoshColors.mossGlow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.check, size: 16, color: MoshColors.moss),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  note,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: MoshColors.moss,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: MoshColors.bg0,
              border: Border.all(color: MoshColors.line),
            ),
            child: SelectableText(
              uri,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.5,
                color: MoshColors.fg2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onCopy,
            icon: Icon(copied ? Icons.check : Icons.copy, size: 16),
            label: Text(copied ? l.onboardCopied : l.onboardCopyLink),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: onOpen,
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: Text(openLabel),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ],
      ),
    );
  }
}
