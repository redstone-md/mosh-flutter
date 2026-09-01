/// Pure UI-helper: unread-message counting and conversation diffing.
///
/// Ported 1:1 from `src/features/private-dm/notifications/unread.ts` per
/// ADR 0012. Free of any Flutter or I/O dependency so it can be unit-tested
/// in isolation; the one value type it borrows is [ConversationRef], the
/// one owner of the key grammar.
library;

import 'package:mosh/src/gateway/conversation_target.dart';

/// A conversation and its current total message count.
class ConversationCount {
  final String id;
  final int messageCount;

  const ConversationCount({required this.id, required this.messageCount});

  @override
  bool operator ==(Object other) =>
      other is ConversationCount &&
      other.id == id &&
      other.messageCount == messageCount;

  @override
  int get hashCode => Object.hash(id, messageCount);

  @override
  String toString() =>
      'ConversationCount(id: $id, messageCount: $messageCount)';
}

/// Authorship info for a single stored message.
///
/// Mirrors the TS `MessageAuthor`: `from_device` -> `fromDevice`,
/// `from_fingerprint` -> `fromFingerprint`. `fromFingerprint` is null for
/// 1:1 DMs (no fingerprint carried) and non-null for channels/groups.
class MessageAuthor {
  final String fromDevice;
  final String? fromFingerprint;

  const MessageAuthor({required this.fromDevice, this.fromFingerprint});

  @override
  bool operator ==(Object other) =>
      other is MessageAuthor &&
      other.fromDevice == fromDevice &&
      other.fromFingerprint == fromFingerprint;

  @override
  int get hashCode => Object.hash(fromDevice, fromFingerprint);

  @override
  String toString() =>
      'MessageAuthor(fromDevice: $fromDevice, fromFingerprint: $fromFingerprint)';
}

/// Counts messages NOT authored by the local participant.
///
/// When both `ownFingerprint` and `message.fromFingerprint` are present
/// (channels/groups), identity is compared by fingerprint: display names
/// are not unique, so a same-named peer must still count, and a renamed
/// self must not. DMs carry no fingerprint and fall back to the display
/// name (2-party, unambiguous). Mirrors the TS filter exactly.
int countMessagesFromOthers(
  List<MessageAuthor> messages,
  String ownDeviceName, [
  String? ownFingerprint,
]) {
  return messages.where((message) {
    if (ownFingerprint != null && message.fromFingerprint != null) {
      return message.fromFingerprint != ownFingerprint;
    }
    return message.fromDevice != ownDeviceName;
  }).length;
}

/// Notification title/body for a conversation that gained messages.
///
/// Mirrors `notificationBody` in unread.ts: channels render as `#<name>`,
/// every other kind renders the generic `New message`. [id] is a
/// conversation key, and [ConversationRef.tryParse] is the one reader of
/// that grammar -- a key that names no conversation renders the generic
/// label.
NotificationBody notificationBody(String id) {
  final conversation = ConversationRef.tryParse(id);
  final label =
      conversation != null && conversation.kind == ConversationKind.channel
          ? '#${conversation.id}'
          : 'New message';
  return NotificationBody(title: 'Mosh', body: '$label - new message');
}

/// Title/body pair returned by [notificationBody]. Value-equal so tests
/// can mirror the TS `toEqual`.
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

/// Compares current per-conversation message counts against last-seen
/// counts and reports which conversations gained messages worth
/// notifying about.
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
    nextLastSeen[conversation.id] = conversation.messageCount;
    final previous = lastSeen[conversation.id];
    if (previous == null) {
      continue;
    }
    final delta = conversation.messageCount - previous;
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
