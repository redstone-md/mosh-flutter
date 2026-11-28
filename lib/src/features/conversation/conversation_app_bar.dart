import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/features/conversation/chat_header_menu.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/conversation_chrome.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart'
    show ConversationFilter, MobileSearchToggle, isMobileBreakpoint;
import 'package:mosh/src/features/shared/rail_back_button.dart';
import 'package:mosh/src/features/shared/conversation_kind_style.dart';
import 'package:mosh/src/gateway/conversation_target.dart';

// Re-exported so a kind header needs only this one import to build its
// kebab items.
export 'package:mosh/src/features/conversation/chat_header_menu.dart'
    show ChatHeaderMenuAction;

/// The Top bar card: who the conversation is with, how it is connected and
/// what can be done with it. A narrow window, and so every phone, leads with
/// the way back and takes the smaller avatar and the tighter spacing.
class ConversationAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const ConversationAppBar({
    super.key,
    required this.title,
    required this.chrome,
    required this.leaveMenuLabel,
    required this.leaveMenuIcon,
    this.avatarName,
    this.plusIdentity,
    this.kind = ConversationKind.dm,
    this.menuActions = const [],
    this.inlineActions = const [],
  });

  /// The name and short status, normally a `ConversationHeaderTitle`.
  final Widget title;
  final String? avatarName;
  final String? plusIdentity;
  final ConversationKind kind;

  /// The kebab's leave item: label + icon. The item is always `danger`.
  final String leaveMenuLabel;
  final IconData leaveMenuIcon;

  /// Kind-specific kebab items, rendered between the filter toggle and the
  /// leave item.
  final List<ChatHeaderMenuAction> menuActions;

  /// Kind-specific primary actions, rendered before search and the menu.
  final List<Widget> inlineActions;

  final ConversationChrome chrome;

  @override
  Size get preferredSize => const Size.fromHeight(kChatHeaderHeight);

  /// The filter toggle as a kebab item: attachments -> "All" (chat icon,
  /// flips to all); else "Files" (attach icon, flips to attachments).
  ChatHeaderMenuAction _filterAction(AppLocalizations l) =>
      switch (chrome.filter) {
        ConversationFilter.attachments => ChatHeaderMenuAction(
            label: l.chatFilterAll,
            icon: MoshIcons.chat,
            onSelect: () => chrome.onFilter(ConversationFilter.all),
          ),
        ConversationFilter.all => ChatHeaderMenuAction(
            label: l.chatFilterAttachments,
            icon: MoshIcons.attach,
            onSelect: () => chrome.onFilter(ConversationFilter.attachments),
          ),
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final narrow = isMobileBreakpoint(context);
    final edge = narrow ? MoshSpace.s1 : MoshSpace.s5;
    final back = railBackButton(context);
    return AppBar(
      leading: back == null
          ? null
          : Padding(
              padding: EdgeInsets.only(left: edge), child: Center(child: back)),
      leadingWidth: edge + MoshControl.height(Theme.of(context).platform),
      titleSpacing: back == null ? edge : MoshSpace.s2,
      title: _identity(l, narrow),
      actions: [
        Padding(
            padding: EdgeInsets.only(right: edge),
            child: Row(mainAxisSize: MainAxisSize.min, children: _actions(l))),
      ],
    );
  }

  Widget _identity(AppLocalizations l, bool narrow) => Row(
        children: [
          if (avatarName case final name?) ...[
            Semantics(
              label: l.chatDetailsTitle,
              button: true,
              child: InkWell(
                onTap: chrome.onOpenPeerStatus,
                customBorder: const CircleBorder(),
                child: ConversationKindAvatar(
                    kind: kind,
                    plusIdentity: plusIdentity,
                    name: name,
                    radius: narrow ? MoshSpace.s5 : MoshSpace.s6),
              ),
            ),
            SizedBox(width: narrow ? MoshSpace.s2 : MoshSpace.s3),
          ],
          Flexible(child: title),
        ],
      );

  List<Widget> _actions(AppLocalizations l) => [
        ...inlineActions,
        MobileSearchToggle(
            open: chrome.mobileSearchOpen,
            onToggle: chrome.onToggleMobileSearch,
            l: l),
        ChatHeaderMenu(l: l, actions: [
          ChatHeaderMenuAction(
              label: l.chatDetailsTitle,
              icon: MoshIcons.info,
              onSelect: chrome.onOpenPeerStatus),
          _filterAction(l),
          ...menuActions,
          ChatHeaderMenuAction(
              label: leaveMenuLabel,
              icon: leaveMenuIcon,
              danger: true,
              onSelect: chrome.onRequestLeave),
        ]),
      ];
}
