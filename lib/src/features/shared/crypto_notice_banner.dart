// Shared crypto notice banner for the channel + group chat screens. The
// public (channel) and group (encrypted) variants differ only in the icon
// (`Icons.lock` for group, `Icons.hash` for public) and the i18n strings.
// This single DRY widget parameterizes the icon + accent + strings so the
// channel (public) and group (encrypted) variants are just different ctor
// call sites.
//
// Position: the banner sits at the TOP of the body Column, ABOVE
// ConversationTools, and is NOT part of the message list.
//
// Accessibility: the banner is wrapped in `Semantics(label: title,
// container: true, excludeSemantics: true)` so the screen reader announces
// the whole banner as one labeled unit (the title) rather than reading the
// icon + title + body as three separate nodes.
//
// Styling: a flex row with a tinted background, a 32x32 rounded icon
// container, a bold title, and a muted body. The accent (border +
// icon-tint + icon-foreground) is passed in so the group variant uses the
// moss-glow green and the public variant uses the info blue. Material
// widgets (Container/Row) so it reads as a notice banner, not a chat bubble.
library;

import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// Tinted crypto notice banner. Renders an icon in a rounded tinted square
/// + a bold title + a muted body, all inside a bordered/tinted section. The
/// `accent` drives the border color, the icon-container background, and
/// the icon foreground color.
///
/// The whole section is wrapped in a `Semantics(container: true,
/// excludeSemantics: true, label: title)` so a screen reader announces the
/// banner as one unit labeled by the title.
class CryptoNoticeBanner extends StatelessWidget {
  const CryptoNoticeBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });

  /// The icon glyph (`Icons.lock` for group, `Icons.hash` for public).
  /// Material equivalents: `Icons.lock` (group), `Icons.tag` (public hash).
  final IconData icon;

  /// Bold title line.
  final String title;

  /// Muted body paragraph.
  final String body;

  /// Accent color driving the border + icon-container tint + icon
  /// foreground. Group = moss green, public = info blue.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    // The group and public variants differ only in the third
    // decimal of the tint alphas, so one set covers both.
    final bg = accent.withValues(alpha: 0.04);
    final border = accent.withValues(alpha: 0.18);
    final iconBg = accent.withValues(alpha: 0.14);
    return Semantics(
      label: title,
      container: true,
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(22, 14, 22, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A 32x32 rounded tinted square holding
            // the 18px icon, centered.
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title: 12.5px/700, fg-1.
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: MoshColors.fg1,
                    ),
                  ),
                  // Body: fg-3, 11.5px/1.5, 3px top margin.
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: MoshColors.fg3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
