/// A public channel. Everything but the title comes from the shared
/// conversation screen and the shared conversation AppBar.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_app_bar.dart';
import 'package:mosh/src/features/conversation/conversation_screen.dart';
import 'package:mosh/src/gateway/conversation_target.dart' show ChannelTarget;

class ChannelScreen extends StatelessWidget {
  const ChannelScreen({super.key, required this.name});

  /// The channel name, which is also its identity.
  final String name;

  @override
  Widget build(BuildContext context) => ConversationScreen(
        target: ChannelTarget(name),
        header: (context, chrome) => ConversationAppBar(
          title: Text(name),
          onOpenPeerStatus: chrome.onOpenPeerStatus,
          onRequestLeave: () => chrome.onRequestLeave(),
          filter: chrome.filter,
          onFilter: chrome.onFilter,
          mobileSearchOpen: chrome.mobileSearchOpen,
          onToggleMobileSearch: chrome.onToggleMobileSearch,
          leaveMenuLabel: AppLocalizations.of(context)!.channelLeaveLabel,
          leaveMenuIcon: Icons.logout,
          desktopLeaveIcon: const Icon(Icons.logout),
          desktopLeaveTooltip: AppLocalizations.of(context)!.channelLeaveLabel,
        ),
      );
}
