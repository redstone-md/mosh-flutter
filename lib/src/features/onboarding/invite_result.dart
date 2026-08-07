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
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;


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
    // React `.invite-ready { gap: 8px; padding: 12px; border-radius: 12px;
    // border: 1px solid rgba(183,216,74,0.3); background: var(--moss-glow) }`
    // -- the whole result reads as a moss-tinted success block.
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
              // `.invite-ready-note { gap: 6px; color: var(--moss);
              // font-size: 11.5px; font-weight: 600 }`.
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
          // `.invite-code { padding: 10px 12px; border-radius: 8px;
          // background: var(--bg-0); color: var(--fg-2); font-family: mono;
          // font-size: 11px; line-height: 1.5; border: 1px solid --line }`.
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
        ],
      ),
    );
  }
}
