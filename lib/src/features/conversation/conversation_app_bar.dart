/// The AppBar skeleton every conversation kind (DM, channel, group) shares:
/// the rail back button, the mobile search toggle, the kebab menu (filter
/// toggle + leave), the peer-status button, and the desktop-only leave
/// button. Each kind passes its title plus its kind-specific buttons; the
/// mobile-vs-desktop action placement (search + leave in the kebab on
/// mobile, leave inline on desktop) lives HERE, once, instead of in each
/// header.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/chat_header_menu.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/features/shared/rail_back_button.dart';

// Re-exported so a kind header needs only this one import to build its
// kebab items.
export 'package:mosh/src/features/conversation/chat_header_menu.dart'
    show ChatHeaderMenuAction;

/// The conversation AppBar: one shared skeleton, kind-specific slots.
///
/// The `actions:` row, in order:
///   1. [leadingActions] -- kind badges/buttons left of everything else
///      (the group's admin-pill + copy-invite).
///   2. the mobile search toggle, mobile only.
///   3. [ChatHeaderMenu] -- the filter toggle first, then [menuActions],
///      then the leave item (danger) built from [leaveMenuLabel] +
///      [leaveMenuIcon]. Self-gates: renders nothing on desktop.
///   4. [inlineActions] -- kind buttons between the kebab and the
///      peer-status button (the DM's call button).
///   5. the peer-status button.
///   6. the desktop leave button ([desktopLeaveIcon] +
///      [desktopLeaveTooltip]), desktop only; on mobile the kebab's leave
///      item is the entry point instead.
///
/// The `leading:` is the shared [railBackButton] (mobile-only back to the
/// rail) and the `title:` is whatever [title] widget the kind builds.
class ConversationAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const ConversationAppBar({
    super.key,
    required this.title,
    required this.onOpenPeerStatus,
    required this.onRequestLeave,
    required this.filter,
    required this.onFilter,
    required this.mobileSearchOpen,
    required this.onToggleMobileSearch,
    required this.leaveMenuLabel,
    required this.leaveMenuIcon,
    required this.desktopLeaveIcon,
    required this.desktopLeaveTooltip,
    this.leadingActions = const [],
    this.menuActions = const [],
    this.inlineActions = const [],
  });

  /// The AppBar `title:` widget (usually a two-line Column: name + lock,
  /// then the status subtitle).
  final Widget title;

  final VoidCallback onOpenPeerStatus;
  final VoidCallback onRequestLeave;

  /// The conversation filter + its setter, both owned by the screen (the
  /// body's ConversationTools + the kebab's filter toggle both drive it).
  final ConversationFilter filter;
  final ValueChanged<ConversationFilter> onFilter;

  /// The mobile search panel open state + toggle, owned by the screen (the
  /// body's MobileConversationSearch reads the same value).
  final bool mobileSearchOpen;
  final VoidCallback onToggleMobileSearch;

  /// The kebab's leave item: label + icon. The item is always `danger`.
  final String leaveMenuLabel;
  final IconData leaveMenuIcon;

  /// The desktop-only leave button: its icon + tooltip.
  final Widget desktopLeaveIcon;
  final String desktopLeaveTooltip;

  /// Kind-specific `actions:` widgets rendered first (before the search
  /// toggle).
  final List<Widget> leadingActions;

  /// Kind-specific kebab items, rendered between the filter toggle and the
  /// leave item.
  final List<ChatHeaderMenuAction> menuActions;

  /// Kind-specific `actions:` widgets rendered between the kebab and the
  /// peer-status button.
  final List<Widget> inlineActions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  /// The filter toggle as a kebab item: attachments -> "All" (chat icon,
  /// flips to all); else "Files" (attach icon, flips to attachments).
  ChatHeaderMenuAction _filterAction(AppLocalizations l) => switch (filter) {
        ConversationFilter.attachments => ChatHeaderMenuAction(
            label: l.chatFilterAll,
            icon: Icons.chat_bubble_outline,
            onSelect: () => onFilter(ConversationFilter.all),
          ),
        ConversationFilter.all => ChatHeaderMenuAction(
            label: l.chatFilterAttachments,
            icon: Icons.attach_file,
            onSelect: () => onFilter(ConversationFilter.attachments),
          ),
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final mobile = isMobileBreakpoint(context);
    return AppBar(
      toolbarHeight: chatHeaderHeight(context),
      titleTextStyle: chatTitleStyle(context),
      leading: railBackButton(context),
      title: title,
      actions: [
        ...leadingActions,
        if (mobile)
          MobileSearchToggle(
            open: mobileSearchOpen,
            onToggle: onToggleMobileSearch,
            l: l,
          ),
        ChatHeaderMenu(
          l: l,
          actions: [
            _filterAction(l),
            ...menuActions,
            ChatHeaderMenuAction(
              label: leaveMenuLabel,
              icon: leaveMenuIcon,
              danger: true,
              onSelect: onRequestLeave,
            ),
          ],
        ),
        ...inlineActions,
        IconButton(
          icon: const Icon(Icons.electrical_services, size: 18),
          tooltip: l.openPeerStatus,
          onPressed: onOpenPeerStatus,
        ),
        if (!mobile)
          IconButton(
            icon: desktopLeaveIcon,
            tooltip: desktopLeaveTooltip,
            onPressed: onRequestLeave,
          ),
      ],
    );
  }
}
