import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

import 'focus_ring.dart';

/// The Start row card: an icon in its own colour, a title, a line about
/// it and a chevron, on a row that takes the state layers of any control.
class StartRow extends StatelessWidget {
  const StartRow({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    required this.line,
    required this.onTap,
  });

  final IconData icon;

  /// The colour the icon is drawn in.
  final Color accent;
  final String title;
  final String line;
  final VoidCallback onTap;

  static const radius = BorderRadius.all(Radius.circular(MoshRadius.large));

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final text = Theme.of(context).textTheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        overlayColor: MoshState.layer(colors.onSurface),
        child: FocusRing(
          radius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: MoshSpace.s16),
            padding: const EdgeInsets.symmetric(
                horizontal: MoshSpace.s4, vertical: MoshSpace.s3),
            child: Row(children: [
              Icon(icon, size: MoshSpace.s6, color: accent),
              const SizedBox(width: MoshSpace.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: text.titleSmall),
                    Text(line, style: text.bodySmall),
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
