/// Shared conversation header with identity, search, kind actions and details.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/features/conversation/chat_header_menu.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/features/shared/rail_back_button.dart';
import 'package:mosh/src/features/shared/conversation_kind_style.dart';
import 'package:mosh/src/gateway/conversation_target.dart';

// Re-exported so a kind header needs only this one import to build its
// kebab items.
export 'package:mosh/src/features/conversation/chat_header_menu.dart'
    show ChatHeaderMenuAction;

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
    this.avatarName,
    this.kind = ConversationKind.dm,
    this.leadingActions = const [],
    this.menuActions = const [],
    this.inlineActions = const [],
  });

  /// The AppBar `title:` widget (usually a two-line Column: name + lock,
  /// then the status subtitle).
  final Widget title;
  final String? avatarName;
  final ConversationKind kind;

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
    return IconButtonTheme(
        data: IconButtonThemeData(
            style: IconButton.styleFrom(
          minimumSize: const Size.square(40),
          shape: MoshShapes.controlShape,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        )),
        child: AppBar(
          toolbarHeight: chatHeaderHeight(context),
          titleTextStyle: chatTitleStyle(context),
          leading: railBackButton(context),
          title: LayoutBuilder(
              builder: (context, constraints) => Row(children: [
                    if (avatarName != null && constraints.maxWidth >= 120) ...[
                      ConversationKindAvatar(
                          kind: kind, name: avatarName!, radius: 20),
                      const SizedBox(width: 12),
                    ],
                    Expanded(child: title),
                  ])),
          actions: [
            ...leadingActions,
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
              icon: const Icon(Icons.info_outline, size: 20),
              tooltip: l.chatDetailsTitle,
              onPressed: onOpenPeerStatus,
            ),
          ],
        ));
  }
}
