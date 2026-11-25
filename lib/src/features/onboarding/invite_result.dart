import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// At most two URI lines, with the complete link available to Copy.
/// An empty note omits repeated status copy in a saved invitation list.
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
    this.busy = false,
  });

  final String note;
  final String uri;
  final bool copied;
  final VoidCallback onCopy;
  final String openLabel;
  final VoidCallback onOpen;
  final VoidCallback? onReplace;
  final String? replaceLabel;
  final String? footer;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (note.isNotEmpty) ...[
        _ReadyNote(title: l.onboardInviteReadyTitle, note: note),
        const SizedBox(height: 20),
      ],
      _LinkField(
          label: l.onboardInviteLinkLabel,
          uri: uri,
          onCopy: busy ? null : onCopy),
      const SizedBox(height: 14),
      ..._actions(context, l),
      if (footer case final text?) _footer(context, text),
    ]);
  }

  Size get _buttonSize =>
      note.isEmpty ? const Size(0, 40) : const Size.fromHeight(48);

  Widget _copy(AppLocalizations l, ButtonStyle style) => OutlinedButton.icon(
        onPressed: busy ? null : onCopy,
        icon: Icon(copied ? MoshIcons.check : MoshIcons.copy, size: 18),
        label: Text(copied ? l.onboardCopied : l.onboardCopyLink),
        style: style,
      );

  Widget _open(ButtonStyle style) => FilledButton.icon(
        onPressed: busy ? null : onOpen,
        icon: const Icon(MoshIcons.forward, size: 18),
        label: Text(openLabel),
        style: style,
      );

  List<Widget> _actions(BuildContext context, AppLocalizations l) {
    final theme = Theme.of(context);
    final style = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(_buttonSize),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
      textStyle: WidgetStatePropertyAll(
          theme.filledButtonTheme.style?.textStyle?.resolve({}) ??
              theme.textTheme.labelLarge),
      visualDensity: VisualDensity.standard,
    );
    final secondary = style.copyWith(
      foregroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? null
              : MoshColors.of(context).onSurface),
    );
    if (onReplace case final replace?) {
      return [
        Wrap(spacing: 12, runSpacing: 8, children: [
          _copy(l, secondary),
          _open(style),
          OutlinedButton.icon(
              onPressed: busy ? null : replace,
              icon: const Icon(MoshIcons.refresh, size: 18),
              label: Text(replaceLabel ?? l.onboardChatRecreate),
              style: secondary),
        ])
      ];
    }
    return [_copy(l, secondary), const SizedBox(height: 12), _open(style)];
  }

  Widget _footer(BuildContext context, String text) => Column(children: [
        const SizedBox(height: 20),
        Divider(height: 1, color: MoshColors.of(context).outlineVariant),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(MoshIcons.lock,
              size: 20, color: MoshColors.of(context).onSurfaceMuted),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: MoshColors.of(context).onSurfaceMuted,
                      height: 1.5))),
        ]),
      ]);
}

class _ReadyNote extends StatelessWidget {
  const _ReadyNote({required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: colors.secondaryContainer,
          border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(MoshIcons.success, size: 32, color: colors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: text.titleSmall?.copyWith(color: colors.primary)),
                const SizedBox(height: 4),
                Text(note,
                    style: text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant, height: 1.45)),
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
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: colors.onSurfaceVariant)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: colors.surfaceContainerLowest,
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(children: [
            Expanded(
              child: SelectableText(
                uri,
                maxLines: 2,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall!
                    .copyWith(color: colors.onSurface),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onCopy,
              tooltip: l.onboardCopyLink,
              icon: const Icon(MoshIcons.copy, size: 18),
            ),
          ]),
        ),
      ],
    );
  }
}
