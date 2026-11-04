import 'package:mosh/src/gateway/conversation_target.dart';

/// A conversation and its current unread count.
class ConversationCount {
  final String id;
  final int unread;

  const ConversationCount({required this.id, required this.unread});

  @override
  bool operator ==(Object other) =>
      other is ConversationCount && other.id == id && other.unread == unread;

  @override
  int get hashCode => Object.hash(id, unread);

  @override
  String toString() => 'ConversationCount(id: $id, unread: $unread)';
}

/// Notification title/body for a conversation that gained messages.
///
/// Channels render as `#<name>`, every other kind renders the generic
/// `New message`. [id] is a conversation key, and
/// [ConversationRef.tryParse] is the one reader of that grammar -- a key
/// that names no conversation renders the generic label.
NotificationBody notificationBody(String id) {
  final conversation = ConversationRef.tryParse(id);
  final label =
      conversation != null && conversation.kind == ConversationKind.channel
          ? '#${conversation.id}'
          : 'New message';
  return NotificationBody(title: 'Mosh', body: '$label - new message');
}

/// Title/body pair returned by [notificationBody]. Value-equal so tests
/// can compare directly.
class NotificationBody {
  final String title;
  final String body;

  const NotificationBody({required this.title, required this.body});

  @override
  bool operator ==(Object other) =>
      other is NotificationBody && other.title == title && other.body == body;

  @override
  int get hashCode => Object.hash(title, body);

  @override
  String toString() => 'NotificationBody(title: $title, body: $body)';
}

/// A conversation that gained `delta` messages since it was last seen.
class NewMessages {
  final String id;
  final int delta;

  const NewMessages({required this.id, required this.delta});

  @override
  bool operator ==(Object other) =>
      other is NewMessages && other.id == id && other.delta == delta;

  @override
  int get hashCode => Object.hash(id, delta);

  @override
  String toString() => 'NewMessages(id: $id, delta: $delta)';
}

/// Result of one poll diff.
class UnreadDiff {
  final List<NewMessages> newMessages;
  final Map<String, int> nextLastSeen;

  const UnreadDiff({required this.newMessages, required this.nextLastSeen});

  @override
  bool operator ==(Object other) =>
      other is UnreadDiff &&
      other.newMessages == newMessages &&
      other.nextLastSeen == nextLastSeen;

  @override
  int get hashCode => Object.hash(newMessages, nextLastSeen);
}

/// Compares current per-conversation unread counts against the previous
/// poll's and reports which conversations gained messages worth notifying
/// about.
///
/// A conversation reports new messages when its count grew AND it is not
/// the currently-active conversation — unless the window is unfocused,
/// in which case even the active conversation reports. A conversation
/// seen for the first time never reports (no baseline). `nextLastSeen`
/// always advances every conversation to its current count.
UnreadDiff diffConversations(
  List<ConversationCount> current,
  Map<String, int> lastSeen,
  String? activeId,
  bool windowUnfocused,
) {
  final newMessages = <NewMessages>[];
  final nextLastSeen = <String, int>{};
  for (final conversation in current) {
    nextLastSeen[conversation.id] = conversation.unread;
    final previous = lastSeen[conversation.id];
    if (previous == null) {
      continue;
    }
    final delta = conversation.unread - previous;
    if (delta <= 0) {
      continue;
    }
    final isActive = conversation.id == activeId;
    if (isActive && !windowUnfocused) {
      continue;
    }
    newMessages.add(NewMessages(id: conversation.id, delta: delta));
  }
  return UnreadDiff(newMessages: newMessages, nextLastSeen: nextLastSeen);
}
