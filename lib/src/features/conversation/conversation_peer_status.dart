/// The peer-status drawer, opened from a conversation's header.
///
/// The drawer itself reads the raw runtime snapshot -- transport path, mesh,
/// members -- so this hands it whichever one the conversation has.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/peer_status_drawer.dart';

class ConversationPeerStatus extends StatelessWidget {
  const ConversationPeerStatus({
    super.key,
    required this.async,
    required this.onRefresh,
    required this.onClose,
  });

  /// The conversation, however far along its read is.
  final AsyncValue<ConversationSnapshot> async;

  final VoidCallback onRefresh;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final snapshot = async.value;
    return PeerStatusDrawer(
      session: snapshot is DmConversation ? snapshot.source : null,
      channel: snapshot is ChannelConversation ? snapshot.source : null,
      group: snapshot is GroupConversation ? snapshot.source : null,
      error: async.hasError ? async.error.toString() : null,
      refreshing: false,
      onRefresh: onRefresh,
      onClose: onClose,
    );
  }
}
