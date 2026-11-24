import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/focus_ring.dart';

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
            for (final action in actions) StartRow(action: action),
          ]),
        ),
      ],
    );
  }
}

/// The Start row card: an icon in the action's colour, a title, a line about
/// it and a chevron, on a row that takes the state layers of any control.
class StartRow extends StatelessWidget {
  const StartRow({super.key, required this.action});

  final StartAction action;

  static const radius = BorderRadius.all(Radius.circular(MoshRadius.large));

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final text = Theme.of(context).textTheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: radius,
        overlayColor: MoshState.layer(colors.onSurface),
        child: FocusRing(
          radius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: MoshSpace.s16),
            padding: const EdgeInsets.symmetric(
                horizontal: MoshSpace.s4, vertical: MoshSpace.s3),
            child: Row(children: [
              Icon(action.icon, size: MoshSpace.s6, color: action.accent),
              const SizedBox(width: MoshSpace.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(action.title, style: text.titleSmall),
                    Text(action.description, style: text.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: MoshSpace.s4),
              Icon(
                MoshIcons.chevronRight,
                size: MoshSpace.s4,
                color: colors.onSurfaceMuted,
                textDirection: Directionality.of(context),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
