import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart'
    show MoshColors, moshTonalIconButtonStyle;
import 'package:mosh/src/features/conversation/conversation_helpers.dart'
    show UnreadBadge;
import 'package:mosh/src/features/sessions/rail_item.dart';
import 'package:mosh/src/features/sessions/sessions_list_controls.dart'
    show chatListSearchFocusProvider;
import 'package:mosh/src/features/shared/focus_ring.dart';
import 'package:mosh/src/features/shared/resumed_ink.dart';
import 'package:mosh/src/state/rail_layout_provider.dart';

/// Width of the collapsed chat list: one column of [kRailItemHeight] rows
/// inside the list's side padding.
const double kRailCompactWidth = kRailItemHeight + 2 * kRailPadding;

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

/// The Compact chat row card: the avatar in [leading] with the unread count
/// on its corner, the name in [tooltip] and the whole row in [label] for
/// screen readers. [hint] says what a tap does when it does not open a chat.
class CompactRailItem extends StatelessWidget {
  const CompactRailItem({
    super.key,
    required this.leading,
    required this.tooltip,
    required this.label,
    required this.onTap,
    this.hint,
    this.active = false,
    this.unreadCount = 0,
  });

  final Widget leading;
  final String tooltip;
  final String label;
  final VoidCallback? onTap;
  final String? hint;
  final bool active;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    const radius = MoshShapes.conversationRow;
    return Padding(
      // The collapsed list is one column with the gap of its buttons.
      padding: const EdgeInsets.only(bottom: kRailPadding),
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: Semantics(
          container: true,
          button: true,
          selected: active,
          label: label,
          hint: hint,
          onTap: onTap,
          child: Material(
            color: active ? colors.secondaryContainer : Colors.transparent,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: ResumedInk(
              builder: (focusNode) => InkWell(
                focusNode: focusNode,
                onTap: onTap,
                child: FocusRing(radius: radius, child: _tile()),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The avatar and the unread badge on the corner.
  Widget _tile() => SizedBox.square(
        dimension: kRailItemHeight,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ExcludeSemantics(child: leading),
            if (unreadCount > 0)
              PositionedDirectional(
                  top: MoshSpace.s1,
                  end: MoshSpace.s1,
                  child:
                      ExcludeSemantics(child: UnreadBadge(count: unreadCount))),
          ],
        ),
      );
}

/// A row of the collapsed list that only expands it: an invitation or an
/// organisation, so a click on an avatar never accepts or changes anything.
class CompactExpandItem extends ConsumerWidget {
  const CompactExpandItem(
      {super.key, required this.leading, required this.name, this.detail = ''});

  final Widget leading;
  final String name;
  final String detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) => CompactRailItem(
        leading: leading,
        tooltip: name,
        label: detail.isEmpty ? name : '$name\n$detail',
        hint: AppLocalizations.of(context)?.chatListExpand,
        onTap: () => expandChatList(ref),
      );
}

/// A control of the collapsed list: the tonal Icon button at the phone's
/// 48 px, named by its tooltip. [fill] and [ink] recolour the one that
/// starts a conversation, and [ink] alone the one that reports a failure.
class CompactRailButton extends StatelessWidget {
  const CompactRailButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.fill,
    this.ink,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? fill;
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    final content = ink ?? colors.onSurface;
    final style = moshTonalIconButtonStyle(colors).copyWith(
      fixedSize: const WidgetStatePropertyAll(Size.square(MoshSpace.s12)),
      iconSize: const WidgetStatePropertyAll(MoshSpace.s6),
      foregroundColor: WidgetStatePropertyAll(content),
      backgroundColor: fill == null ? null : WidgetStatePropertyAll(fill),
      overlayColor: MoshState.layer(content),
    );
    // A covering route freezes the press ink; a fresh button drops it.
    return ResumedInk(
      builder: (focusNode) => IconButton(
        focusNode: focusNode,
        style: style,
        tooltip: label,
        onPressed: onTap,
        icon: Icon(icon),
      ),
    );
  }
}
