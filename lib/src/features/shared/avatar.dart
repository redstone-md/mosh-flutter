import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/plus/user_plus_badge.dart';

/// The plate of the avatar named [name]: one of the four of the palette,
/// the same one wherever and whenever that name is drawn.
Color avatarPlate(MoshColors colors, String name) {
  // FNV-1a over the name's code units: String.hashCode may differ per run.
  var hash = 0x811C9DC5;
  for (final unit in name.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return [
    colors.avatar1,
    colors.avatar2,
    colors.avatar3,
    colors.avatar4
  ][hash % 4];
}

/// The Avatar card: a person shows initials, a group and a channel show
/// their [sign]. Presence and the Mosh+ mark sit on the circle's edge, on
/// its diagonals.
class Avatar extends StatelessWidget {
  const Avatar(
      {super.key,
      required this.name,
      this.radius = 16.0,
      this.sign,
      this.online = false,
      this.plusIdentity,
      this.ownPlus = false});

  final String name;

  /// The glyph of a group or a channel, in place of initials.
  final IconData? sign;

  /// Marks a person whose connection is up.
  final bool online;
  final String? plusIdentity;
  final bool ownPlus;

  /// Circle radius. The card's sizes are 16 (compact, beside a message),
  /// 20 (small), 24 (medium, the chat list) and 32 (large, a profile).
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final text = Theme.of(context).textTheme;
    final initials = switch (radius) {
      >= 32 => text.headlineSmall!,
      >= 24 => text.titleMedium!,
      >= 20 => text.titleSmall!,
      _ => text.labelMedium!,
    };
    // How far the circle's edge is from the box's corner along a diagonal.
    final inset = radius * (1 - math.sqrt1_2);
    final presence = radius >= 32 ? MoshSpace.s4 : MoshSpace.s3;
    return Stack(clipBehavior: Clip.none, children: [
      CircleAvatar(
        backgroundColor: avatarPlate(colors, name),
        radius: radius,
        child: sign == null
            ? Text(avatarInitials(name),
                style: initials.copyWith(color: colors.onAvatar))
            : Icon(sign, size: radius, color: colors.onAvatar),
      ),
      if (online)
        PositionedDirectional(
          bottom: inset - presence / 2,
          end: inset - presence / 2,
          child: Tooltip(
            message: AppLocalizations.of(context)!.stateReady,
            child: Container(
              width: presence,
              height: presence,
              decoration: BoxDecoration(
                color: colors.success,
                shape: BoxShape.circle,
                border: Border.all(
                    color: colors.surface,
                    width: MoshBorder.thick,
                    strokeAlign: BorderSide.strokeAlignOutside),
              ),
            ),
          ),
        ),
      PositionedDirectional(
        top: inset - UserPlusBadge.size / 2,
        end: inset - UserPlusBadge.size / 2,
        child:
            UserPlusBadge(identity: plusIdentity, own: ownPlus, plated: true),
      ),
    ]);
  }
}
