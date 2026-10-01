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
import 'package:mosh/src/features/conversation/conversation_date_divider.dart';
import 'package:mosh/src/features/conversation/conversation_message_row.dart';
import 'package:mosh/src/features/conversation/conversation_snapshot.dart';
import 'package:mosh/src/features/conversation/conversation_sender_meta.dart';
import 'package:mosh/src/features/conversation/message_copy.dart';
import 'package:mosh/src/gateway/conversation_target.dart'
    show ConversationKind;
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
  if (!DateUtils.isSameDay(messageDate(previousMs), messageDate(currentMs))) {
    return false;
  }
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

/// Renders the visible messages of one conversation. Their text can be
/// selected and copied; see [MessageSelectionArea]. Newly arriving messages
/// animate in (fade + slight slide up + micro-scale) like in Telegram,
/// while initial messages skip animation on load.
class ConversationMessageListView extends StatefulWidget {
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
  State<ConversationMessageListView> createState() =>
      _ConversationMessageListViewState();
}

class _ConversationMessageListViewState
    extends State<ConversationMessageListView> {
  final Set<String> _seenMessageIds = <String>{};
  final Set<String> _newIncomingIds = <String>{};
  String? _lastTargetId;

  @override
  void initState() {
    super.initState();
    _lastTargetId = widget.snapshot.target.id;
    for (final m in widget.messages) {
      _seenMessageIds.add(_messageKey(m));
    }
  }

  @override
  void didUpdateWidget(covariant ConversationMessageListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.snapshot.target.id != _lastTargetId) {
      _lastTargetId = widget.snapshot.target.id;
      _seenMessageIds.clear();
      _newIncomingIds.clear();
      for (final m in widget.messages) {
        _seenMessageIds.add(_messageKey(m));
      }
      return;
    }

    _newIncomingIds.clear();
    for (final m in widget.messages) {
      final key = _messageKey(m);
      if (!_seenMessageIds.contains(key)) {
        _seenMessageIds.add(key);
        // Only newly arrived incoming messages animate.
        if (!m.own) {
          _newIncomingIds.add(key);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final kind = widget.snapshot.target.kind;
    final rows = groupConversationMessages(widget.messages).reversed.toList();
    return MessageSelectionArea(
      child: ListView.builder(
        padding: kChatScrollPadding,
        reverse: true,
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final date = messageDate(rows[index].message.sentAtMs);
          final previous = index + 1 < rows.length
              ? messageDate(rows[index + 1].message.sentAtMs)
              : null;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (date != null && !DateUtils.isSameDay(date, previous))
                  ConversationDateDivider(date: date),
                _buildRow(context, rows[index], kind, l),
              ]);
        },
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    GroupedConversationMessage row,
    ConversationKind kind,
    AppLocalizations l,
  ) {
    final attachment = row.message.attachment;
    final view = attachment == null
        ? null
        : widget.snapshot.attachmentView(attachment.attachmentId);
    final callbacks = widget.attachmentCallbacks(view);
    final body = row.message.body;
    final messageRow = ConversationMessageRow(
      message: row.message,
      kind: kind,
      grouped: row.grouped,
      attachmentView: view,
      peer: widget.peer,
      busy: callbacks.busy,
      onAttachmentDownload: callbacks.onDownload,
      onAttachmentCancel: callbacks.onCancel,
      onAttachmentOpen: callbacks.onOpen,
      onRetry: widget.onRetryMessage,
      l: l,
    );
    final wrapped = body.isEmpty
        ? messageRow
        : CopyableMessage(body: body, child: messageRow);

    final id = _messageKey(row.message);
    return _AnimatedMessageRow(
      key: ValueKey(id),
      animate: _newIncomingIds.contains(id),
      child: wrapped,
    );
  }

  String _messageKey(ConversationMessage m) =>
      m.messageId ??
      '${m.fromDevice}:${m.sentAtMs}:${m.body}:${identityHashCode(m)}';
}

/// Telegram-style entrance animation for newly arriving messages: subtle
/// fade-in + slight slide-up + micro-scale with an ease-out cubic curve.
class _AnimatedMessageRow extends StatefulWidget {
  const _AnimatedMessageRow({
    super.key,
    required this.animate,
    required this.child,
  });

  final bool animate;
  final Widget child;

  @override
  State<_AnimatedMessageRow> createState() => _AnimatedMessageRowState();
}

class _AnimatedMessageRowState extends State<_AnimatedMessageRow>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _fadeAnimation;
  Animation<Offset>? _slideAnimation;
  Animation<double>? _scaleAnimation;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      final controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 240),
      );
      _controller = controller;
      final curve = CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutCubic,
      );
      _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curve);
      _slideAnimation = Tween<Offset>(
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(curve);
      _scaleAnimation = Tween<double>(begin: 0.94, end: 1.0).animate(curve);
      controller.addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {});
        }
      });
      controller.forward();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || controller.isCompleted) return widget.child;
    return FadeTransition(
      opacity: _fadeAnimation!,
      child: SlideTransition(
        position: _slideAnimation!,
        child: ScaleTransition(
          scale: _scaleAnimation!,
          alignment: Alignment.bottomLeft,
          child: widget.child,
        ),
      ),
    );
  }
}
