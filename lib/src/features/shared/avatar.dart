// Initials avatar.
//
// Every avatar is styled identically: a 32px circle on the
// [MoshColors.avatarSurface] plate with bold fg-1 initials on the
// labelMedium step -- there is no per-name tint. An earlier version had an
// `avatarColor(name)` hash that painted every sender a different Material
// hue, which is the most visible palette drift in the message list and the
// rail. The initials are static text, so they read in text ink, not in the
// moss accent that marks interactive/primary elements.
//
// `radius` stays a parameter because the org rows render a smaller circle;
// everything else about the chrome is fixed here.
library;

import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/conversation_helpers.dart';

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.radius = 16.0});

  final String name;

  /// Circle radius; 16 is the CSS-fixed 32px diameter.
  final double radius;

  @override
  Widget build(BuildContext context) {
    // ThemeData fills every text slot, so labelMedium is never null.
    final step = Theme.of(context).textTheme.labelMedium!;
    return Container(
      width: radius * 2,
      height: radius * 2,
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      child: CircleAvatar(
        backgroundColor: MoshColors.avatarSurface,
        radius: radius,
        child: Text(
          avatarInitials(name),
          style: step.copyWith(
            color: MoshColors.fg1,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.04 * step.fontSize!,
          ),
        ),
      ),
    );
  }
}
