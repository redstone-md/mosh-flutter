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
          chrome: chrome,
          kind: ConversationKind.channel,
          avatarName: '#$name',
          title: ConversationHeaderTitle(
              name: '#$name',
              onOpenDetails: chrome.onOpenPeerStatus,
              subtitle: AppLocalizations.of(context)!.channelNoticeTitle),
          leaveMenuLabel: AppLocalizations.of(context)!.channelLeaveLabel,
          leaveMenuIcon: Icons.logout,
        ),
      );
}
