import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart';

/// Shares Connection's native ListTile geometry across settings headers.
class SettingsCardHeader extends StatelessWidget {
  const SettingsCardHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Widget title;
  final Widget subtitle;

  static const double iconTextGap = 10;

  static ListTileThemeData layout(BuildContext context) =>
      ListTileTheme.of(context).copyWith(
        horizontalTitleGap: iconTextGap,
        minLeadingWidth: 44,
        titleAlignment: ListTileTitleAlignment.center,
        visualDensity: VisualDensity.standard,
      );

  @override
  Widget build(BuildContext context) => ListTileTheme(
        data: layout(context),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: SettingsIcon(icon),
          title: title,
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: subtitle,
          ),
        ),
      );
}

class SettingsIcon extends StatelessWidget {
  const SettingsIcon(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
            color: MoshColors.mossGlow,
            borderRadius: MoshShapes.conversationRow),
        child: Icon(icon, color: MoshColors.moss, size: 24),
      );
}
