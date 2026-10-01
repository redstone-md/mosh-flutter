/// A public channel. Everything but the title comes from the shared
/// conversation screen and the shared conversation AppBar.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_app_bar.dart';
import 'package:mosh/src/features/conversation/conversation_header_title.dart';
import 'package:mosh/src/features/conversation/conversation_screen.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ChannelTarget, ConversationKind;

class ChannelScreen extends StatelessWidget {
  const ChannelScreen({super.key, required this.name});

  /// The channel name, which is also its identity.
  final String name;

  @override
  Widget build(BuildContext context) => ConversationScreen(
        target: ChannelTarget(name),
        header: (context, chrome) => ConversationAppBar(
          kind: ConversationKind.channel,
          avatarName: '#$name',
          title: ConversationHeaderTitle(
              name: '#$name',
              subtitle: AppLocalizations.of(context)!.channelNoticeTitle),
          onOpenPeerStatus: chrome.onOpenPeerStatus,
          onRequestLeave: () => chrome.onRequestLeave(),
          filter: chrome.filter,
          onFilter: chrome.onFilter,
          mobileSearchOpen: chrome.mobileSearchOpen,
          onToggleMobileSearch: chrome.onToggleMobileSearch,
          leaveMenuLabel: AppLocalizations.of(context)!.channelLeaveLabel,
          leaveMenuIcon: Icons.logout,
        ),
      );
}
