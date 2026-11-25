import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/start_row.dart';

/// One way to start a conversation.
class StartAction {
  const StartAction({
    required this.icon,
    required this.accent,
    required this.title,
    required this.description,
    required this.onTap,
    this.encrypted = true,
  });

  final IconData icon;

  /// The conversation type's accent, as the rail shows it.
  final Color accent;
  final String title;
  final String description;
  final VoidCallback onTap;

  /// Whether what it opens is end-to-end encrypted. Every invite link
  /// opens a DM, group or organization, all admitted through MLS; only a
  /// public channel is open.
  final bool encrypted;
}

/// The actions as rows, grouped by whether what they open is encrypted.
class StartActionList extends StatelessWidget {
  const StartActionList({super.key, required this.actions});

  final List<StartAction> actions;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          icon: MoshIcons.lock,
          label: l.startGroupEncrypted,
          actions: [...actions.where((a) => a.encrypted)],
        ),
        const SizedBox(height: MoshSpace.s2),
        _Section(
          icon: MoshIcons.language,
          label: l.startGroupOpen,
          actions: [...actions.where((a) => !a.encrypted)],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(
      {required this.icon, required this.label, required this.actions});

  final IconData icon;
  final String label;
  final List<StartAction> actions;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              MoshSpace.s4, MoshSpace.s2, MoshSpace.s4, MoshSpace.s2),
          child: Row(children: [
            Icon(icon, size: MoshSpace.s4, color: colors.onSurfaceMuted),
            const SizedBox(width: MoshSpace.s2),
            Flexible(
              child: Semantics(
                  header: true,
                  child: Text(label,
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge!
                          .copyWith(color: colors.onSurfaceMuted))),
            ),
          ]),
        ),
        Material(
          color: colors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
              borderRadius: StartRow.radius,
              side: BorderSide(color: colors.outlineVariant)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final action in actions)
              StartRow(
                  icon: action.icon,
                  accent: action.accent,
                  title: action.title,
                  line: action.description,
                  onTap: action.onTap),
          ]),
        ),
      ],
    );
  }
}
