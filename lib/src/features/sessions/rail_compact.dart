import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/sessions/rail_item.dart';
import 'package:mosh/src/features/sessions/sessions_list_controls.dart'
    show chatListSearchFocusProvider;
import 'package:mosh/src/features/shared/avatar.dart';
import 'package:mosh/src/features/shared/conversation_kind_style.dart';
import 'package:mosh/src/features/shared/focus_ring.dart';
import 'package:mosh/src/features/shared/resumed_ink.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
import 'package:mosh/src/state/rail_layout_provider.dart';

/// Width of the collapsed chat list: one avatar column.
const double kRailCompactWidth = 80;

/// Side of a collapsed row's square tap target.
const double _kCompactItem = 56;

/// Whether the chat list below is collapsed to its avatar strip. Only the
/// desktop shell collapses it; without a scope the list is expanded.
class RailCompactScope extends InheritedWidget {
  const RailCompactScope(
      {super.key, required this.compact, required super.child});

  final bool compact;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RailCompactScope>()?.compact ??
      false;

  @override
  bool updateShouldNotify(RailCompactScope oldWidget) =>
      compact != oldWidget.compact;
}

/// Expands the collapsed chat list, optionally focusing its search once
/// the field is back.
void expandChatList(WidgetRef ref, {bool focusSearch = false}) {
  final layout = ref.read(railLayoutProvider);
  if (layout.collapsed) {
    ref
        .read(railLayoutProvider.notifier)
        .set(layout.copyWith(collapsed: false));
  }
  if (!focusSearch) return;
  WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(chatListSearchFocusProvider).requestFocus());
}

/// A collapsed rail row: the avatar with its unread badge on the corner,
/// the name in a tooltip and the whole row for screen readers. A row with a
/// second action, such as an invitation, expands the list instead of
/// acting, so a click on an avatar never accepts anything.
class CompactRailItem extends ConsumerWidget {
  const CompactRailItem({super.key, required this.item});

  final RailItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final kind = item.kind.conversationKind;
    final onTap = item.action == null ? item.onTap : () => expandChatList(ref);
    final label = item.semanticLabel ??
        [if (l != null) kind.label(l), item.title, item.subtitle]
            .where((part) => part.isNotEmpty)
            .join('\n');
    const radius = MoshShapes.conversationRow;
    return Padding(
      padding: const EdgeInsets.only(bottom: kRailListGap),
      child: Tooltip(
        message: item.title,
        excludeFromSemantics: true,
        child: Semantics(
          container: true,
          button: true,
          selected: item.active,
          label: label,
          onTap: onTap,
          child: Material(
            color: item.active ? kind.tint : Colors.transparent,
            borderRadius: radius,
            child: ResumedInk(
              child: InkWell(
                borderRadius: radius,
                onTap: onTap,
                child: FocusRing(radius: radius, child: _tile(kind, radius)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The avatar, the active ring and the unread badge on the corner.
  Widget _tile(ConversationKind kind, BorderRadius radius) => Container(
        width: _kCompactItem,
        height: _kCompactItem,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: item.active
              ? Border.all(color: kind.accent.withValues(alpha: 0.4))
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            ExcludeSemantics(
              child: IconTheme.merge(
                data: IconThemeData(color: kind.accent, size: 18),
                child: item.leading,
              ),
            ),
            if (item.trailing case final badge?)
              PositionedDirectional(top: 2, end: 0, child: badge),
          ],
        ),
      );
}

/// A square icon control of the collapsed list, named by its tooltip.
class CompactRailButton extends StatelessWidget {
  const CompactRailButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onTap;

  /// The creation action keeps its moss disc; other buttons stay quiet.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    const radius = MoshShapes.control;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: filled ? Colors.transparent : MoshColors.bg2,
          borderRadius: radius,
          child: ResumedInk(
            child: InkWell(
              borderRadius: radius,
              onTap: onTap,
              hoverColor: filled ? MoshColors.mossGlow : MoshColors.bg3,
              child: FocusRing(
                radius: radius,
                child: SizedBox.square(
                  dimension: _kCompactItem,
                  child: Center(child: ExcludeSemantics(child: icon)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The creation disc, as the expanded New button draws it.
const Widget kCompactNewIcon = CircleAvatar(
  radius: 16,
  backgroundColor: MoshColors.moss,
  child: Icon(Icons.add, size: 20, color: MoshColors.mossInk),
);

/// An organization in the collapsed list: its avatar, which expands the
/// list to the full section.
class CompactOrgButton extends ConsumerWidget {
  const CompactOrgButton({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.only(bottom: kRailListGap),
        child: CompactRailButton(
          icon: Avatar(name: name, radius: 20),
          label: name,
          filled: true,
          onTap: () => expandChatList(ref),
        ),
      );
}
