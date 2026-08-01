// Shared colored avatar circle with initials -- the Flutter rail idiom that
// mirrors React's `Avatar.tsx` (`mosh/src/features/private-dm/Avatar.tsx`,
// a text-only `<span>` with the initials). React's avatar has no size prop
// (CSS-fixed) and no color (the React rail renders text-only initials); the
// Flutter rail renders avatars as colored `CircleAvatar`s, so this widget
// adds the color while keeping the same initials algorithm. Both the
// initials (`avatarInitials`) and the color (`avatarColor`) live in
// `dm_helpers.dart` and are shared by every call site -- this widget just
// composes them (DRY): previously the colored-avatar-with-initials
// construction was duplicated inline across the DM / channel / group message
// rows, the org section rows, the offer rail, and the sessions list row.
// `radius` (default 16, the message-row size; org rows pass 12) covers the
// size variation; `foregroundColor`/`fontSize`/`fontWeight` are optional so
// each site keeps its exact text color, size, and weight.
library;

import 'package:flutter/material.dart';

import 'package:mosh/src/features/dm/dm_helpers.dart';

class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.name,
    this.radius = 16.0,
    this.foregroundColor,
    this.fontSize,
    this.fontWeight = FontWeight.w600,
  });

  final String name;
  final double radius;

  // When null, `CircleAvatar` derives the text color from [avatarColor]'s
  // brightness (`primaryColorLight`/`primaryColorDark` under Material 3).
  // The session list row and the offer rail pass an explicit white/black
  // contrast color to preserve their existing look.
  final Color? foregroundColor;

  // When null, `CircleAvatar` uses its default text size. Org rows pass 10
  // and the offer rail passes 13 to keep their original sizes.
  final double? fontSize;

  // Defaults to w600 (the message-row + org + sessions look). The offer rail
  // passes no weight so it inherits `CircleAvatar`'s `titleMedium` (w500),
  // matching the pre-refactor inline `Text(initials, style: TextStyle(
  // fontSize: 13))` which merged over the avatar's w500 default.
 final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: avatarColor(name),
      radius: radius,
      foregroundColor: foregroundColor,
      child: Text(
        avatarInitials(name),
        style: TextStyle(
          fontWeight: fontWeight,
          fontSize: fontSize,
        ),
      ),
    );
  }
}
