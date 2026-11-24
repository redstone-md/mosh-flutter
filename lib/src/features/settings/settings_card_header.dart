import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart';

/// The header of a Settings card: the plate with the icon of the card's
/// subject, its title, a line about it and, at the right, [trailing]: the
/// one control that matters most (a switch, a retry, a spinner).
///
/// The plate keeps its place at the top however long the line runs; the
/// title alone, and [trailing], sit level with the plate's middle.
class SettingsCardHeader extends StatelessWidget {
  const SettingsCardHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsIcon(icon),
        const SizedBox(width: MoshSpace.s3),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: SettingsIcon.size),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                    header: true, child: Text(title, style: text.titleMedium)),
                if (subtitle case final line?)
                  Text(line, style: text.bodySmall),
              ],
            ),
          ),
        ),
        if (trailing case final tail?) ...[
          const SizedBox(width: MoshSpace.s3),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: SettingsIcon.size),
            child: Center(widthFactor: 1, child: tail),
          ),
        ],
      ],
    );
  }
}

/// The plate with the icon of a card's subject.
class SettingsIcon extends StatelessWidget {
  const SettingsIcon(this.icon, {super.key});

  final IconData icon;

  static const double size = MoshSpace.s10;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius:
              const BorderRadius.all(Radius.circular(MoshRadius.medium))),
      child: Icon(icon, color: colors.primary, size: MoshSpace.s5),
    );
  }
}
