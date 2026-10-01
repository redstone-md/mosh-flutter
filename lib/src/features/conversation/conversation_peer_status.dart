/// The peer-status drawer, opened from a conversation's header.
///
/// The drawer itself reads the raw runtime snapshot -- transport path, mesh,
/// members -- so this hands it whichever one the conversation has.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_details_panel.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import 'package:mosh/src/features/conversation/peer_status_drawer.dart';
import 'package:mosh/src/features/shared/conversation_action_error.dart';

class ConversationPeerStatus extends StatelessWidget {
  const ConversationPeerStatus({
    super.key,
    required this.async,
    required this.target,
    required this.onOpenAttachment,
    required this.onRefresh,
    required this.onClose,
  });

  /// The conversation, however far along its read is.
  final AsyncValue<ConversationSnapshot> async;

  final AnyConversationTarget target;
  final void Function(AttachmentDescriptor, AttachmentView?) onOpenAttachment;
  final VoidCallback onRefresh;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final snapshot = async.value;
    return PeerStatusDrawer(
      panel: ConversationDetailsPanel(
          target: target,
          async: async,
          onClose: onClose,
          onOpenAttachment: onOpenAttachment),
      session: snapshot is DmConversation ? snapshot.source : null,
      channel: snapshot is ChannelConversation ? snapshot.source : null,
      group: snapshot is GroupConversation ? snapshot.source : null,
      // Worded from the error's kind, never the runtime's raw message.
      error: async.hasError
          ? ConversationActionError.of(async.error!)
              .describe(AppLocalizations.of(context)!)
          : null,
      refreshing: false,
      onRefresh: onRefresh,
      onClose: onClose,
    );
  }
}
