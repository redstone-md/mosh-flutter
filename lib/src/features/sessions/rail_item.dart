// The rail row chrome.
//
// A rail row is at least 48px tall (large text grows it), radius 12, with
// 12px side padding and a 10px gap, holding a leading avatar/icon, a
// two-line text block (the theme's list-row title over its fg-2 subtitle)
// and the unread badge. Active is an inset 2px accent ring.
//
// The per-kind tints: a DM row is plain bg-2 with fg-2 glyphs, a channel
// row is channelTint (info at 10%) with info, and a group row is moss-glow
// with moss. The active ring follows the tint (info for channels, moss
// otherwise). Hover is a light wash over the tint, not a replacement.
library;

import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/focus_ring.dart';

/// Which rail-item variant a row is: the tint and the active ring both
/// follow from it.
enum RailItemKind { dm, channel, group }

/// Minimum height of one rail row; large text grows it.
const double kRailItemHeight = 48;

/// Minimum height of the pinned New chat and Settings buttons.
const double kRailButtonHeight = 40;

/// Vertical gap between rail rows.
const double kRailListGap = 8;

/// Padding around the rail and gap between its sections.
const double kRailPadding = 12;

/// Width of the expanded rail pane.
const double kRailWidth = 268;

/// Hover wash over any row tint: about one bg step lighter on bg2.
final Color _kHoverOverlay = Colors.white.withValues(alpha: 0.03);

extension on RailItemKind {
  Color get background => switch (this) {
        RailItemKind.dm => MoshColors.bg2,
        RailItemKind.channel => MoshColors.channelTint,
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
/// carries the unread badge. [action] is a second control (the offer's
/// dismiss X) laid out beside the row's tap target, never inside it, so
/// assistive tech sees two sibling buttons instead of one nested in the
/// other.
///
/// The tap target is one button whose name is the visible text, unless
/// [semanticLabel] replaces it.
class RailItem extends StatelessWidget {
  const RailItem({
    super.key,
    required this.kind,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.action,
    this.semanticLabel,
    this.active = false,
    this.onTap,
  });

  final RailItemKind kind;
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? action;
  final String? semanticLabel;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // The radius stays 12 in every state; the active ring is an inset
    // border and must not move the outer geometry (audit 2026-09-21:
    // radius jumped 12 -> 14 when a row was selected).
    final radius = BorderRadius.circular(12);
    return Padding(
      padding: const EdgeInsets.only(bottom: kRailListGap),
      child: Material(
        color: kind.background,
        borderRadius: radius,
        // Clips the tap target's ink to the row's corners when [action]
        // shares the row.
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          // `inset 0 0 0 2px <accent>`: painted over the row, so it neither
          // moves the content nor needs an (outset-only) BoxShadow.
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: active ? Border.all(color: kind.ring, width: 2) : null,
          ),
          child: Row(
            children: <Widget>[
              Expanded(child: _tapTarget(radius)),
              if (action case final action?) action,
            ],
          ),
        ),
      ),
    );
  }

  Widget _tapTarget(BorderRadius radius) {
    return Semantics(
      container: true,
      button: true,
      selected: active,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      // Excluding the children drops the InkWell's own tap action, so the
      // labelled row carries it here or a screen reader cannot activate it.
      onTap: semanticLabel == null ? null : onTap,
      child: InkWell(
        onTap: onTap,
        // An overlay, not an opaque fill, so the channel and group tints
        // still show through on hover.
        hoverColor: _kHoverOverlay,
        child: FocusRing(
          radius: radius,
          child: Container(
            // A floor, not a fixed height: large text grows the row.
            constraints: const BoxConstraints(minHeight: kRailItemHeight),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            child: Row(
              children: <Widget>[
                ExcludeSemantics(
                  child: IconTheme.merge(
                    data: IconThemeData(color: kind.accent, size: 18),
                    child: leading,
                  ),
                ),
                const SizedBox(width: 10), // `.rail-item { gap: 10px }`
                Expanded(
                  child: _RailText(title: title, subtitle: subtitle),
                ),
                if (trailing case final trailing?) ...<Widget>[
                  const SizedBox(width: 10),
                  trailing,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The row's title over its optional subtitle, in the theme's list-row
/// styles (the subtitle is fg2, which clears 4.5:1 on every row tint).
class _RailText extends StatelessWidget {
  const _RailText({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final styles = ListTileTheme.of(context);
    // Both lines ellipsize; the tooltip is the path to the full values. It
    // stays out of the semantics tree, which already reads both lines.
    return Tooltip(
      message: subtitle.isEmpty ? title : '$title\n$subtitle',
      waitDuration: const Duration(milliseconds: 500),
      excludeFromSemantics: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.titleTextStyle,
          ),
          if (subtitle.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2), // `.rail-text { gap: 2px }`
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.subtitleTextStyle,
            ),
          ],
        ],
      ),
    );
  }
}

/// A full-width [MoshColors.lineStrong] hairline.
class RailDivider extends StatelessWidget {
  const RailDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: kRailListGap),
      child: Container(
        height: 1,
        color: MoshColors.lineStrong,
      ),
    );
  }
}

/// The gear button pinned at the bottom of the rail: full width, at least
/// 40px tall, radius 12, a settings glyph and a 12.5px/600 fg-2 label.
/// Opens the Discord-like settings screen (AppRoutes.settings).
class RailSettingsButton extends StatelessWidget {
  const RailSettingsButton({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    // The fill lives on the Material so the InkWell's hover, press and
    // focus ink paint above it instead of under an opaque Container.
    return Semantics(
      button: true,
      child: Material(
        color: MoshColors.bg2,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          hoverColor: MoshColors.bg3,
          child: FocusRing(
            radius: radius,
            child: Container(
              constraints: const BoxConstraints(minHeight: kRailButtonHeight),
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.settings_outlined,
                      size: 18, color: MoshColors.fg2),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: MoshColors.fg2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dashed moss "New chat" button at the top of the rail: full width,
/// at least 40px tall, radius 12, a 1.5px dashed moss border at 35% alpha,
/// a moss plus glyph and a 12.5px/700 fg-1 label.
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
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        // `.rail-new:hover { background: var(--moss-glow) }`.
        hoverColor: MoshColors.mossGlow,
        child: FocusRing(
          radius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: kRailButtonHeight),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
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
      ),
    );
  }
}
