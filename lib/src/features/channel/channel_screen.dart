/// A public channel. Everything but the header comes from the shared
/// conversation screen.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/chat_header_menu.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/conversation_screen.dart';
import 'package:mosh/src/features/conversation/conversation_tools.dart';
import 'package:mosh/src/features/shared/rail_back_button.dart';
import 'package:mosh/src/gateway/conversation_target.dart' show ChannelTarget;

class ChannelScreen extends StatelessWidget {
  const ChannelScreen({super.key, required this.name});

  /// The channel name, which is also its identity.
  final String name;

  @override
  Widget build(BuildContext context) => ConversationScreen(
        target: ChannelTarget(name),
        header: (context, hooks) => _ChannelHeader(name: name, hooks: hooks),
      );
}

/// The channel's app bar: its name, and the buttons that drive the shared
/// screen. On a narrow window the search and the leave action move into the
/// menu.
class _ChannelHeader extends StatelessWidget implements PreferredSizeWidget {
  const _ChannelHeader({required this.name, required this.hooks});

  final String name;
  final ConversationHeaderHooks hooks;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final mobile = isMobileBreakpoint(context);
    return AppBar(
      toolbarHeight: chatHeaderHeight(context),
      titleTextStyle: chatTitleStyle(context),
      leading: railBackButton(context),
      title: Text(name),
      actions: [
        if (mobile)
          MobileSearchToggle(
            open: hooks.mobileSearchOpen,
            onToggle: hooks.onToggleMobileSearch,
            l: l,
          ),
        ChatHeaderMenu(
          l: l,
          actions: [
            if (hooks.filter == ConversationFilter.attachments)
              ChatHeaderMenuAction(
                label: l.chatFilterAll,
                icon: Icons.chat_bubble_outline,
                onSelect: () => hooks.onFilter(ConversationFilter.all),
              )
            else
              ChatHeaderMenuAction(
                label: l.chatFilterAttachments,
                icon: Icons.attach_file,
                onSelect: () => hooks.onFilter(ConversationFilter.attachments),
              ),
            ChatHeaderMenuAction(
              label: l.channelLeaveLabel,
              icon: Icons.logout,
              danger: true,
              onSelect: hooks.onRequestLeave,
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.electrical_services, size: 18),
          tooltip: l.openPeerStatus,
          onPressed: hooks.onOpenPeerStatus,
        ),
        if (!mobile)
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l.channelLeaveLabel,
            onPressed: hooks.onRequestLeave,
          ),
      ],
    );
  }
}
