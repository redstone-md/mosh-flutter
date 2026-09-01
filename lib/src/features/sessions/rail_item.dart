// The rail row chrome, ported from `.rail-item` in desktop-shell.css.
//
// The Flutter rail has no collapse mode (it is a fixed pane), so the target
// is React's EXPANDED rail throughout: `.session-rail-expanded .rail-item`
// is a 48px row at radius 12 with 12px side padding and a 10px gap, holding
// a leading avatar/icon, a two-line `.rail-text` block (12.5px/1.1 --fg-1
// over 10.5px/1.1 --fg-4) and the unread badge. Active is
// `box-shadow: inset 0 0 0 2px <accent>`.
//
// The per-kind tints are CSS too: a DM row is plain --bg-2 with --fg-2
// glyphs, `.rail-channel` is rgba(--info, 0.10) with --info, and
// `.rail-group` is --moss-glow with --moss. The active ring follows the
// tint (--info for channels, --moss otherwise).
//
// The expanded rail hides `.rail-dot` and `.rail-admin-crown` outright, so
// those never render here. `.rail-offer-badge` is the exception: it belongs
// to the offer row alone, which renders it in [RailItem]'s trailing slot
// next to the dismiss X (see `rail_entry.dart`).
library;

import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// Which `.rail-item` variant a row is: the tint and the active ring both
/// follow from it.
enum RailItemKind { dm, channel, group }

/// React `.session-rail-expanded .rail-item { height: 48px }`.
const double kRailItemHeight = 48;

/// React `.rail-list { gap: 8px }`.
const double kRailListGap = 8;

/// React `.session-rail-expanded { padding: 12px; gap: 12px }`.
const double kRailPadding = 12;

/// React `.desktop-body-rail-expanded { grid-template-columns: 268px ... }`.
const double kRailWidth = 268;

extension on RailItemKind {
  Color get background => switch (this) {
        RailItemKind.dm => MoshColors.bg2,
        RailItemKind.channel => MoshColors.info.withValues(alpha: 0.10),
        RailItemKind.group => MoshColors.mossGlow,
      };

  /// The glyph colour, and the colour of the active inset ring.
  Color get accent => switch (this) {
        RailItemKind.dm => MoshColors.fg2,
        RailItemKind.channel => MoshColors.info,
        RailItemKind.group => MoshColors.moss,
      };

  Color get ring =>
      this == RailItemKind.channel ? MoshColors.info : MoshColors.moss;
}

/// One rail row. [leading] is the avatar (DMs, offers) or the 18px glyph
/// (channels, groups); [title]/[subtitle] fill `.rail-text`; [trailing]
/// carries the unread badge and, for offers, the dismiss control.
class RailItem extends StatelessWidget {
  const RailItem({
    super.key,
    required this.kind,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.active = false,
    this.onTap,
  });

  final RailItemKind kind;
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(active ? 14 : 12);
    return Padding(
      padding: const EdgeInsets.only(bottom: kRailListGap),
      child: Material(
        color: kind.background,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          // `.rail-item:hover { background: var(--bg-3) }`.
          hoverColor: MoshColors.bg3,
          child: Container(
            height: kRailItemHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: radius,
              // `inset 0 0 0 2px <accent>` — an inside ring, so a border
              // rather than a Flutter (outset-only) BoxShadow.
              border: active ? Border.all(color: kind.ring, width: 2) : null,
            ),
            child: Row(
              children: <Widget>[
                IconTheme.merge(
                  data: IconThemeData(color: kind.accent, size: 18),
                  child: leading,
                ),
                const SizedBox(width: 10), // `.rail-item { gap: 10px }`
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.1,
                          color: MoshColors.fg1,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2), // `.rail-text { gap: 2px }`
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            height: 1.1,
                            color: MoshColors.fg4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...<Widget>[
                  const SizedBox(width: 10),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// React `.rail-divider` — a full-width hairline at rgba(255,255,255,0.08)
/// in the expanded rail.
class RailDivider extends StatelessWidget {
  const RailDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: kRailListGap),
      child: Container(
        height: 1,
        color: Colors.white.withValues(alpha: 0.08),
      ),
    );
  }
}

/// React `.rail-new` — the dashed moss "New chat" button at the top of the
/// rail: full width, 40px tall, radius 12, a 1.5px dashed moss border at
/// 35% alpha, a moss plus glyph and a 12.5px/700 --fg-1 label.
///
/// Flutter has no dashed border primitive; a 1.5px solid moss border at the
/// same alpha is the closest single-widget equivalent and keeps the row
/// reading as an outlined affordance rather than a filled one.
class RailNewButton extends StatelessWidget {
  const RailNewButton({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        // `.rail-new:hover { background: var(--moss-glow) }`.
        hoverColor: MoshColors.mossGlow,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: MoshColors.moss.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.add, size: 18, color: MoshColors.moss),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: MoshColors.fg1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
