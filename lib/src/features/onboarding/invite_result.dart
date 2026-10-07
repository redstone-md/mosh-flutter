import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// A created invite: a ready note, the link with a copy button, then the
/// way into the new conversation.
///
/// [onReplace] adds a button that makes a fresh invite next to Copy.
/// [footer] explains what the link allows, under a rule.
class InviteResult extends StatelessWidget {
  const InviteResult({
    super.key,
    required this.note,
    required this.uri,
    required this.copied,
    required this.onCopy,
    required this.openLabel,
    required this.onOpen,
    this.onReplace,
    this.replaceLabel,
    this.footer,
  });

  /// What to do with the link, under the "Invite ready" title.
  final String note;
  final String uri;

  /// Whether the link was just copied; flips the Copy button.
  final bool copied;
  final VoidCallback onCopy;

  /// "Open chat" / "Open group".
  final String openLabel;
  final VoidCallback onOpen;

  final VoidCallback? onReplace;
  final String? replaceLabel;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final copy = OutlinedButton.icon(
      onPressed: onCopy,
      icon: Icon(copied ? Icons.check : Icons.copy_outlined, size: 18),
      label: Text(copied ? l.onboardCopied : l.onboardCopyLink),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReadyNote(title: l.onboardInviteReadyTitle, note: note),
        const SizedBox(height: 20),
        _LinkField(label: l.onboardInviteLinkLabel, uri: uri, onCopy: onCopy),
        const SizedBox(height: 14),
        if (onReplace case final replace?)
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: replace,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(replaceLabel ?? ''),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: copy),
          ])
        else
          copy,
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onOpen,
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: Text(openLabel),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        if (footer case final text?) ...[
          const SizedBox(height: 20),
          const Divider(height: 1, color: MoshColors.line),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.lock_outline, size: 20, color: MoshColors.fg3),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: MoshColors.fg3, height: 1.5)),
            ),
          ]),
        ],
      ],
    );
  }
}

class _ReadyNote extends StatelessWidget {
  const _ReadyNote({required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: MoshColors.mossGlow,
          border: Border.all(color: MoshColors.moss.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.check_circle_outline,
              size: 32, color: MoshColors.moss),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: text.titleSmall?.copyWith(
                        color: MoshColors.moss, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(note,
                    style: text.bodySmall
                        ?.copyWith(color: MoshColors.fg2, height: 1.45)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// The link in full, selectable, with a copy button inside the field.
class _LinkField extends StatelessWidget {
  const _LinkField(
      {required this.label, required this.uri, required this.onCopy});

  final String label;
  final String uri;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: MoshColors.fg2)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: MoshColors.bg0,
            border: Border.all(color: MoshColors.lineStrong),
          ),
          child: Row(children: [
            Expanded(
              child: SelectableText(
                uri,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  height: 1.5,
                  color: MoshColors.fg1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onCopy,
              tooltip: l.onboardCopyLink,
              icon: const Icon(Icons.copy_outlined, size: 18),
            ),
          ]),
        ),
      ],
    );
  }
}
