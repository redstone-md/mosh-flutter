// Shared crypto notice banner for the channel + group chat screens -- the
// 1-в-1 port of React's `GroupNotice` / `PublicNotice`
// (src/features/private-dm/ActiveChatPanes.tsx ~L420-445). The two React
// components are structurally identical (`<section className="crypto-banner
// crypto-banner-{group|public}">` with a `crypto-icon` div + a div holding
// `<strong>{noticeTitle}</strong>` + `<p>{noticeBody}</p>`), differing only
// in the lucide icon (`IconLock` for group, `IconHash` for public) and the
// i18n strings. This single DRY widget parameterizes the icon + accent +
// strings so the channel (public) and group (encrypted) variants are just
// different ctor call sites.
//
// Position: React wires the banner as the `afterHeader` slot of the active
// chat header (ActiveChatHeader.tsx L42-72), which renders
// `header -> afterHeader -> MobileSearch -> ConversationTools -> list`. The
// Flutter screens use the AppBar as the header, so the banner sits at the
// TOP of the body Column, ABOVE ConversationTools (matching the React
// afterHeader-before-tools order). The banner is NOT part of the message
// list.
//
// Accessibility: React sets `aria-label={noticeTitle}` on the section. This
// wraps the banner in `Semantics(label: title, container: true,
// excludeSemantics: true)` so the screen reader announces the whole banner
// as one labeled unit (the title) rather than reading the icon + title +
// body as three separate nodes.
//
// Styling: mirrors React's `.crypto-banner` (chat-pane.css L111-130) +
// `.crypto-banner-{group,public}` (desktop-shell.css L519-538): a flex row
// with a tinted background, a 32x32 rounded icon container, a bold title,
// and a muted body. The accent (border + icon-tint + icon-foreground) is
// passed in so the group variant uses the moss-glow green and the public
// variant uses the info blue, matching React's per-kind CSS. Material
// widgets (Container/Row) so it reads as a notice banner, not a chat bubble.
library;

import 'package:flutter/material.dart';

/// Tinted crypto notice banner -- 1-в-1 with React `GroupNotice` /
/// `PublicNotice`. Renders an icon in a rounded tinted square + a bold
/// title + a muted body, all inside a bordered/tinted section. The
/// `accent` drives the border color, the icon-container background, and
/// the icon foreground color (mirrors React's `.crypto-banner-{kind}` +
/// `.crypto-banner-{kind} .crypto-icon` CSS overrides).
///
/// The whole section is wrapped in a `Semantics(container: true,
/// excludeSemantics: true, label: title)` so a screen reader announces the
/// banner as one unit labeled by the title (matching React's
/// `aria-label={noticeTitle}` on the `<section>`).
class CryptoNoticeBanner extends StatelessWidget {
  const CryptoNoticeBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });

  /// The icon glyph (React: `IconLock` for group, `IconHash` for public).
  /// Material equivalents: `Icons.lock` (group), `Icons.tag` (public hash).
  final IconData icon;

  /// Bold title line (React `<strong>{noticeTitle}</strong>`).
  final String title;

  /// Muted body paragraph (React `<p>{noticeBody}</p>`).
  final String body;

  /// Accent color driving the border + icon-container tint + icon
  /// foreground. Mirrors React's per-kind `.crypto-banner-{kind}` border +
  /// `.crypto-icon` background/foreground. Group = moss green, public =
  /// info blue.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // React's `.crypto-banner` background is a very faint tint of the
    // accent (rgba(...,0.04-0.06)); approximate with 6% opacity over the
    // theme surface so it reads on light + dark themes.
    final bg = accent.withValues(alpha: 0.06);
    final border = accent.withValues(alpha: 0.25);
    final iconBg = accent.withValues(alpha: 0.18);
    return Semantics(
      label: title,
      container: true,
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // React's `.crypto-icon`: a 32x32 rounded tinted square holding
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
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor, height: 1.5),
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
