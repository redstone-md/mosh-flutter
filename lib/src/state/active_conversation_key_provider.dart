// The currently-active conversation key, 1-1 with React's
// `activeConversationKey` (private-dm-screen.tsx): `'dm:<id>'` /
// `'channel:<name>'` / `'group:<id>'` or null when no conversation is open.
//
// This is the small prerequisite state for the unread-lifecycle diff
// (clearOnActive + window-focus toasts): React passes `activeKey` into
// `useUnreadNotifications` and clears it on close. The Flutter side keeps
// the same value in a Riverpod Notifier so the lifecycle provider can read
// it + the chat screens can set/clear it on open/leave without threading a
// prop through every rebuild.
//
// Set by the sessions rail on select + the chat screens on open (initState);
// cleared on leave/close. null = no conversation open (React's empty-string
// `activeConversationKey` maps to `activeKey: null`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/src/gateway/conversation_target.dart';

/// Holds the active conversation key (`'dm:<id>'` / `'channel:<name>'` /
/// `'group:<id>'`) or null when nothing is open. Mirrors React's
/// `activeConversationKey || null` shape passed to `useUnreadNotifications`.
final activeConversationKeyProvider =
    NotifierProvider<_ActiveConversationKeyNotifier, String?>(
  _ActiveConversationKeyNotifier.new,
);

/// The active-conversation kind, parsed from the key prefix ('dm:' /
/// 'channel:' / 'group:'). Mirrors React's branch test on `activeSession` /
/// `activeChannel` / `activeGroup` (private-dm-screen.tsx L282-292).
enum ActiveConversationKind { dm, channel, group }

/// Parsed active key: the kind discriminator plus the snapshot-family
/// argument (sessionId / channel name / groupId -- the suffix after the
/// ':' prefix).
class ActiveConversation {
  const ActiveConversation({required this.kind, required this.arg});

  final ActiveConversationKind kind;
  final String arg;

  /// Reads a key back, or returns null when it names no conversation.
  ///
  /// [ConversationRef.tryParse] owns the grammar; this keeps only the
  /// projection the existing callers read, so a key with an empty id is now
  /// "nothing open" instead of a conversation with a blank arg.
  static ActiveConversation? parse(String? key) {
    final ref = ConversationRef.tryParse(key);
    if (ref == null) return null;
    return ActiveConversation(kind: _kindOf(ref.kind), arg: ref.id);
  }

  /// The two kind enums carry the same three names; [ActiveConversation] keeps
  /// its own so the state layer does not re-export the Gateway's. Ticket 09
  /// collapses them.
  static ActiveConversationKind _kindOf(ConversationKind kind) =>
      switch (kind) {
        ConversationKind.dm => ActiveConversationKind.dm,
        ConversationKind.channel => ActiveConversationKind.channel,
        ConversationKind.group => ActiveConversationKind.group,
      };
}

/// The parsed [ActiveConversation] for the current key, or null when no
/// conversation is open. The single parse site for the titlebar, the shell
/// drawer, and the auto-poll loop.
final activeConversationProvider = Provider<ActiveConversation?>(
  (ref) => ActiveConversation.parse(ref.watch(activeConversationKeyProvider)),
);

class _ActiveConversationKeyNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Sets the active conversation key (called on open/select).
  void set(String? key) {
    if (state == key) return;
    state = key;
  }

  /// Clears the active key to null (called on leave/close).
  void clear() {
    if (state == null) return;
    state = null;
  }
}
