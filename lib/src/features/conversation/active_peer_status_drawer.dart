import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/conversation_action_error.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/state/active_conversation_key_provider.dart';
import 'package:mosh/src/state/channel_group_providers.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/session_providers.dart';

import 'peer_status_drawer.dart';

/// Selected-conversation diagnostics, shared by the main frame and chat shell.
class ActivePeerStatusDrawer extends ConsumerWidget {
  const ActivePeerStatusDrawer({super.key, required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeConversationProvider);
    final dm = active?.kind == ConversationKind.dm
        ? ref.watch(activeSessionProvider(active!.arg))
        : null;
    final channel = active?.kind == ConversationKind.channel
        ? ref.watch(channelSnapshotProvider(active!.arg))
        : null;
    final group = active?.kind == ConversationKind.group
        ? ref.watch(groupSnapshotProvider(active!.arg))
        : null;
    final error = dm?.error ?? channel?.error ?? group?.error;
    return PeerStatusDrawer(
      session: dm?.value,
      channel: channel?.value,
      group: group?.value,
      error: error == null
          ? null
          : ConversationActionError.of(error)
              .describe(AppLocalizations.of(context)!),
      refreshing: false,
      onClose: onClose,
      onRefresh: () {
        if (active != null) {
          invalidateConversation(ref.invalidate, active.conversation);
        }
      },
    );
  }
}
