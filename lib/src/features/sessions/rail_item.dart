import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/conversation/conversation_helpers.dart'
    show UnreadBadge;
import 'package:mosh/src/features/sessions/rail_compact.dart';
import 'package:mosh/src/features/shared/conversation_kind_style.dart';
import 'package:mosh/src/features/shared/focus_ring.dart';
import 'package:mosh/src/features/shared/resumed_ink.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;

/// Minimum height of one chat row; large text grows it.
const double kRailItemHeight = MoshSpace.s16;

/// Vertical gap between rows of the list.
const double kRailListGap = MoshSpace.s1;

/// Side padding of the chat list, and the gap between its sections.
const double kRailPadding = MoshSpace.s2;

/// Padding above and below the chat list.
const double kRailEdge = MoshSpace.s4;

/// Widest default width of the expanded rail pane: a 324 px row and the
/// list's side padding. Below it the default follows the window, and a drag
/// can widen the pane further.
const double kRailWidth = 340;

/// The Chat row card: the avatar in [leading], the name, when the last
/// message came and what it says, with the unread count beside it. The open
/// chat is the one filled row, the same for a person, a group and a channel.
/// A row whose menu is open stays pressed under it.
///
/// The tap target is one button named by the kind of conversation and the
/// visible text. In the collapsed list the row is a [CompactRailItem].
class RailItem extends StatelessWidget {
  const RailItem({
    super.key,
    required this.kind,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.timestamp,
    this.unreadCount = 0,
    this.active = false,
    this.menuOpen = false,
    this.onTap,
  });

  final ConversationKind kind;
  final Widget leading;
  final String title;
  final String subtitle;
  final String? timestamp;
  final int unreadCount;
  final bool active;
  final bool menuOpen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final kindLabel = l == null ? null : kind.label(l);
    if (RailCompactScope.of(context)) {
      return CompactRailItem(
        leading: leading,
        tooltip: title,
        label: [kindLabel ?? '', title, subtitle]
            .where((part) => part.isNotEmpty)
            .join('\n'),
        active: active,
        unreadCount: unreadCount,
        onTap: onTap,
      );
    }
    final colors = MoshColors.of(context);
    // The same corners in every state, so selecting a row moves nothing.
    const radius = MoshShapes.conversationRow;
    return Padding(
      padding: const EdgeInsets.only(bottom: kRailListGap),
      child: Semantics(
        container: true,
        button: true,
        selected: active,
        label: kindLabel,
        child: Material(
          color: active ? colors.secondaryContainer : Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          // On mobile the opened chat hides the rail and freezes the tap ink.
          child: ResumedInk(
            builder: (focusNode) => InkWell(
              focusNode: focusNode,
              onTap: onTap,
              child: FocusRing(radius: radius, child: _content(colors)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(MoshColors colors) => Container(
        // A floor, not a fixed height: large text grows the row.
        constraints: const BoxConstraints(minHeight: kRailItemHeight),
        color: menuOpen
            ? MoshState.tint(colors.onSurface, MoshState.pressed)
            : null,
        padding: const EdgeInsets.symmetric(
            horizontal: MoshSpace.s3, vertical: MoshSpace.s2),
        child: Row(
          spacing: MoshSpace.s3,
          children: <Widget>[
            ExcludeSemantics(child: leading),
            Expanded(
              child: _RailText(
                title: title,
                subtitle: subtitle,
                timestamp: timestamp,
                unreadCount: unreadCount,
                active: active,
              ),
            ),
          ],
        ),
      );
}

/// The row's name and time over its last message and unread count. A long
/// name and a long message are cut at the end; the tooltip shows them whole.
class _RailText extends StatelessWidget {
  const _RailText({
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.unreadCount,
    required this.active,
  });

  final String title;
  final String subtitle;
  final String? timestamp;
  final int unreadCount;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = MoshColors.of(context);
    // On the fill of the open chat the quiet inks fall under 4.5:1, so the
    // time and the message take the fill's own ink.
    final onFill = active ? colors.onSecondaryContainer : null;
    // The tooltip stays out of the semantics tree, which already reads both lines.
    return Tooltip(
      message: subtitle.isEmpty ? title : '$title\n$subtitle',
      waitDuration: const Duration(milliseconds: 500),
      excludeFromSemantics: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            spacing: MoshSpace.s2,
            children: [
              Expanded(child: _line(title, text.titleMedium!)),
              if (timestamp case final time?)
                Text(time,
                    style: text.labelMedium!
                        .copyWith(color: onFill ?? colors.onSurfaceMuted)),
            ],
          ),
          if (subtitle.isNotEmpty || unreadCount > 0)
            Row(
              spacing: MoshSpace.s2,
              children: [
                Expanded(
                  child: _line(
                      subtitle,
                      text.bodyMedium!
                          .copyWith(color: onFill ?? colors.onSurfaceVariant)),
                ),
                if (unreadCount > 0) UnreadBadge(count: unreadCount),
              ],
            ),
        ],
      ),
    );
  }

  Widget _line(String value, TextStyle style) =>
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
}

/// The hairline between the parts of the list.
class RailDivider extends StatelessWidget {
  const RailDivider({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(bottom: kRailListGap),
        child: Divider(),
      );
}
