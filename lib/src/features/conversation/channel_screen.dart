import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/state/chat_names_provider.dart';
import 'package:mosh/src/features/conversation/rename_chat_dialog.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_app_bar.dart';
import 'package:mosh/src/features/conversation/conversation_header_title.dart';
import 'package:mosh/src/features/conversation/conversation_screen.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ChannelTarget, ConversationKind;

class ChannelScreen extends ConsumerWidget {
  const ChannelScreen({super.key, required this.name});

  /// The channel name, which is also its identity.
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ChannelTarget(name);
    final personal = ref.watch(personalChatNameProvider(target.ref));
    final title = chatDisplayName('#$name', personal);
    return ConversationScreen(
      target: ChannelTarget(name),
      header: (context, chrome) => ConversationAppBar(
        chrome: chrome,
        kind: ConversationKind.channel,
        avatarName: title,
        title: ConversationHeaderTitle(
            name: title,
            onOpenDetails: chrome.onOpenPeerStatus,
            subtitle: AppLocalizations.of(context)!.channelNoticeTitle),
        leaveMenuLabel: AppLocalizations.of(context)!.channelLeaveLabel,
        leaveMenuIcon: Icons.logout,
        menuActions: [
          ChatHeaderMenuAction(
              label: AppLocalizations.of(context)!.chatRename,
              icon: Icons.edit_outlined,
              onSelect: () => showRenameChatDialog(context, target,
                  name: title,
                  originalName: '#$name',
                  hasPersonalName: personal != null))
        ],
      ),
    );
  }
}
