/// The message list, for any kind of conversation.
///
/// It groups the messages, then renders them newest-at-the-bottom. Grouping
/// follows the sender: consecutive messages from the same sender within five
/// minutes become one block, and only the first row of a block shows the
/// sender meta.
library;

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/conversation/conversation_helpers.dart';
import 'package:mosh/src/features/conversation/conversation_message_row.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_sender_meta.dart';
import 'package:mosh/src/rust/conversation/attachments.dart'
    show AttachmentDescriptor, AttachmentView;

/// How long a gap can be before the next message starts a new block.
const Duration conversationGroupWindow = Duration(minutes: 5);

/// A message plus whether it continues the block above it.
@immutable
class GroupedConversationMessage {
  const GroupedConversationMessage({
    required this.message,
    required this.grouped,
  });

  final ConversationMessage message;
  final bool grouped;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupedConversationMessage &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          grouped == other.grouped;

  @override
  int get hashCode => Object.hash(message, grouped);
}

/// Works out the block boundaries, oldest first. The first message never
/// continues a block. A later one does when it has the same sender, both
/// messages carry a time, time moves forward, and the gap fits inside
/// [conversationGroupWindow]. A missing time always starts a new block.
List<GroupedConversationMessage> groupConversationMessages(
  List<ConversationMessage> messages,
) {
  final grouped = <GroupedConversationMessage>[];
  for (var i = 0; i < messages.length; i++) {
    grouped.add(GroupedConversationMessage(
      message: messages[i],
      grouped: i > 0 && _continuesBlock(messages[i - 1], messages[i]),
    ));
  }
  return grouped;
}

bool _continuesBlock(
    ConversationMessage previous, ConversationMessage current) {
  final previousMs = previous.sentAtMs;
  final currentMs = current.sentAtMs;
  if (previousMs == null || currentMs == null) return false;
  if (previous.senderKey != current.senderKey) return false;
  if (currentMs < previousMs) return false;
  return currentMs - previousMs <=
      BigInt.from(conversationGroupWindow.inMilliseconds);
}

/// What one attachment card can do. Built per row, so Open resolves this
/// row's own transfer state.
@immutable
class ConversationAttachmentCallbacks {
  const ConversationAttachmentCallbacks({
    required this.busy,
    required this.onDownload,
    required this.onCancel,
    required this.onOpen,
  });

  /// True while another transfer is running.
  final bool busy;

  final void Function(String attachmentId) onDownload;
  final void Function(String attachmentId) onCancel;
  final void Function(AttachmentDescriptor descriptor) onOpen;
}

/// Renders the visible messages of one conversation.
class ConversationMessageListView extends StatelessWidget {
  const ConversationMessageListView({
    super.key,
    required this.messages,
    required this.snapshot,
    required this.attachmentCallbacks,
    required this.onRetryMessage,
    this.peer,
  });

  /// The messages to show, already filtered, oldest first.
  final List<ConversationMessage> messages;

  /// The conversation they came from. Read for its kind and its attachment
  /// transfer state.
  final ConversationSnapshot snapshot;

  final ConversationAttachmentCallbacks Function(AttachmentView? view)
      attachmentCallbacks;

  /// Sends a failed message again.
  final void Function(String messageId) onRetryMessage;

  /// Peer actions for the sender names. Null in a DM.
  final PeerActions? peer;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final kind = snapshot.target.kind;
    // Grouped oldest first, then reversed: the list itself is reversed so
    // the newest message sits at the bottom.
    final rows = groupConversationMessages(messages).reversed.toList();
    return ListView.builder(
      padding: kChatScrollPadding,
      reverse: true,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final attachment = row.message.attachment;
        final view = attachment == null
            ? null
            : snapshot.attachmentView(attachment.attachmentId);
        final callbacks = attachmentCallbacks(view);
        return ConversationMessageRow(
          message: row.message,
          kind: kind,
          grouped: row.grouped,
          attachmentView: view,
          peer: peer,
          busy: callbacks.busy,
          onAttachmentDownload: callbacks.onDownload,
          onAttachmentCancel: callbacks.onCancel,
          onAttachmentOpen: callbacks.onOpen,
          onRetry: onRetryMessage,
          l: l,
        );
      },
    );
  }
}
