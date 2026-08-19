// Initials avatar -- the Flutter port of React's `Avatar.tsx` + the
// `.avatar` rule in chat-pane.css.
//
// React styles every avatar identically (`.avatar { width: 32px; height:
// 32px; border-radius: 50%; background: #2d3f23; color: var(--moss);
// font-size: 11px; font-weight: 700; letter-spacing: 0.04em }`) -- there is
// no per-name tint. The Flutter port had grown a `avatarColor(name)` hash
// that painted every sender a different Material hue, which is the most
// visible palette drift in the message list and the rail.
//
// `radius` stays a parameter because the org rows render a smaller circle;
// everything else about the chrome is CSS-fixed and therefore fixed here.
library;

import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/conversation_helpers.dart';

/// React `.avatar` background -- a fixed dark moss, not a per-name hash.
const Color kAvatarBackground = Color(0xFF2D3F23);

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.radius = 16.0});

  final String name;

  /// Circle radius; 16 is React's CSS-fixed 32px diameter.
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: kAvatarBackground,
      radius: radius,
      child: Text(
        avatarInitials(name),
        style: const TextStyle(
          color: MoshColors.moss,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.04 * 11,
        ),
      ),
    );
  }
}
