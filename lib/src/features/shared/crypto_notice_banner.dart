// Shared informational/status banner above conversation tools. Persistence
// belongs to its caller; the close action is optional and separately
// accessible from the title/body announcement.
library;

import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// Tinted crypto notice banner. Renders an icon in a rounded tinted square
/// + a bold title + a muted body, all inside a bordered/tinted section. The
/// `accent` drives the border color, the icon-container background, and
/// the icon foreground color.
///
/// The title and body are one semantic node; the close button is another.
class CryptoNoticeBanner extends StatelessWidget {
  const CryptoNoticeBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
    this.onDismiss,
    this.dismissing = false,
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

  final Future<void> Function()? onDismiss;
  final bool dismissing;

  @override
  Widget build(BuildContext context) {
    // The group and public variants differ only in the third
    // decimal of the tint alphas, so one set covers both.
    final bg = accent.withValues(alpha: 0.04);
    final border = accent.withValues(alpha: 0.18);
    final iconBg = accent.withValues(alpha: 0.14);
    return Semantics(
      container: true,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          // Concentric radius: inner icon plate 8 + vertical inset 12 = 20.
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A 32x32 rounded tinted square holding
            // the 18px icon, centered.
            ExcludeSemantics(
                child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: accent),
            )),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                label: '$title. $body',
                excludeSemantics: true,
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
            ),
            if (onDismiss != null) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: dismissing ? null : onDismiss,
                tooltip: AppLocalizations.of(context)!.dialogClose,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18, color: MoshColors.fg3),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
